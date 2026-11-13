import Foundation

/// Error de la API con el mensaje de Laravel y, si es de validación (422), el primer error de cada campo.
nonisolated struct FallaAPI: Error, LocalizedError {
    let mensaje: String
    var campos: [String: String] = [:]
    /// El gasto pasa su presupuesto (error "presupuesto"): se elige de qué categorías cubrirlo y se reenvía.
    var presupuesto: ExcesoPresupuesto? = nil
    var errorDescription: String? { mensaje }
}

/// Cliente de la API de finanzas (requiere el token de Sanctum guardado en el Keychain).
/// Los JSON vienen en snake_case y se convierten solos a camelCase.
final class API {
    static let shared = API()
    private init() {}

    /// Se avisa cuando el token ya no sirve (401) para volver al login.
    static let sesionExpirada = Notification.Name("sesionExpirada")

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func get<T: Decodable>(_ ruta: String, _ parametros: [String: String?] = [:]) async throws -> T {
        try await pedir("GET", ruta, parametros: parametros, cuerpo: nil as Vacio?)
    }

    func post<T: Decodable, B: Encodable>(_ ruta: String, _ cuerpo: B) async throws -> T {
        try await pedir("POST", ruta, cuerpo: cuerpo)
    }

    func put<T: Decodable, B: Encodable>(_ ruta: String, _ cuerpo: B) async throws -> T {
        try await pedir("PUT", ruta, cuerpo: cuerpo)
    }

    func patch<T: Decodable, B: Encodable>(_ ruta: String, _ cuerpo: B) async throws -> T {
        try await pedir("PATCH", ruta, cuerpo: cuerpo)
    }

    /// Para peticiones cuya respuesta no interesa (204, DELETE…).
    func enviar<B: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: B? = nil as Vacio?) async throws {
        let _: Vacio = try await pedir(metodo, ruta, cuerpo: cuerpo, ignorarCuerpo: true)
    }

    func borrar(_ ruta: String, _ parametros: [String: String?] = [:]) async throws {
        let _: Vacio = try await pedir("DELETE", ruta, parametros: parametros, cuerpo: nil as Vacio?, ignorarCuerpo: true)
    }

    /// DELETE que devuelve el registro actualizado (ej. quitar el pago de un participante de un evento).
    func borrarDevolviendo<T: Decodable>(_ ruta: String) async throws -> T {
        try await pedir("DELETE", ruta, cuerpo: nil as Vacio?)
    }

    /// Formulario multipart con un archivo (fotos). PHP no lee archivos en PUT/PATCH: va como POST con "_method" en los campos.
    func subir<T: Decodable>(_ ruta: String, campos: [String: String], archivo: String, datos: Data, tipo: String = "image/jpeg") async throws -> T {
        let limite = "Limite-\(UUID().uuidString)"
        var cuerpo = Data()
        func agregar(_ texto: String) { cuerpo.append(Data(texto.utf8)) }
        for (k, v) in campos {
            agregar("--\(limite)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        agregar("--\(limite)\r\nContent-Disposition: form-data; name=\"\(archivo)\"; filename=\"foto.jpg\"\r\nContent-Type: \(tipo)\r\n\r\n")
        cuerpo.append(datos)
        agregar("\r\n--\(limite)--\r\n")
        return try await pedir("POST", ruta, cuerpo: nil as Vacio?, crudo: (cuerpo, "multipart/form-data; boundary=\(limite)"))
    }

    // MARK: - Interno

    private func pedir<T: Decodable, B: Encodable>(_ metodo: String, _ ruta: String, parametros: [String: String?] = [:], cuerpo: B?, ignorarCuerpo: Bool = false, crudo: (Data, String)? = nil) async throws -> T {
        guard var componentes = URLComponents(string: Constants.baseURL + ruta) else { throw FallaAPI(mensaje: "Dirección no válida.") }
        let items = parametros.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { componentes.queryItems = items }
        guard let url = componentes.url else { throw FallaAPI(mensaje: "Dirección no válida.") }

        var request = URLRequest(url: url)
        request.httpMethod = metodo
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainManager.shared.getToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let cuerpo {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(cuerpo)
        } else if let (datos, tipo) = crudo {
            request.setValue(tipo, forHTTPHeaderField: "Content-Type")
            request.httpBody = datos
        }

        let datos: Data
        let respuesta: URLResponse
        do {
            (datos, respuesta) = try await URLSession.shared.data(for: request)
        } catch {
            throw FallaAPI(mensaje: "No se pudo conectar con el servidor. Revisa tu conexión.")
        }
        let codigo = (respuesta as? HTTPURLResponse)?.statusCode ?? 0

        switch codigo {
        case 200...299:
            if ignorarCuerpo || datos.isEmpty, let vacio = Vacio() as? T { return vacio }
            do { return try decoder.decode(T.self, from: datos) } catch {
                throw FallaAPI(mensaje: "La respuesta del servidor no se pudo leer.")
            }
        case 401:
            _ = KeychainManager.shared.deleteToken()
            NotificationCenter.default.post(name: API.sesionExpirada, object: nil)
            throw FallaAPI(mensaje: "Tu sesión expiró. Vuelve a iniciar sesión.")
        case 403:
            throw FallaAPI(mensaje: "No tienes permiso para hacer esto.")
        default:
            let laravel = try? decoder.decode(ErrorLaravel.self, from: datos)
            let campos = (laravel?.errors ?? [:]).compactMapValues { $0.first }
            let mensaje = campos.values.first ?? laravel?.message ?? (codigo == 404 ? "No se encontró el registro." : "Error del servidor (\(codigo)).")
            throw FallaAPI(mensaje: mensaje, campos: campos, presupuesto: laravel?.presupuesto)
        }
    }

    /// Descarga una imagen privada (fotos de contactos) con el token; en caché mientras la app está abierta.
    private let cache = NSCache<NSURL, NSData>()

    /// Descarga un archivo (reportes en PDF, XLSX o CSV, la imagen de un evento) a la carpeta temporal y devuelve dónde quedó.
    func descargar(_ ruta: String, _ parametros: [String: String?], nombre: String? = nil) async throws -> URL {
        guard var componentes = URLComponents(string: Constants.baseURL + ruta) else { throw FallaAPI(mensaje: "Dirección no válida.") }
        componentes.queryItems = parametros.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        guard let url = componentes.url else { throw FallaAPI(mensaje: "Dirección no válida.") }
        var request = URLRequest(url: url)
        if let token = KeychainManager.shared.getToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (datos, respuesta) = try? await URLSession.shared.data(for: request), let http = respuesta as? HTTPURLResponse else {
            throw FallaAPI(mensaje: "No se pudo conectar con el servidor. Revisa tu conexión.")
        }
        switch http.statusCode {
        case 200: break
        case 403: throw FallaAPI(mensaje: "No tienes permiso para descargar esto.")
        case 401:
            NotificationCenter.default.post(name: API.sesionExpirada, object: nil)
            throw FallaAPI(mensaje: "Tu sesión expiró. Vuelve a iniciar sesión.")
        default: throw FallaAPI(mensaje: "No se pudo descargar el archivo (\(http.statusCode)).")
        }
        let nombre = nombre ?? (http.value(forHTTPHeaderField: "Content-Disposition")?.components(separatedBy: "filename=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))).flatMap { $0.isEmpty ? nil : $0 } ?? "reporte"
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("reportes", isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let destino = carpeta.appendingPathComponent(nombre)
        try datos.write(to: destino, options: .atomic)
        return destino
    }

    func olvidarImagen(_ direccion: String?) {
        if let d = direccion, let url = URL(string: d) { cache.removeObject(forKey: url as NSURL) }
    }

    func imagen(_ direccion: String) async -> Data? {
        guard let url = URL(string: direccion) else { return nil }
        if let guardada = cache.object(forKey: url as NSURL) { return guardada as Data }
        var request = URLRequest(url: url)
        if let token = KeychainManager.shared.getToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (datos, respuesta) = try? await URLSession.shared.data(for: request),
              (respuesta as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        cache.setObject(datos as NSData, forKey: url as NSURL)
        return datos
    }
}

/// Cuerpo o respuesta vacía.
nonisolated struct Vacio: Codable {}

private nonisolated struct ErrorLaravel: Decodable {
    let message: String?
    let errors: [String: [String]]?
    let presupuesto: ExcesoPresupuesto?
}

/// Respuesta envuelta en "data" (recursos de Laravel).
nonisolated struct Envoltura<T: Decodable>: Decodable {
    let data: T
}

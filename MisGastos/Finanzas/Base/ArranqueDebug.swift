import Foundation

#if DEBUG
/// Solo en desarrollo: abrir la app en el simulador ya con sesión y en una pantalla, para revisarla sin tocar la pantalla.
///   SIMCTL_CHILD_MG_TOKEN=…        token de Sanctum (se guarda en el Keychain)
///   SIMCTL_CHILD_MG_PESTANA=0…4    pestaña inicial (0 Inicio, 1 Efectivo, 2 Tarjetas, 3 Compromisos, 4 Más)
///   SIMCTL_CHILD_MG_ABRIR=…        "compromiso:169", "pago:169", "serie:169", "efectivo-nuevo" o rutas de Más: "mas:cuentas,cuenta:43"
enum ArranqueDebug {
    private static var entorno: [String: String] { ProcessInfo.processInfo.environment }

    static func aplicarToken() {
        if let token = entorno["MG_TOKEN"], !token.isEmpty { _ = KeychainManager.shared.saveToken(token) }
    }

    static var pestana: Int? { entorno["MG_PESTANA"].flatMap(Int.init) }
    static var abrir: String? { entorno["MG_ABRIR"] }
    /// SIMCTL_CHILD_MG_HOJA: formulario a abrir en la pantalla de destino ("editar", "nuevo", "cargo:5", "cargo-nuevo")
    static var hoja: String? { entorno["MG_HOJA"] }

    /// "mas:cuentas,cuenta:43" → [.cuentas, .cuenta(43)]
    static var rutasMas: [Ruta]? {
        guard let a = abrir, a.hasPrefix("mas:") else { return nil }
        return a.dropFirst(4).split(separator: ",").compactMap { Ruta(texto: String($0)) }
    }
}

extension Ruta {
    init?(texto: String) {
        let partes = texto.split(separator: ":")
        let id = partes.count > 1 ? Int(partes[1]) ?? 0 : 0
        switch partes.first.map(String.init) {
        case "cuentas": self = .cuentas
        case "cuenta": self = .cuenta(id)
        case "tarjeta": self = .tarjeta(id)
        case "contactos": self = .contactos(soloDeben: id == 1)
        case "contacto": self = .contacto(id)
        case "prestamos": self = .prestamos
        case "prestamo": self = .prestamo(id)
        case "ingresos": self = .ingresos
        case "ingreso": self = .ingreso(id)
        case "perfil": self = .perfil
        case "categorias": self = .categorias
        case "reportes": self = .reportes
        case "compromiso": self = .compromiso(id)
        case "eventos": self = .eventos
        case "evento": self = .evento(id)
        default: return nil
        }
    }
}
#endif

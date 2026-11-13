import Foundation
import UIKit

// MARK: - Eventos: dividir la cuenta (/api/eventos)

/// Un evento como una tabla: participantes (filas) × productos (columnas). En cada producto, "cantidades" = cuántos
/// pidió cada participante, en su orden. estado: pagador, festejado, hogar, pendiente, parcial o pagado.
nonisolated struct Evento: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let nombre: String
    let fecha: String
    let lugar: String?
    let comentario: String?
    let propinaTipo: String
    let propinaValor: String
    let origen: String?
    let origenValor: String?
    let categoriaPersonalId: Int?
    let pagoElHogar: Bool
    let subtotal: String
    let propina: String
    let total: String
    let porCobrar: String
    let participantes: [ParticipanteEvento]
    let consumos: [ConsumoEvento]
    /// Foto de la cuenta (con el token).
    let fotoUrl: String?

    var pagador: ParticipanteEvento? { participantes.first { $0.esPagador } }
}

nonisolated struct ParticipanteEvento: Decodable, Identifiable, Hashable {
    let id: Int
    let quien: String
    let nombre: String
    let userId: Int?
    let contacto: ContactoMini?
    let esFestejado: Bool
    let esPagador: Bool
    let consumo: String
    let propina: String
    let festejo: String
    let total: String
    let pagado: String
    let pendiente: String
    let estado: String
    let fechaPago: String?
    let deudaId: Int?
    let cobros: [CobroEvento]
    let detalle: [DetalleEvento]
}

nonisolated struct CobroEvento: Decodable, Hashable, Identifiable { let id: Int; let fecha: String; let monto: String; let destino: String? }
nonisolated struct DetalleEvento: Decodable, Hashable { let descripcion: String; let cantidad: Int; let precio: String; let monto: String; let compartido: Bool }
/// compartido: el precio es el del producto completo y se divide entre quienes comieron según sus porciones (cantidades). montos: lo de cada participante.
nonisolated struct ConsumoEvento: Decodable, Identifiable { let id: Int; let descripcion: String; let precio: String; let compartido: Bool; let cantidad: Int; let total: String; let cantidades: [Int]; let montos: [String] }
nonisolated struct OpcionEvento: Decodable, Hashable { let valor: String; let etiqueta: String }
/// participantes: "miembro:{id}" o id de contacto; origenes: de dónde pagar; destinos: a dónde entra un cobro.
nonisolated struct OpcionesEvento: Decodable { let participantes: [OpcionEvento]; let origenes: [OpcionEvento]; let destinos: [OpcionEvento] }

nonisolated struct ParticipanteEventoCuerpo: Encodable { let quien: String; let esFestejado: Bool }
/// cantidades: cuántos pidió cada participante, en el orden de participantes (si es compartido, sus porciones; el precio es el del producto completo).
nonisolated struct ConsumoEventoCuerpo: Encodable { let descripcion: String; let precio: String; let compartido: Bool; let cantidades: [Int] }
nonisolated struct EventoCuerpo: Encodable {
    let nombre: String
    let fecha: String
    let lugar: String?
    let propinaTipo: String
    let propinaValor: String?
    let participantes: [ParticipanteEventoCuerpo]
    let pagador: Int
    let consumos: [ConsumoEventoCuerpo]
    let origen: String?
    let categoriaPersonalId: Int?
    var confirmar: Bool?
}
nonisolated struct CobroEventoCuerpo: Encodable { let monto: String; let fecha: String; let destino: String }
nonisolated struct PagadoEventoCuerpo: Encodable { let fecha: String; let origen: String?; let categoriaPersonalId: Int?; var confirmar: Bool? }

/// Reparto en centavos, igual que EventoService::calcular del servidor (la suma de las partes es exactamente el total).
enum CalculoEvento {
    struct Persona { let uid: Int; let festejado: Bool }
    /// Un producto: precio en centavos y cuántos pidió cada uno (uid → cantidad). Compartido: el precio se divide según las porciones.
    struct Producto { let centavos: Int; var compartido = false; let cant: [Int: Int] }
    struct Parte { let consumo: Int; let propina: Int; let festejo: Int; let total: Int }
    struct Reparto { let subtotal: Int; let propina: Int; let total: Int; let festejo: Int; let por: [Int: Parte] }

    private static func r6(_ v: Double) -> Double { (v * 1e6).rounded() / 1e6 }

    /// A igualdad de fracción, el centavo que sobra va a quien tenga menos "exceso" (lo que ya recibió de más).
    static func repartir(_ total: Int, _ pesos: [(Int, Double)], exceso: [Int: Double] = [:]) -> [Int: Int] {
        guard !pesos.isEmpty else { return [:] }
        let w = pesos.reduce(0) { $0 + $1.1 } <= 0 ? pesos.map { ($0.0, 1.0) } : pesos
        let suma = w.reduce(0) { $0 + $1.1 }
        var partes: [Int: Int] = [:]; var frac: [Int: Double] = [:]
        for (k, p) in w { let exacto = Double(total) * p / suma; let base = Int((exacto + 1e-9).rounded(.down)); partes[k] = base; frac[k] = r6(exacto - Double(base)) }
        let orden = w.map(\.0)
        let claves = orden.sorted { a, b in
            if frac[a]! != frac[b]! { return frac[a]! > frac[b]! }
            let ea = r6(exceso[a] ?? 0), eb = r6(exceso[b] ?? 0)
            if ea != eb { return ea < eb }
            return orden.firstIndex(of: a)! < orden.firstIndex(of: b)!
        }
        var sobran = total - partes.values.reduce(0, +)
        var i = 0
        while sobran > 0 { partes[claves[i % claves.count]]! += 1; sobran -= 1; i += 1 }
        return partes
    }

    /// Centavos de un producto para cada uno: cantidad × precio, o si es compartido su precio dividido según las porciones.
    static func montos(_ producto: Producto, _ uids: [Int]) -> [Int: Int] {
        let cantidades = uids.map { ($0, max(0, producto.cant[$0] ?? 0)) }.filter { $0.1 > 0 }
        if producto.compartido { return repartir(producto.centavos, cantidades.map { ($0.0, Double($0.1)) }) }
        return Dictionary(uniqueKeysWithValues: cantidades.map { ($0.0, $0.1 * producto.centavos) })
    }

    /// Propina: porcentaje del consumo de cada uno o un monto fijo dividido entre todos. Lo de los festejados se reparte entre los demás.
    static func calcular(_ personas: [Persona], _ productos: [Producto], propinaTipo: String, propinaValor: String) -> Reparto {
        let uids = personas.map(\.uid)
        let celdas = productos.map { montos($0, uids) }
        let consumo = Dictionary(uniqueKeysWithValues: uids.map { u in (u, celdas.reduce(0) { $0 + ($1[u] ?? 0) }) })
        let subtotal = consumo.values.reduce(0, +)
        let valor = Double(propinaValor) ?? 0
        var propina = 0
        var exactas = Dictionary(uniqueKeysWithValues: uids.map { ($0, 0.0) })
        if propinaTipo == "porcentaje" {
            propina = Int((Double(subtotal) * valor / 100).rounded())
            exactas = Dictionary(uniqueKeysWithValues: uids.map { ($0, subtotal > 0 ? Double(propina) * Double(consumo[$0]!) / Double(subtotal) : 0) })
        } else if propinaTipo == "monto" {
            propina = Int((valor * 100).rounded())
            exactas = Dictionary(uniqueKeysWithValues: uids.map { ($0, Double(propina) / Double(max(1, uids.count))) })
        }
        let propinas = repartir(propina, uids.map { ($0, exactas[$0]!) })
        let festejados = personas.filter(\.festejado).map(\.uid)
        let pagan = uids.filter { !festejados.contains($0) }
        let festejo = festejados.reduce(0) { $0 + consumo[$1]! + (propinas[$1] ?? 0) }
        let exceso = Dictionary(uniqueKeysWithValues: uids.map { ($0, Double(propinas[$0] ?? 0) - exactas[$0]!) })
        let aportes = pagan.isEmpty ? [:] : repartir(festejo, pagan.map { ($0, 1.0) }, exceso: exceso)
        let por = Dictionary(uniqueKeysWithValues: uids.map { u -> (Int, Parte) in
            let c = consumo[u]!, p = propinas[u] ?? 0, f = aportes[u] ?? 0
            return (u, Parte(consumo: c, propina: p, festejo: f, total: festejados.contains(u) ? 0 : c + p + f))
        })
        return Reparto(subtotal: subtotal, propina: propina, total: subtotal + propina, festejo: festejo, por: por)
    }
}

extension Imagen {
    /// Foto completa (ej. la cuenta de un restaurante): derecha y con su lado mayor en `maximo` px como máximo.
    static func reducida(_ datos: Data, maximo: CGFloat = 1600) -> Data? {
        guard let original = UIImage(data: datos) else { return nil }
        let escala = min(1, maximo / max(original.size.width, original.size.height))
        let tamano = CGSize(width: (original.size.width * escala).rounded(), height: (original.size.height * escala).rounded())
        let formato = UIGraphicsImageRendererFormat(); formato.scale = 1
        // Dibujarla aplica su orientación: el JPEG queda derecho
        return UIGraphicsImageRenderer(size: tamano, format: formato).image { _ in original.draw(in: CGRect(origin: .zero, size: tamano)) }
            .jpegData(compressionQuality: 0.85)
    }
}

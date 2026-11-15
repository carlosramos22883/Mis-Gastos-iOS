import SwiftUI

/// Un gasto que pasa su presupuesto (error 422 "presupuesto") o un presupuesto que ya se pasó: cuánto y de qué otras
/// categorías se puede cubrir.
nonisolated struct ExcesoPresupuesto: Decodable, Identifiable, Hashable {
    let mensaje: String
    /// nil = la categoría no tenía presupuesto en el ciclo (sinPresupuesto): cubrirlo le crea uno.
    let presupuestoId: Int?
    var sinPresupuesto: Bool? = nil
    let categoria: String
    /// Vacíos al repartir lo que le queda a un presupuesto (disponible = lo que le queda; opciones = a cuáles pasarlo).
    var queda: String? = nil
    var gasto: String? = nil
    var excedente: String? = nil
    let disponible: String
    var alcanza: Bool? = nil
    let opciones: [OpcionPresupuesto]
    var id: String { "\(presupuestoId.map(String.init) ?? categoria)-\(excedente ?? disponible)" }
}

nonisolated struct OpcionPresupuesto: Decodable, Hashable, Identifiable {
    let presupuestoId: Int
    let categoria: String
    let color: String?
    let disponible: String
    var id: Int { presupuestoId }
}

/// Cuánto se le quita a una categoría para cubrir lo que se pasa otra.
nonisolated struct TraspasoBody: Encodable, Hashable { let presupuestoId: Int; let monto: String }

nonisolated struct CubrirBody: Encodable { let traspasos: [TraspasoBody] }

/// Lo que se eligió en el aviso: "cubrir" (con lo que se quita a cada una) o "pasarme".
struct DecisionPresupuesto: Hashable {
    let modo: String
    var traspasos: [TraspasoBody]? = nil
}

/// Reparto en centavos de lo que se pasa entre las categorías elegidas.
enum RepartoPresupuesto {
    static func centavos(_ texto: String?) -> Int {
        guard let t = texto?.replacingOccurrences(of: ",", with: ""), let v = Double(t) else { return 0 }
        return Int((v * 100).rounded())
    }

    static func texto(_ centavos: Int) -> String { String(format: "%d.%02d", centavos / 100, centavos % 100) }

    /// Partes iguales; si a una no le alcanza su parte, lo que falta pasa a las otras (mismo orden que disponibles).
    static func sugerir(_ excedente: Int, _ disponibles: [Int]) -> [Int] {
        var resultado = Array(repeating: 0, count: disponibles.count)
        var resto = excedente
        let orden = disponibles.indices.sorted { disponibles[$0] < disponibles[$1] }
        for (i, idx) in orden.enumerated() {
            let quedan = orden.count - i
            let parte = quedan == 1 ? resto : resto / quedan
            let toma = min(parte, disponibles[idx])
            resultado[idx] = toma
            resto -= toma
        }
        return resultado
    }

    /// Repartir: por qué aún no se puede pasar (nil = ya se puede). Se puede pasar menos de lo que le queda, pero la
    /// suma no puede pasarlo. Sin tope por categoría que recibe.
    static func avisoReparto(_ disponible: Int, _ montos: [Int]) -> String? {
        guard !montos.isEmpty else { return nil }
        let suma = montos.reduce(0, +)
        if suma > disponible { return "Solo le quedan \(Formato.dinero(texto(disponible))): bájale \(Formato.dinero(texto(suma - disponible))) a los montos." }
        if montos.contains(where: { $0 <= 0 }) { return "Quita las categorías sin monto." }
        return nil
    }

    /// Por qué aún no se puede cubrir (nil = ya cuadra). elegidas: (monto, disponible) en centavos.
    static func aviso(_ excedente: Int, _ elegidas: [(Int, Int)]) -> String? {
        guard !elegidas.isEmpty else { return nil }
        if elegidas.contains(where: { $0.0 > $0.1 }) { return "Una categoría no tiene tanto disponible." }
        let falta = excedente - elegidas.reduce(0) { $0 + $1.0 }
        if falta > 0 {
            let sinUsar = elegidas.reduce(0) { $0 + max(0, $1.1 - $1.0) }
            return sinUsar >= falta ? "Te faltan \(Formato.dinero(texto(falta))): súbele a los montos."
                : "Te faltan \(Formato.dinero(texto(falta))): elige otra categoría para que alcance."
        }
        if falta < 0 { return "Te sobran \(Formato.dinero(texto(-falta))): bájale a los montos." }
        if elegidas.contains(where: { $0.0 <= 0 }) { return "Quita las categorías sin monto." }
        return nil
    }
}

/// Hoja para elegir de qué categorías cubrir lo que se pasa. Al marcar, sugiere partes iguales; los montos se pueden
/// cambiar mientras sumen justo lo que se pasa. manual = cubrir un presupuesto que ya se pasó (sin "pasarme").
/// repartir = pasar lo que le queda a un presupuesto a otras (se elige cuánto; las que reciben no tienen tope).
struct HojaCubrirPresupuesto: View {
    let exceso: ExcesoPresupuesto
    var manual = false
    var repartir = false
    let alDecidir: (DecisionPresupuesto) -> Void

    @Environment(\.dismiss) private var cerrar
    private var sinPresupuesto: Bool { exceso.sinPresupuesto == true }
    @State private var montos: [Int: String] = [:] // presupuesto_id -> monto (solo las elegidas)

    /// Repartir: se sugiere pasar todo lo que le queda, pero se puede pasar menos.
    private var excedente: Int { RepartoPresupuesto.centavos(repartir ? exceso.disponible : exceso.excedente) }
    private var elegidas: [OpcionPresupuesto] { exceso.opciones.filter { montos[$0.presupuestoId] != nil } }
    private var pares: [(Int, Int)] { elegidas.map { (RepartoPresupuesto.centavos(montos[$0.presupuestoId]), RepartoPresupuesto.centavos($0.disponible)) } }
    private var suma: Int { pares.reduce(0) { $0 + $1.0 } }
    private var aviso: String? {
        repartir ? RepartoPresupuesto.avisoReparto(excedente, pares.map(\.0))
            : RepartoPresupuesto.aviso(excedente, pares)
    }
    private var valido: Bool { !elegidas.isEmpty && aviso == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(repartir ? "A «\(exceso.categoria)» le quedan \(Formato.dinero(exceso.disponible)). Pásalo a las categorías que sí lo van a usar."
                             : manual ? "«\(exceso.categoria)» se pasó por \(Formato.dinero(exceso.excedente))."
                             : sinPresupuesto ? "«\(exceso.categoria)» no tiene presupuesto en este ciclo"
                                + (RepartoPresupuesto.centavos(exceso.queda) < 0 ? " y ya lleva \(Formato.dinero(Double(-RepartoPresupuesto.centavos(exceso.queda)) / 100)) gastados" : "")
                                + ". Si lo guardas, te pasas del tope por \(Formato.dinero(exceso.excedente)). ¿Aun así deseas guardarlo?"
                             : "A «\(exceso.categoria)» le quedan \(Formato.dinero(exceso.queda)) y el gasto es de \(Formato.dinero(exceso.gasto)): te pasarías por \(Formato.dinero(exceso.excedente)).")
                    } icon: { Image(systemName: repartir ? "arrow.left.arrow.right.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(repartir ? .green : .orange) }
                }
                if exceso.opciones.isEmpty {
                    Text("Ninguna otra categoría tiene presupuesto disponible este ciclo.").foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(exceso.opciones) { o in fila(o) }
                    } header: { Text(repartir ? "¿A cuáles?" : "¿Lo cubres con otras categorías?") } footer: {
                        Text(repartir ? "Elige una o varias. Se sugiere repartir todo lo que le queda, pero puedes pasar menos: cambia cuánto recibe cada una." : "Elige una o varias y, si quieres, cambia cuánto le quitas a cada una.")
                    }
                    Section {
                        HStack {
                            Text(repartir ? "Repartes" : "Cubres").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Formato.dinero(RepartoPresupuesto.texto(suma))) de \(Formato.dinero(RepartoPresupuesto.texto(excedente)))").bold()
                                .foregroundStyle(valido ? .green : .primary)
                        }
                        if let aviso { Text(aviso).font(.footnote).foregroundStyle(.orange) }
                    }
                }
                if !manual {
                    Section {
                        Button(sinPresupuesto ? "Guardarlo sin presupuesto" : "Guardar y pasarme") { alDecidir(DecisionPresupuesto(modo: "pasarme")); cerrar() }
                    } footer: { Text(sinPresupuesto ? "Se guarda fuera de presupuesto y sale del tope del ciclo." : "Se guarda como antes y la categoría queda pasada.") }
                }
            }
            .navigationTitle(repartir ? "Pasar a otras categorías" : manual ? "Cubrir presupuesto" : sinPresupuesto ? "Sin presupuesto" : "Te pasas del presupuesto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                if !exceso.opciones.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(repartir ? "Pasar" : manual ? "Cubrir" : "Cubrir y guardar") {
                            let traspasos = elegidas.map { TraspasoBody(presupuestoId: $0.presupuestoId, monto: RepartoPresupuesto.texto(RepartoPresupuesto.centavos(montos[$0.presupuestoId]))) }
                            alDecidir(DecisionPresupuesto(modo: "cubrir", traspasos: traspasos)); cerrar()
                        }.disabled(!valido)
                    }
                }
            }
        }
    }

    private func fila(_ o: OpcionPresupuesto) -> some View {
        let elegida = montos[o.presupuestoId] != nil
        return HStack {
            Button {
                if elegida { montos[o.presupuestoId] = nil } else { montos[o.presupuestoId] = "" }
                sugerir()
            } label: {
                HStack {
                    Image(systemName: elegida ? "checkmark.circle.fill" : "circle").foregroundStyle(elegida ? Color.accentColor : .secondary)
                    Circle().fill(Formato.color(o.color)).frame(width: 10, height: 10)
                    VStack(alignment: .leading) {
                        Text(o.categoria).foregroundStyle(.primary)
                        Text("\(repartir ? "Ahora le quedan" : "Le quedan") \(Formato.dinero(o.disponible))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain)
            Spacer()
            if elegida {
                HStack(spacing: 2) {
                    Text("$").foregroundStyle(.secondary)
                    TextField("0.00", text: Binding(get: { montos[o.presupuestoId] ?? "" }, set: { montos[o.presupuestoId] = $0.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." } }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        .foregroundStyle(!repartir && RepartoPresupuesto.centavos(montos[o.presupuestoId]) > RepartoPresupuesto.centavos(o.disponible) ? .red : .primary)
                }
            }
        }
    }

    private func sugerir() {
        let lista = elegidas
        let sugeridos = RepartoPresupuesto.sugerir(excedente, lista.map { repartir ? Int.max : RepartoPresupuesto.centavos($0.disponible) })
        for (i, o) in lista.enumerated() { montos[o.presupuestoId] = RepartoPresupuesto.texto(sugeridos[i]) }
    }
}

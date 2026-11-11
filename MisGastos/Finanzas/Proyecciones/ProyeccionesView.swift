import SwiftUI
import Charts

// MARK: - Modelos (/api/proyecciones): montos como texto, meses "Y-m"; un hito o un "cero" en nil = más de 15 años

nonisolated struct ProyeccionDeudas: Decodable {
    let base: BaseProyeccion
    let escenarios: [EscenarioMini]
    let ver: [Int]
    let comparacion: [ComparacionEscenario]
}

nonisolated struct BaseProyeccion: Decodable {
    let mesInicio: String
    let ingreso: String
    let gasto: String
    /// "tope" (el del ciclo) o "promedio" (de los últimos 3 ciclos)
    let gastoOrigen: String
    let cuotasEfectivo: String
    let sobra: String
    let grupos: GruposDeuda
}

nonisolated struct GruposDeuda: Decodable { let tarjetas: String; let bancos: String; let personas: String; let hipoteca: String }
nonisolated struct EscenarioMini: Decodable, Identifiable { let id: Int; let nombre: String }

nonisolated struct ComparacionEscenario: Decodable {
    /// nil = "Si sigo igual"
    let id: Int?
    let nombre: String
    let orden: String
    let modoTarjetas: String
    let hitos: HitosProyeccion
    let totales: TotalesProyeccion
    let meta: MetaProyeccion?
    let deudas: [DeudaCero]
    let serie: [PuntoSerie]
}

nonisolated struct HitosProyeccion: Decodable { let tarjetas: String?; let personas: String?; let sinDeudas: String? }
nonisolated struct TotalesProyeccion: Decodable {
    let interesesTarjetas: String; let perdidaRotar: String; let prestamosNuevos: String; let faltante: String; let mesesConFaltante: Int
}
/// extra: lo que falta al mes para llegar a tiempo ("0.00" = ya se logra; nil = ni con $20,000)
nonisolated struct MetaProyeccion: Decodable { let que: String; let mes: String; let extra: String?; let logradoEn: String? }
nonisolated struct DeudaCero: Decodable { let clave: String; let nombre: String; let cero: String? }
nonisolated struct PuntoSerie: Decodable { let mes: String; let total: String }

// MARK: - Pantalla

/// Escenarios que se comparan a la vez con "Si sigo igual" (igual que la web).
private let maxComparar = 3
private let mesesCortos = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]

private func mesTexto(_ m: String?) -> String {
    guard let m, m.count >= 7, let n = Int(m.dropFirst(5).prefix(2)) else { return "Más de 15 años" }
    return "\(mesesCortos[n - 1]) \(m.prefix(4))"
}

/// Paleta categórica validada (claro / oscuro), en orden fijo: "Si sigo igual" siempre es la primera.
private func colorSerie(_ i: Int) -> Color {
    let claro: [UInt32] = [0x2A78D6, 0xEB6834, 0x1BAF7A, 0xEDA100]
    let noche: [UInt32] = [0x3987E5, 0xD95926, 0x199E70, 0xC98500]
    return Color(light: claro[i % 4], dark: noche[i % 4])
}

struct ProyeccionesView: View {
    @State private var datos: ProyeccionDeudas?
    @State private var error: String?
    @State private var mesElegido: String?

    var body: some View {
        Group {
            if let d = datos { contenido(d) }
            else if let error { ErrorConReintento(mensaje: error) { Task { await cargar(nil) } } }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .navigationTitle("Proyecciones")
        .task { if datos == nil { await cargar(nil) } }
        .refreshable { await cargar(datos?.ver) }
    }

    private func contenido(_ d: ProyeccionDeudas) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("¿Cuándo salgo de mis deudas? Con tus datos reales desde \(mesTexto(d.base.mesInicio)).")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Seccion("Tu situación hoy") {
                    FilaValor(etiqueta: "Entra al mes", valor: Formato.dinero(d.base.ingreso))
                    FilaValor(etiqueta: d.base.gastoOrigen == "tope" ? "Gasto de vida (el tope)" : "Gasto de vida (promedio)", valor: Formato.dinero(d.base.gasto))
                    FilaValor(etiqueta: "Cuotas en efectivo", valor: Formato.dinero(d.base.cuotasEfectivo))
                    FilaValor(etiqueta: "Sobra para deudas", valor: Formato.dinero(d.base.sobra), color: (Double(d.base.sobra) ?? 0) < 0 ? .red : .primary, negrita: true)
                    Divider()
                    FilaValor(etiqueta: "Tarjetas", valor: Formato.dinero(d.base.grupos.tarjetas))
                    FilaValor(etiqueta: "Préstamos del banco", valor: Formato.dinero(d.base.grupos.bancos))
                    FilaValor(etiqueta: "Personas", valor: Formato.dinero(d.base.grupos.personas))
                    FilaValor(etiqueta: "Hipoteca (va aparte)", valor: Formato.dinero(d.base.grupos.hipoteca))
                }
                Seccion("Comparar con «Si sigo igual»") {
                    if d.escenarios.isEmpty {
                        Text("Aún no tienes escenarios. Créalos en la web, en Proyecciones.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Elige hasta \(maxComparar). Los escenarios se crean y editan en la web.").font(.caption).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(d.escenarios) { e in
                                    let elegido = d.ver.contains(e.id)
                                    Button { Task { await alternar(e.id, en: d.ver) } } label: {
                                        Label(e.nombre, systemImage: elegido ? "checkmark" : "plus").font(.subheadline)
                                    }
                                    .buttonStyle(.bordered).tint(elegido ? .accentColor : .secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(Array(d.comparacion.enumerated()), id: \.offset) { i, e in tarjeta(e, color: colorSerie(i)) }
                grafica(d.comparacion)
                Seccion("Cuándo queda en cero cada deuda") {
                    ForEach(d.comparacion.first?.deudas ?? [], id: \.clave) { deuda in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deuda.nombre).font(.subheadline.weight(.medium))
                            ForEach(Array(d.comparacion.enumerated()), id: \.offset) { i, e in
                                let cero = e.deudas.first { $0.clave == deuda.clave }?.cero
                                HStack {
                                    Capsule().fill(colorSerie(i)).frame(width: 12, height: 2)
                                    Text(e.nombre).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(mesTexto(cero)).font(.caption).foregroundStyle(cero == nil ? .red : .primary)
                                }
                            }
                        }.padding(.vertical, 2)
                    }
                }
                Text("Es una proyección con supuestos: el ingreso y el gasto se mantienen, lo que sobra paga deudas según el orden del escenario y lo que falta se va a las tarjetas.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
    }

    private func tarjeta(_ e: ComparacionEscenario, color: Color) -> some View {
        let ordenes = ["mas_cara": "la más cara primero", "mas_pequena": "la más pequeña primero", "personalizado": "orden propio"]
        return Seccion(e.nombre) {
            HStack {
                Capsule().fill(color).frame(width: 16, height: 3)
                Text((e.modoTarjetas == "rotar" ? "Tarjetas rotando con avances" : "Tarjetas pagando intereses") + " · " + (ordenes[e.orden] ?? e.orden))
                    .font(.caption).foregroundStyle(.secondary)
            }
            fecha("Tarjetas en $0", e.hitos.tarjetas)
            fecha("Personas pagadas", e.hitos.personas)
            fecha("Sin deudas (menos la hipoteca)", e.hitos.sinDeudas)
            FilaValor(etiqueta: "Intereses de tarjetas", valor: Formato.dinero(e.totales.interesesTarjetas))
            if (Double(e.totales.perdidaRotar) ?? 0) > 0 { FilaValor(etiqueta: "Perdido al rotar", valor: Formato.dinero(e.totales.perdidaRotar)) }
            if (Double(e.totales.prestamosNuevos) ?? 0) > 0 { FilaValor(etiqueta: "Préstamos nuevos: intereses y comisiones", valor: Formato.dinero(e.totales.prestamosNuevos)) }
            if e.totales.mesesConFaltante > 0 {
                FilaValor(etiqueta: "No alcanzó en \(e.totales.mesesConFaltante) mes(es)", valor: Formato.dinero(e.totales.faltante), color: .red)
            }
            if let m = e.meta { meta(m, deudas: e.deudas) }
        }
    }

    private func fecha(_ etiqueta: String, _ mes: String?) -> some View {
        FilaValor(etiqueta: etiqueta, valor: mesTexto(mes), color: mes == nil ? .red : .primary, negrita: true)
    }

    @ViewBuilder
    private func meta(_ m: MetaProyeccion, deudas: [DeudaCero]) -> some View {
        let que = ["tarjetas": "Tarjetas en $0", "personas": "Personas pagadas", "sin_deudas": "Sin deudas"][m.que]
            ?? "Pagar " + (deudas.first { $0.clave == m.que }?.nombre ?? m.que)
        let extra = m.extra.flatMap(Double.init)
        VStack(alignment: .leading, spacing: 2) {
            Text("Meta: \(que) para \(mesTexto(m.mes))").font(.caption).foregroundStyle(.secondary)
            if m.extra == nil {
                Text("No se logra ni con $ 20,000.00 más al mes").font(.subheadline.weight(.semibold)).foregroundStyle(.red)
            } else if extra == 0 {
                Text("Ya lo logras (\(mesTexto(m.logradoEn)))").font(.subheadline.weight(.semibold)).foregroundStyle(Semantica.ingreso)
            } else {
                Text("Necesitas \(Formato.dinero(m.extra)) más al mes").font(.subheadline.weight(.semibold))
            }
        }.padding(.top, 4)
    }

    /// Deuda total sin hipoteca, mes a mes: una línea por escenario. Tocar o arrastrar muestra los valores de ese mes.
    private func grafica(_ comparacion: [ComparacionEscenario]) -> some View {
        Seccion("Cuánto debes, mes a mes (sin hipoteca)") {
            ForEach(Array(comparacion.enumerated()), id: \.offset) { i, e in
                HStack {
                    Capsule().fill(colorSerie(i)).frame(width: 16, height: 2)
                    Text(e.nombre).font(.caption)
                    Spacer()
                    if let mesElegido, let p = e.serie.first(where: { $0.mes == mesElegido }) {
                        Text(Formato.dinero(p.total)).font(.caption.weight(.semibold))
                    }
                }
            }
            Text(mesElegido.map(mesTexto) ?? "Toca la gráfica para ver un mes").font(.caption2).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(comparacion.enumerated()), id: \.offset) { i, e in
                    ForEach(e.serie, id: \.mes) { p in
                        LineMark(x: .value("Mes", p.mes), y: .value("Deuda", Double(p.total) ?? 0), series: .value("Escenario", e.nombre))
                            .foregroundStyle(colorSerie(i)).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
                if let mesElegido { RuleMark(x: .value("Mes", mesElegido)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1)) }
            }
            .chartXSelection(value: $mesElegido)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { v in AxisValueLabel { Text(mesTexto(v.as(String.self))).font(.caption2) } } }
            .chartLegend(.hidden)
            .frame(height: 220)
            .accessibilityLabel("Gráfica de la deuda total por mes en cada escenario")
        }
    }

    private func alternar(_ id: Int, en actual: [Int]) async {
        await cargar(actual.contains(id) ? actual.filter { $0 != id } : Array((actual + [id]).suffix(maxComparar)))
    }

    /// ver = nil: los escenarios más recientes; vacío: solo "Si sigo igual".
    private func cargar(_ ver: [Int]?) async {
        do {
            var parametros: [String: String?] = [:]
            if let ver { parametros["ver"] = ver.map(String.init).joined(separator: ",") }
            let r: Envoltura<ProyeccionDeudas> = try await API.shared.get("/proyecciones", parametros)
            datos = r.data; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

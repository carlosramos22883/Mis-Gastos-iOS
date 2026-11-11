import QuickLook
import SwiftUI

/// Los cuatro reportes (los mismos de la web).
let reportes: [(String, String)] = [("ejecucion", "Ejecución"), ("gastos", "Gastos"), ("prestamos", "Préstamos"), ("estado-cuenta", "Estado")]

@Observable
final class ReportesModelo {
    var reporte = "ejecucion"
    /// Período pedido: ciclo (una fecha dentro) o desde/hasta.
    var ciclo: String?
    var desde: String?
    var hasta: String?
    var cargando = true
    var error: String?
    var periodo: PeriodoReporte?
    var ejecucion: Ejecucion?
    var gastos: GastosReporte?
    var prestamos: PrestamosReporte?
    var estado: EstadoReporte?
    var tarjetas: [Tarjeta] = []
    var tarjetaId: Int?
    var estadoId: Int?
    var cortes: [CorteReporte] = []
    var descargando = false

    var parametros: [String: String?] {
        if let desde, let hasta { return ["desde": desde, "hasta": hasta] }
        return ["ciclo": ciclo]
    }

    var hayDatos: Bool {
        switch reporte {
        case "gastos": gastos != nil
        case "prestamos": prestamos != nil
        case "estado-cuenta": estado != nil
        default: ejecucion != nil
        }
    }

    func cargar() async {
        cargando = true
        error = nil
        do {
            switch reporte {
            case "gastos":
                let r: RespuestaReporte<GastosReporte> = try await API.shared.get("/reportes/gastos", parametros)
                periodo = r.periodo; gastos = r.data
            case "prestamos":
                let r: RespuestaReporte<PrestamosReporte> = try await API.shared.get("/reportes/prestamos")
                periodo = r.periodo; prestamos = r.data
            case "estado-cuenta":
                if tarjetas.isEmpty, let t: Envoltura<[Tarjeta]> = try? await API.shared.get("/tarjetas") {
                    tarjetas = t.data.sorted { $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending }
                }
                if let tarjetaId {
                    let r: RespuestaReporte<EstadoReporte> = try await API.shared.get("/reportes/estado-cuenta", ["tarjeta": "\(tarjetaId)", "estado": estadoId.map(String.init)])
                    estado = r.data; cortes = r.cortes ?? []
                } else {
                    estado = nil; cortes = []
                }
            default:
                let r: RespuestaReporte<Ejecucion> = try await API.shared.get("/reportes/ejecucion", parametros)
                periodo = r.periodo; ejecucion = r.data
            }
        } catch { self.error = error.localizedDescription }
        cargando = false
    }

    func descargar(_ formato: String) async throws -> URL {
        descargando = true
        defer { descargando = false }
        var p = parametros
        p["formato"] = formato
        p["tarjeta"] = tarjetaId.map(String.init)
        p["estado"] = estadoId.map(String.init)
        return try await API.shared.descargar("/reportes/\(reporte)/exportar", p)
    }
}

/// Reportes: ejecución financiera, gastos por categoría, préstamos y estado de cuenta; se descargan en PDF, Excel o CSV.
struct ReportesView: View {
    @State private var modelo = ReportesModelo()
    @State private var rango = false
    @State private var desde = Date()
    @State private var hasta = Date()
    @State private var archivo: URL?
    @State private var aviso: String?
    private let comunes = Comunes.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Reporte", selection: Binding(get: { modelo.reporte }, set: { r in modelo.reporte = r; Task { await modelo.cargar() } })) {
                    ForEach(reportes, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                if modelo.reporte == "ejecucion" || modelo.reporte == "gastos" { selectorPeriodo }
                if modelo.cargando {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let e = modelo.error {
                    ErrorConReintento(mensaje: e) { Task { await modelo.cargar() } }
                } else {
                    switch modelo.reporte {
                    case "gastos": if let g = modelo.gastos { VistaGastos(d: g) }
                    case "prestamos": if let p = modelo.prestamos { VistaPrestamos(d: p) }
                    case "estado-cuenta": vistaEstado
                    default: if let e = modelo.ejecucion { VistaEjecucion(d: e) }
                    }
                }
            }
            .padding(16)
        }
        .background(Semantica.fondo)
        .navigationTitle("Reportes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if modelo.hayDatos {
                ToolbarItem(placement: .primaryAction) {
                    if modelo.descargando {
                        ProgressView()
                    } else {
                        Menu {
                            ForEach([("pdf", "PDF"), ("xlsx", "Excel"), ("csv", "CSV")], id: \.0) { f, t in
                                Button("Descargar en \(t)") { Task { await descargar(f) } }
                            }
                        } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("Descargar")
                    }
                }
            }
        }
        .task {
            #if DEBUG
            if let h = ArranqueDebug.hoja, reportes.contains(where: { $0.0 == h }) { modelo.reporte = h }
            #endif
            await modelo.cargar()
        }
        .refreshable { await modelo.cargar() }
        // Vista previa del archivo, con su botón para compartir o guardar
        .quickLookPreview($archivo)
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    /// "‹ Ciclo del 23/09 al 22/10 ›" o un rango de fechas.
    private var selectorPeriodo: some View {
        VStack(spacing: 6) {
            if rango {
                DatePicker("Desde", selection: $desde, in: ...Date(), displayedComponents: .date)
                DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date)
                Button("Ver") {
                    modelo.desde = Formato.textoLocal(desde); modelo.hasta = Formato.textoLocal(hasta); modelo.ciclo = nil
                    Task { await modelo.cargar() }
                }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack {
                    Button { irA(modelo.periodo?.anterior) } label: { Image(systemName: "chevron.left") }
                        .disabled(modelo.periodo?.esCiclo != true || modelo.periodo?.anterior == nil).accessibilityLabel("Ciclo anterior")
                    Spacer()
                    Text(modelo.periodo?.texto ?? "").font(.subheadline).multilineTextAlignment(.center)
                    Spacer()
                    Button { irA(modelo.periodo?.siguiente) } label: { Image(systemName: "chevron.right") }
                        .disabled(modelo.periodo?.esCiclo != true || modelo.periodo?.siguiente == nil).accessibilityLabel("Ciclo siguiente")
                }
            }
            Button(rango ? "Por ciclo" : "Elegir fechas") {
                rango.toggle()
                if rango, let p = modelo.periodo { desde = Formato.fechaLocal(p.desde); hasta = Formato.fechaLocal(p.hasta) }
                if !rango && modelo.desde != nil { irA(nil) }
            }
            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Semantica.tarjeta, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var vistaEstado: some View {
        Seccion("Tarjeta y corte") {
            Picker("Tarjeta", selection: Binding(get: { modelo.tarjetaId }, set: { id in modelo.tarjetaId = id; modelo.estadoId = nil; Task { await modelo.cargar() } })) {
                Text("Elegir…").tag(nil as Int?)
                ForEach(modelo.tarjetas) { Text($0.nombre + ($0.activo ? "" : " (inactiva)")).tag($0.id as Int?) }
            }
            if modelo.tarjetaId != nil {
                if modelo.cortes.isEmpty {
                    Text("Los estados de cuenta se generan solos en cada corte; esta tarjeta aún no ha cortado desde que se registró.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Corte", selection: Binding(get: { modelo.estadoId }, set: { id in modelo.estadoId = id; Task { await modelo.cargar() } })) {
                        Text("Elegir…").tag(nil as Int?)
                        ForEach(modelo.cortes) { Text("\(Formato.fechaCorta($0.fechaCorte)) · \(Formato.dinero($0.total))").tag($0.id as Int?) }
                    }
                }
            }
        }
        if let d = modelo.estado { VistaEstado(d: d) }
    }

    private func irA(_ fecha: String?) {
        modelo.ciclo = fecha; modelo.desde = nil; modelo.hasta = nil
        Task { await modelo.cargar() }
    }

    private func descargar(_ formato: String) async {
        do { archivo = try await modelo.descargar(formato) } catch { aviso = error.localizedDescription }
    }
}

/// Cifra grande en una tarjeta.
private struct Cifra: View {
    let etiqueta: String
    let valor: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(etiqueta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(valor).font(.headline).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Semantica.tarjeta, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Barra de una categoría: nombre, barra con su color, monto y porcentaje.
private struct BarraCategoria: View {
    let c: CategoriaReporte
    let maximo: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(c.nombre).lineLimit(1)
                Spacer()
                Text(Formato.dinero(c.monto)).fontWeight(.medium)
                Text("\(c.porcentaje.formatted()) %").font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill))
                    Capsule().fill(Formato.color(c.color, .accentColor)).frame(width: max(4, g.size.width * c.monto / max(maximo, 1)))
                }
            }
            .frame(height: 6)
        }
        .contentShape(Rectangle())
    }
}

private struct VistaEjecucion: View {
    let d: Ejecucion
    private let comunes = Comunes.shared

    var body: some View {
        let t = d.totales
        HStack(spacing: 8) {
            Cifra(etiqueta: "Ingresos", valor: Formato.dinero(t.ingresos), color: Semantica.ingreso)
            Cifra(etiqueta: "Gastos", valor: Formato.dinero(t.gastos))
        }
        HStack(spacing: 8) {
            Cifra(etiqueta: "Ahorro", valor: Formato.dinero(t.ahorro), color: t.ahorro < 0 ? Semantica.egreso : Semantica.ingreso)
            Cifra(etiqueta: "Al pagar compromisos", valor: Formato.dinero(t.liquidez), color: t.liquidez < 0 ? Semantica.egreso : .primary)
        }
        Seccion("Ingresos · \(Formato.dinero(t.ingresos))") {
            if d.ingresos.isEmpty { Text("No hubo ingresos en este período.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(d.ingresos) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.descripcion).font(.subheadline).lineLimit(1)
                        Text([Formato.fechaCorta(m.fecha), m.categoria, m.donde, comunes.quien(m.userId)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(Formato.dinero(m.monto)).fontWeight(.medium).foregroundStyle(Semantica.ingreso)
                }
            }
        }
        Seccion("Gastos por categoría · \(Formato.dinero(t.gastos))") {
            if d.gastos.isEmpty { Text("No hubo gastos en este período.").font(.subheadline).foregroundStyle(.secondary) }
            let maximo = d.gastos.map(\.monto).max() ?? 1
            ForEach(d.gastos) { BarraCategoria(c: $0, maximo: maximo) }
        }
        Seccion("Efectivo y cuentas") {
            caja("Efectivo", d.efectivo.saldoInicial, d.efectivo.ingresos, d.efectivo.egresos, d.efectivo.saldoFinal)
            ForEach(d.cuentas) { c in
                Divider()
                NavigationLink(value: Ruta.cuenta(c.id)) { caja(c.nombre, c.saldoInicial, c.ingresos, c.egresos, c.saldoFinal).contentShape(Rectangle()) }.buttonStyle(.plain)
            }
            Divider()
            FilaValor(etiqueta: "Total al final", valor: Formato.dinero(t.efectivo + t.cuentas), negrita: true)
        }
        Seccion("Compromisos") {
            if d.compromisos.isEmpty { Text("No hubo compromisos con fecha en este período.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(d.compromisos) { c in
                NavigationLink(value: Ruta.compromiso(c.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.descripcion).font(.subheadline).lineLimit(1)
                            Text("\(Formato.fechaCorta(c.fecha)) · \(c.estadoTexto)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formato.dinero(c.pendiente > 0 ? c.pendiente : c.monto)).fontWeight(.medium)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !d.compromisos.isEmpty { FilaValor(etiqueta: "Por pagar", valor: Formato.dinero(t.porPagar), negrita: true) }
        }
        Seccion("Tarjetas (hoy, por fecha de pago)") {
            ForEach(d.tarjetas) { tj in
                NavigationLink(value: Ruta.tarjeta(tj.id)) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Formato.color(tj.color)).frame(width: 4, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text([tj.nombre, comunes.quien(tj.userId)].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).lineLimit(1)
                            Text(tj.fechaLimite.map { "Pagar antes del \(Formato.fechaCorta($0))" } ?? "Sin pagos pendientes").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(tj.porPagar > 0 ? Formato.dinero(tj.porPagar) : "—").fontWeight(.medium)
                            Text("disp. \(Formato.dinero(tj.disponible))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            FilaValor(etiqueta: "Por pagar", valor: Formato.dinero(t.tarjetasPorPagar), negrita: true)
            FilaValor(etiqueta: "Disponible", valor: Formato.dinero(t.tarjetasDisponible))
        }
        Seccion("Nos deben (hoy) · \(Formato.dinero(t.nosDeben))") {
            if d.nosDeben.isEmpty { Text("Nadie nos debe. 🎉").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(d.nosDeben) { c in
                NavigationLink(value: Ruta.contacto(c.id)) { FilaValor(etiqueta: c.nombre, valor: Formato.dinero(c.pendiente)).contentShape(Rectangle()) }.buttonStyle(.plain)
            }
        }
    }

    private func caja(_ nombre: String, _ inicial: Double, _ entro: Double, _ salio: Double, _ final: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            FilaValor(etiqueta: "\(nombre): \(Formato.dinero(inicial)) →", valor: Formato.dinero(final), negrita: true)
            Text("Entró \(Formato.dinero(entro)) · salió \(Formato.dinero(salio))").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct VistaGastos: View {
    let d: GastosReporte
    @State private var abierta: String?
    private let comunes = Comunes.shared

    var body: some View {
        let varios = d.ciclos.count > 1
        HStack(spacing: 8) {
            Cifra(etiqueta: "Gastado", valor: Formato.dinero(d.total))
            if varios { Cifra(etiqueta: "Promedio por ciclo", valor: Formato.dinero(d.promedioPorCiclo)) }
            else { Cifra(etiqueta: "Mayor gasto", valor: d.categorias.first?.nombre ?? "—") }
        }
        if d.categorias.isEmpty {
            Text("No hubo gastos en este período.").foregroundStyle(.secondary)
        } else {
            if varios {
                Seccion("Total por ciclo") {
                    ForEach(Array(d.ciclos.enumerated()), id: \.offset) { i, c in
                        FilaValor(etiqueta: Formato.rango(c.inicio, c.fin), valor: Formato.dinero(d.porCiclo.indices.contains(i) ? d.porCiclo[i] : 0))
                    }
                }
            }
            Seccion("Por categoría") {
                Text("Toca una categoría para ver sus movimientos.").font(.caption).foregroundStyle(.secondary)
                let maximo = d.categorias.map(\.monto).max() ?? 1
                ForEach(d.categorias) { c in
                    BarraCategoria(c: c, maximo: maximo)
                        .onTapGesture { withAnimation { abierta = abierta == c.nombre ? nil : c.nombre } }
                    if abierta == c.nombre {
                        VStack(alignment: .leading, spacing: 4) {
                            if varios, let por = c.porCiclo {
                                Text(d.ciclos.indices.map { "\(Formato.fechaCorta(d.ciclos[$0].fin)): \(Formato.dinero(por.indices.contains($0) ? por[$0] : 0))" }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(c.movimientos ?? []) { m in
                                HStack(alignment: .top) {
                                    Text(Formato.fechaCorta(m.fecha)).font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.descripcion).font(.caption).lineLimit(1)
                                        Text([m.donde, comunes.quien(m.userId)].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Formato.dinero(m.monto)).font(.caption)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
            }
        }
    }
}

private struct VistaPrestamos: View {
    let d: PrestamosReporte

    var body: some View {
        let t = d.totales
        HStack(spacing: 8) {
            Cifra(etiqueta: "Saldo", valor: Formato.dinero(t.saldo))
            Cifra(etiqueta: "Cuotas al mes", valor: Formato.dinero(t.cuotasAlMes))
        }
        HStack(spacing: 8) {
            Cifra(etiqueta: "Intereses pagados", valor: Formato.dinero(t.pagadoIntereses))
            Cifra(etiqueta: "Intereses que faltan", valor: Formato.dinero(t.interesesRestantes), color: Semantica.egreso)
        }
        if d.prestamos.isEmpty { Text("No hay préstamos registrados.").foregroundStyle(.secondary) }
        ForEach(d.prestamos) { p in
            Seccion(p.nombre + (p.activo ? "" : " (pagado)")) {
                Text([p.acreedor, Formato.dinero(p.montoOriginal), p.tasaAnual.map { "\($0.formatted()) % anual" }, p.plazoMeses.map { "\($0) meses" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                ProgressView(value: min(max(p.avance / 100, 0), 1)).tint(Formato.color(p.color, .accentColor))
                NavigationLink(value: Ruta.prestamo(p.id)) {
                    FilaValor(etiqueta: "Saldo (\(p.avance.formatted()) % pagado)", valor: Formato.dinero(p.saldo), negrita: true).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let c = p.cuotaTotal { FilaValor(etiqueta: "Cuota al mes", valor: Formato.dinero(c)) }
                FilaValor(etiqueta: "Pagos registrados", valor: "\(p.pagosRealizados)")
                FilaValor(etiqueta: "Capital pagado", valor: Formato.dinero(p.pagadoCapital))
                FilaValor(etiqueta: "Intereses pagados", valor: Formato.dinero(p.pagadoIntereses))
                if let i = p.interesesRestantes { FilaValor(etiqueta: "Intereses que faltan", valor: Formato.dinero(i), color: Semantica.egreso) }
                if let m = p.mesesRestantes { FilaValor(etiqueta: "Faltan", valor: "\(m) meses · \(Formato.fechaCorta(p.fechaFin))") }
            }
        }
    }
}

private struct VistaEstado: View {
    let d: EstadoReporte

    var body: some View {
        HStack(spacing: 8) {
            Cifra(etiqueta: "Total", valor: Formato.dinero(d.total))
            Cifra(etiqueta: "Pagado", valor: Formato.dinero(d.pagado), color: Semantica.ingreso)
            Cifra(etiqueta: "Pendiente", valor: Formato.dinero(d.pendiente))
        }
        Seccion("Del \(Formato.fechaCorta(d.fechaInicio)) al \(Formato.fechaCorta(d.fechaCorte))") {
            Text("Pagar antes del \(Formato.fechaLarga(d.fechaLimitePago))").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(d.lineas.enumerated()), id: \.offset) { _, l in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.descripcion + (l.cuota.map { " (\($0))" } ?? "")).font(.subheadline).lineLimit(2)
                        Text([Formato.fechaCorta(l.fecha), l.categoria].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formato.dinero(l.monto)).foregroundStyle(l.monto < 0 ? Semantica.ingreso : .primary)
                }
            }
            Divider()
            FilaValor(etiqueta: "Total del corte", valor: Formato.dinero(d.total), negrita: true)
            if d.estado == "pendiente", let c = d.compromisoId {
                NavigationLink("Ir a pagarlo", value: Ruta.compromiso(c)).font(.subheadline)
            }
        }
    }
}

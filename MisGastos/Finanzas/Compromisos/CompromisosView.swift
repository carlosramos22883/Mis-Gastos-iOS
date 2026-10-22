import SwiftUI
import Observation

@Observable
final class CompromisosModelo {
    var lista: [Compromiso] = []
    var ciclo: CicloSimple?
    var periodo = "actual"            // actual | proximos | todos
    var estado: String?               // pendiente | vencido | pagado | cancelado
    var pagina = 1
    var hayMas = false
    var cargando = false
    var error: String?

    func cargar() async {
        cargando = lista.isEmpty
        do {
            let r: PaginaCompromisos = try await API.shared.get("/compromisos", ["periodo": periodo, "estado": estado, "page": "1", "per_page": "30"])
            lista = r.data; ciclo = r.ciclo; pagina = 1; hayMas = r.meta.currentPage < r.meta.lastPage; error = nil
        } catch { self.error = error.localizedDescription }
        cargando = false
    }

    func cargarMas() async {
        guard hayMas, let r: PaginaCompromisos = try? await API.shared.get("/compromisos", ["periodo": periodo, "estado": estado, "page": String(pagina + 1), "per_page": "30"]) else { return }
        lista += r.data; pagina = r.meta.currentPage; hayMas = r.meta.currentPage < r.meta.lastPage
    }
}

/// Color de cada estado (siempre acompañado de su texto).
func colorEstado(_ estadoVisual: String) -> Color {
    switch estadoVisual {
    case "pagado": Semantica.ingreso
    case "vencido", "antiguo": Semantica.egreso
    case "parcial": Semantica.aviso
    case "cancelado": .secondary
    default: Semantica.info
    }
}

struct CompromisosView: View {
    @State private var modelo = CompromisosModelo()
    @State private var nuevo = false
    @State private var aviso: String?

    var body: some View {
        List {
            Section {
                Picker("Período", selection: Binding(get: { modelo.periodo }, set: { v in modelo.periodo = v; modelo.lista = []; Task { await modelo.cargar() } })) {
                    Text("Este ciclo").tag("actual"); Text("Próximos").tag("proximos"); Text("Todos").tag("todos")
                }.pickerStyle(.segmented)
                Picker("Estado", selection: Binding(get: { modelo.estado ?? "" }, set: { v in modelo.estado = v.isEmpty ? nil : v; modelo.lista = []; Task { await modelo.cargar() } })) {
                    Text("Cualquier estado").tag(""); Text("Pendientes").tag("pendiente"); Text("Vencidos").tag("vencido")
                    Text("Pagados").tag("pagado"); Text("Cancelados").tag("cancelado")
                }
                if let c = modelo.ciclo, modelo.periodo == "actual" {
                    Text("Ciclo \(Formato.rango(c.inicio, c.fin))").font(.caption).foregroundStyle(.secondary)
                }
            }
            if modelo.cargando { ProgressView().frame(maxWidth: .infinity) }
            else if let e = modelo.error, modelo.lista.isEmpty { ErrorConReintento(mensaje: e) { Task { await modelo.cargar() } } }
            else if modelo.lista.isEmpty { Text("No hay compromisos con estos filtros.").foregroundStyle(.secondary) }
            ForEach(modelo.lista) { c in
                NavigationLink(value: Ruta.compromiso(c.id)) { fila(c) }
                    .onAppear { if c == modelo.lista.last { Task { await modelo.cargarMas() } } }
            }
        }
        .navigationTitle("Compromisos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo compromiso") }
        }
        .refreshable { await modelo.cargar() }
        .task { await modelo.cargar() }
        .sheet(isPresented: $nuevo) { FormularioCompromiso(modo: .nuevo) { aviso = $0; Task { await modelo.cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func fila(_ c: Compromiso) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Formato.color(c.tarjeta?.color ?? c.categoria?.color, Color(.separator))).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.descripcion).font(.subheadline).lineLimit(2)
                HStack(spacing: 6) {
                    Text([c.fechaEsperada.map { Formato.fechaCorta($0) } ?? "Sin fecha", c.numeroCuota.map { "cuota \($0)" + (c.totalCuotas.map { "/\($0)" } ?? "") }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Insignia(texto: c.estadoTexto, color: colorEstado(c.estadoVisual))
                }
            }
            Spacer()
            Text(Formato.dinero(c.estado == "pendiente" ? c.saldoPendiente : c.monto)).fontWeight(.semibold)
        }
    }
}

/// Detalle de un compromiso: pagar (desde efectivo, cuenta u otra tarjeta) o cancelar.
struct CompromisoDetalleView: View {
    let id: Int
    @State private var compromiso: Compromiso?
    @State private var error: String?
    @State private var pagando = false
    @State private var editando: FormularioCompromiso.Modo?
    @State private var cancelarSerie: Bool?
    @State private var aviso: String?
    @Environment(\.dismiss) private var volver
    private let comunes = Comunes.shared

    var body: some View {
        Group {
            if let c = compromiso { contenido(c) }
            else if let error { ErrorConReintento(mensaje: error) { Task { await cargar() } } }
            else { Cargando() }
        }
        .navigationTitle("Compromiso")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cargar()
            #if DEBUG
            if ArranqueDebug.abrir == "pago:\(id)" { pagando = true }
            if ArranqueDebug.abrir == "serie:\(id)", let c = compromiso { editando = .serie(c) }
            #endif
        }
        .sheet(isPresented: $pagando) {
            if let c = compromiso { FormularioPago(compromiso: c) { aviso = "Pago registrado."; Task { await cargar() } } }
        }
        .sheet(isPresented: Binding(get: { editando != nil }, set: { if !$0 { editando = nil } })) {
            if let m = editando { FormularioCompromiso(modo: m) { aviso = $0; Task { await cargar() } } }
        }
        .confirmationDialog(cancelarSerie == true ? "¿Cancelar la serie?" : "¿Cancelar este pago?", isPresented: Binding(get: { cancelarSerie != nil }, set: { if !$0 { cancelarSerie = nil } }), titleVisibility: .visible) {
            Button("Sí, cancelar", role: .destructive) { Task { await cancelar(serie: cancelarSerie == true) } }
        } message: {
            Text(cancelarSerie == true ? "Se cancela este pago y ya no se generan los siguientes." : "Los demás pagos de la serie siguen igual.")
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func contenido(_ c: Compromiso) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(c.descripcion).font(.title3.weight(.semibold))
                    Insignia(texto: c.estadoTexto, color: colorEstado(c.estadoVisual))
                    Text(Formato.dinero(c.estado == "pendiente" ? c.saldoPendiente : c.monto)).font(.system(size: 32, weight: .bold))
                }
            }
            Section("Detalle") {
                FilaValor(etiqueta: "Monto", valor: Formato.dinero(c.monto))
                FilaValor(etiqueta: "Pagado", valor: Formato.dinero(c.montoPagado))
                FilaValor(etiqueta: "Pendiente", valor: Formato.dinero(c.saldoPendiente), negrita: true)
                FilaValor(etiqueta: "Fecha esperada", valor: c.fechaEsperada.map { Formato.fechaLarga($0) } ?? "Sin fecha")
                if let n = c.numeroCuota { FilaValor(etiqueta: "Cuota", valor: "\(n)" + (c.totalCuotas.map { " de \($0)" } ?? "")) }
                if let t = c.tarjeta { FilaValor(etiqueta: "Tarjeta", valor: t.nombre ?? "") }
                if let cat = c.categoria { FilaValor(etiqueta: "Categoría", valor: cat.nombre) }
                if let con = c.contacto { FilaValor(etiqueta: "Con", valor: con.nombre) }
                if let r = c.recurrente { FilaValor(etiqueta: "Se repite", valor: r.descripcionFrecuencia ?? r.frecuencia) }
                if let q = comunes.quien(c.userId) { FilaValor(etiqueta: "Registrado por", valor: q) }
                if let com = c.comentario, !com.isEmpty { Text(com).font(.footnote).foregroundStyle(.secondary) }
            }
            if let abonos = c.abonos, !abonos.isEmpty {
                Section("Pagos en efectivo") {
                    ForEach(abonos) { a in FilaValor(etiqueta: "\(Formato.fechaCorta(a.fecha)) · \(a.descripcion)", valor: Formato.dinero(a.monto)) }
                }
            }
            if c.estado == "pendiente" {
                Section {
                    Button("Pagar") { pagando = true }.frame(maxWidth: .infinity).buttonStyle(.borderedProminent)
                    if c.tarjeta == nil { Button("Editar este pago") { editando = .pago(c) } }
                    if let r = c.recurrente, r.activo { Button("Editar la serie (\(r.descripcionFrecuencia ?? r.frecuencia))") { editando = .serie(c) } }
                    Button("Cancelar este pago") { cancelarSerie = false }
                    if c.recurrente?.activo == true { Button("Cancelar la serie", role: .destructive) { cancelarSerie = true } }
                }
            }
        }
        .refreshable { await cargar() }
    }

    private func cargar() async {
        do {
            let r: Envoltura<Compromiso> = try await API.shared.get("/compromisos/\(id)")
            compromiso = r.data; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func cancelar(serie: Bool) async {
        do {
            try await API.shared.borrar("/compromisos/\(id)", ["alcance": serie ? "serie" : "pago"])
            volver()
        } catch { aviso = error.localizedDescription }
    }
}

/// Pagar un compromiso (completo o un abono). Si es el estado de cuenta de una tarjeta no pide categoría.
struct FormularioPago: View {
    let compromiso: Compromiso
    let alPagar: () -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var origenes: [(String, String)] = []
    @State private var origen: String?
    @State private var monto = ""
    @State private var fecha = Date()
    @State private var descripcion = ""
    @State private var categoriaId: Int?
    @State private var userId: Int?
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if origenes.isEmpty { ProgressView() }
                    Picker("¿De dónde sale?", selection: $origen) {
                        ForEach(origenes, id: \.0) { Text($0.1).tag($0.0 as String?) }
                    }
                    ErrorCampo(texto: errores["origen"])
                    if origen?.hasPrefix("tarjeta:") == true {
                        Text("Se registra como una compra en esa tarjeta (ej. pagar Credisiman con la Atlántida por NPE).").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    CampoMonto(etiqueta: "Monto", valor: $monto, error: errores["monto"])
                    Text("Pendiente: \(Formato.dinero(compromiso.saldoPendiente)) (un monto menor es un abono)").font(.caption).foregroundStyle(.secondary)
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                    ErrorCampo(texto: errores["fecha"])
                    TextField("Descripción", text: $descripcion); ErrorCampo(texto: errores["descripcion"])
                    if compromiso.tarjeta == nil {
                        Picker("Categoría", selection: $categoriaId) {
                            Text("Elegir…").tag(nil as Int?)
                            ForEach(comunes.categoriasDe("egreso")) { Text($0.nombre).tag($0.id as Int?) }
                        }
                        ErrorCampo(texto: errores["categoria_personal_id"])
                    }
                    if comunes.miembros.count > 1 {
                        Picker("¿Quién pagó?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Pagar compromiso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Registrar") { Task { await pagar() } }.disabled(guardando || origenes.isEmpty) }
            }
            .task { await cargarOrigenes() }
        }
    }

    private func cargarOrigenes() async {
        monto = compromiso.saldoPendiente; descripcion = compromiso.descripcion
        categoriaId = compromiso.categoria?.id; userId = comunes.usuario?.id
        do {
            let r: Envoltura<[String: String]> = try await API.shared.get("/compromisos/\(compromiso.id)/origenes-pago")
            // Efectivo primero, luego cuentas y tarjetas (el JSON de un mapa no garantiza el orden)
            let peso: (String) -> Int = { $0 == "efectivo" ? 0 : $0.hasPrefix("cuenta:") ? 1 : 2 }
            origenes = r.data.map { ($0.key, $0.value) }.sorted { (peso($0.0), $0.1) < (peso($1.0), $1.1) }
            origen = origenes.first?.0
        } catch { self.error = error.localizedDescription }
    }

    private func pagar() async {
        var e: [String: String] = [:]
        if origen == nil { e["origen"] = "Elige de dónde sale el dinero." }
        if !Formato.montoValido(monto) { e["monto"] = "Monto positivo con máximo dos decimales." }
        if descripcion.trimmingCharacters(in: .whitespaces).isEmpty { e["descripcion"] = "Escribe una descripción." }
        if compromiso.tarjeta == nil && categoriaId == nil { e["categoria_personal_id"] = "Elige una categoría." }
        errores = e
        guard e.isEmpty, let origen else { return }
        guardando = true
        let cuerpo = PagoCompromisoBody(origen: origen, descripcion: descripcion, monto: monto, fecha: Formato.textoLocal(fecha),
                                        categoriaPersonalId: compromiso.tarjeta == nil ? categoriaId : nil, userId: userId)
        do {
            let _: Envoltura<Compromiso> = try await API.shared.post("/compromisos/\(compromiso.id)/pagar", cuerpo)
            alPagar(); cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje }
        catch { self.error = error.localizedDescription }
        guardando = false
    }
}

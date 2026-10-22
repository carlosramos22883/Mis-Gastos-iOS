import SwiftUI
import Observation

@Observable
final class EfectivoModelo {
    var movimientos: [MovimientoEfectivo] = []
    var ciclo: CicloEfectivo?
    var resumen: ResumenEfectivo?
    var tipo: String?                 // nil = todos
    var cicloConsultado: String?      // fecha dentro del ciclo (nil = actual)
    var pagina = 1
    var hayMas = false
    var cargando = false
    var error: String?

    func cargar() async {
        cargando = movimientos.isEmpty
        do {
            let r: PaginaEfectivo = try await API.shared.get("/efectivo", ["ciclo": cicloConsultado, "tipo": tipo, "page": "1", "per_page": "30"])
            movimientos = r.data; ciclo = r.ciclo; resumen = r.resumen
            pagina = 1; hayMas = r.meta.currentPage < r.meta.lastPage; error = nil
        } catch { self.error = error.localizedDescription }
        cargando = false
    }

    func cargarMas() async {
        guard hayMas else { return }
        if let r: PaginaEfectivo = try? await API.shared.get("/efectivo", ["ciclo": cicloConsultado, "tipo": tipo, "page": String(pagina + 1), "per_page": "30"]) {
            movimientos += r.data; pagina = r.meta.currentPage; hayMas = r.meta.currentPage < r.meta.lastPage
        }
    }

    func irA(_ fecha: String?) async { cicloConsultado = fecha; movimientos = []; await cargar() }
    func filtrar(_ t: String?) async { tipo = t; movimientos = []; await cargar() }
}

/// Efectivo por ciclo: resumen, filtros y movimientos; registrar, editar o eliminar.
struct EfectivoView: View {
    @State private var modelo = EfectivoModelo()
    @State private var editando: MovimientoEfectivo?
    @State private var nuevo = false
    @State private var aviso: String?
    private let comunes = Comunes.shared

    var body: some View {
        List {
            Section {
                encabezado
            }
            .listRowBackground(Color.clear)
            if modelo.cargando {
                ProgressView().frame(maxWidth: .infinity)
            } else if let e = modelo.error, modelo.movimientos.isEmpty {
                ErrorConReintento(mensaje: e) { Task { await modelo.cargar() } }
            } else if modelo.movimientos.isEmpty {
                Text("No hay movimientos en este ciclo.").foregroundStyle(.secondary)
            }
            ForEach(Dictionary(grouping: modelo.movimientos, by: \.fecha).sorted { $0.key > $1.key }, id: \.key) { fecha, lista in
                Section(Formato.fechaLarga(fecha)) {
                    ForEach(lista) { m in
                        Button { abrir(m) } label: { fila(m) }
                            .buttonStyle(.plain)
                            .onAppear { if m == modelo.movimientos.last { Task { await modelo.cargarMas() } } }
                    }
                }
            }
        }
        .navigationTitle("Efectivo")
        .toolbar {
            if modelo.ciclo?.esActual == true {
                Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Registrar movimiento")
            }
        }
        .refreshable { await modelo.cargar() }
        .task {
            if modelo.movimientos.isEmpty { await modelo.cargar() }
            #if DEBUG
            if ArranqueDebug.abrir == "efectivo-nuevo" { nuevo = true }
            #endif
        }
        .sheet(isPresented: $nuevo) { FormularioEfectivo(movimiento: nil, inicioCiclo: modelo.ciclo?.inicio) { mensaje in aviso = mensaje; Task { await modelo.cargar() } } }
        .sheet(item: $editando) { m in FormularioEfectivo(movimiento: m, inicioCiclo: modelo.ciclo?.inicio) { mensaje in aviso = mensaje; Task { await modelo.cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private var encabezado: some View {
        VStack(spacing: 10) {
            HStack {
                Button { Task { await modelo.irA(modelo.ciclo?.anterior) } } label: { Image(systemName: "chevron.left") }
                    .disabled(modelo.ciclo?.anterior == nil).buttonStyle(.borderless)
                Spacer()
                if let c = modelo.ciclo {
                    Text(Formato.rango(c.inicio, c.fin) + (c.esActual ? " · ciclo actual" : "")).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await modelo.irA(modelo.ciclo?.siguiente) } } label: { Image(systemName: "chevron.right") }
                    .disabled(modelo.ciclo?.siguiente == nil).buttonStyle(.borderless)
            }
            if let r = modelo.resumen {
                HStack {
                    cifra("Ingresos", r.ingresos); cifra("Egresos", r.egresos); cifra("Saldo", r.saldo, negrita: true)
                }
            }
            Picker("Tipo", selection: Binding(get: { modelo.tipo ?? "" }, set: { v in Task { await modelo.filtrar(v.isEmpty ? nil : v) } })) {
                Text("Todos").tag(""); Text("Ingresos").tag("ingreso"); Text("Egresos").tag("egreso")
            }.pickerStyle(.segmented)
        }
    }

    private func cifra(_ etiqueta: String, _ valor: String, negrita: Bool = false) -> some View {
        VStack {
            Text(etiqueta).font(.caption2).foregroundStyle(.secondary)
            Text(Formato.dinero(valor)).font(.headline.weight(negrita ? .bold : .medium))
        }.frame(maxWidth: .infinity)
    }

    private func fila(_ m: MovimientoEfectivo) -> some View {
        let ingreso = m.tipo == "ingreso"
        return HStack(spacing: 12) {
            if m.categoria == nil && m.contacto == nil {
                Image(systemName: "arrow.left.arrow.right").frame(width: 36, height: 36).background(Color(.secondarySystemFill), in: Circle())
            } else {
                Avatar(url: m.contacto?.fotoUrl, nombre: m.contacto?.nombre ?? m.categoria?.nombre ?? "?", color: Formato.color(m.categoria?.color), tamano: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.descripcion).font(.subheadline).lineLimit(2).foregroundStyle(.primary)
                Text([m.categoria?.nombre, m.contacto?.nombre, comunes.quien(m.userId)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !m.editable { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
            Text((ingreso ? "+" : "−") + Formato.dinero(m.monto)).fontWeight(.semibold).foregroundStyle(ingreso ? Semantica.ingreso : Semantica.egreso)
        }
        .contentShape(Rectangle())
    }

    private func abrir(_ m: MovimientoEfectivo) {
        if m.editable { editando = m; return }
        aviso = m.compromisoId != nil ? "Es el pago de un compromiso: se modifica desde Compromisos."
            : "Este movimiento se modifica desde su módulo (deudas, préstamos, ingresos o transferencias)."
    }
}

/// Lo que el formulario necesita de un movimiento de efectivo o de una cuenta para editarlo.
nonisolated protocol MovimientoEditable {
    var id: Int { get }
    var tipo: String { get }
    var descripcion: String { get }
    var monto: String { get }
    var fecha: String { get }
    var categoria: CategoriaMini? { get }
    var userId: Int? { get }
    var contacto: ContactoMini? { get }
}

extension MovimientoEfectivo: MovimientoEditable {}

/// Registrar o editar un ingreso/egreso de efectivo o de una cuenta (base: "/efectivo" o "/cuentas/{id}/movimientos").
struct FormularioEfectivo: View {
    let movimiento: (any MovimientoEditable)?
    let inicioCiclo: String?
    var base = "/efectivo"
    let alGuardar: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var tipo = "egreso"
    @State private var descripcion = ""
    @State private var monto = ""
    @State private var fecha = Date()
    @State private var categoriaId: Int?
    @State private var userId: Int?
    @State private var contactoId: Int?
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    @State private var confirmarBorrar = false
    private let comunes = Comunes.shared
    /// Primera fecha permitida: el inicio del ciclo actual.
    private var desde: Date { inicioCiclo.map { Formato.fechaLocal($0) } ?? .distantPast }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo", selection: $tipo) { Text("Egreso").tag("egreso"); Text("Ingreso").tag("ingreso") }
                    .pickerStyle(.segmented)
                    .onChange(of: tipo) { _, _ in if !comunes.categoriasDe(tipo).contains(where: { $0.id == categoriaId }) { categoriaId = nil } }
                Section {
                    TextField("Descripción", text: $descripcion); ErrorCampo(texto: errores["descripcion"])
                    CampoMonto(etiqueta: "Monto", valor: $monto, error: errores["monto"])
                    DatePicker("Fecha", selection: $fecha, in: desde...Date(), displayedComponents: .date)
                    ErrorCampo(texto: errores["fecha"])
                }
                Section {
                    Picker("Categoría", selection: $categoriaId) {
                        Text("Elegir…").tag(nil as Int?)
                        ForEach(comunes.categoriasDe(tipo)) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    ErrorCampo(texto: errores["categoria_personal_id"])
                    if comunes.miembros.count > 1 {
                        Picker("¿Quién lo hizo?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                    Picker("¿Con quién?", selection: $contactoId) {
                        Text("Nadie").tag(nil as Int?)
                        ForEach(comunes.contactos.filter { $0.activo || $0.id == contactoId }) { Text($0.nombreCompleto).tag($0.id as Int?) }
                    }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
                if movimiento != nil {
                    Button("Eliminar movimiento", role: .destructive) { confirmarBorrar = true }
                }
            }
            .navigationTitle(movimiento == nil ? "Nuevo movimiento" : "Editar movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
            .confirmationDialog("¿Eliminar este movimiento?", isPresented: $confirmarBorrar, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) { Task { await eliminar() } }
            }
            .onAppear(perform: llenar)
        }
    }

    private func llenar() {
        userId = comunes.usuario?.id
        guard let m = movimiento else { return }
        tipo = m.tipo; descripcion = m.descripcion; monto = m.monto; fecha = Formato.fechaLocal(m.fecha)
        categoriaId = m.categoria?.id; userId = m.userId; contactoId = m.contacto?.id
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if descripcion.trimmingCharacters(in: .whitespaces).isEmpty { e["descripcion"] = "Escribe una descripción." }
        if !Formato.montoValido(monto) { e["monto"] = "Monto positivo con máximo dos decimales." }
        if categoriaId == nil { e["categoria_personal_id"] = "Elige una categoría." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        let cuerpo = MovimientoEfectivoBody(tipo: tipo, descripcion: descripcion.trimmingCharacters(in: .whitespaces), monto: monto,
                                            fecha: Formato.textoLocal(fecha), categoriaPersonalId: categoriaId, userId: userId, contactoId: contactoId.map(String.init))
        do {
            if let m = movimiento {
                try await API.shared.enviar("PUT", "\(base)/\(m.id)", cuerpo)
            } else {
                try await API.shared.enviar("POST", base, cuerpo)
            }
            alGuardar(movimiento == nil ? "Movimiento registrado." : "Movimiento actualizado.")
            cerrar()
        } catch let f as FallaAPI {
            errores = f.campos; error = f.mensaje
        } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let m = movimiento else { return }
        do {
            try await API.shared.borrar("\(base)/\(m.id)")
            alGuardar("Movimiento eliminado.")
            cerrar()
        } catch { self.error = error.localizedDescription }
    }
}

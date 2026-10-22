import SwiftUI

/// Cuentas y billeteras con su saldo; transferir y crear cuentas.
struct CuentasView: View {
    @State private var cuentas: [Cuenta] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var transferir = false
    @State private var nueva = false
    @State private var aviso: String?
    private let comunes = Comunes.shared

    var body: some View {
        List {
            if cargando && cuentas.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, cuentas.isEmpty {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else if cuentas.isEmpty {
                Text("Aún no hay cuentas. Créala con el botón +.").foregroundStyle(.secondary)
            } else {
                Section {
                    FilaValor(etiqueta: "Total en cuentas", valor: Formato.dinero(cuentas.filter(\.activo).reduce(0) { $0 + (Double($1.saldo) ?? 0) }), negrita: true)
                }
                Section {
                    ForEach(cuentas) { c in
                        NavigationLink(value: Ruta.cuenta(c.id)) { fila(c) }
                    }
                }
            }
        }
        .navigationTitle("Cuentas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { transferir = true } label: { Label("Transferir", systemImage: "arrow.left.arrow.right") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva cuenta")
            }
        }
        .task { await cargar() }
        .refreshable { await cargar() }
        .sheet(isPresented: $transferir) { FormularioTransferencia { aviso = "Transferencia registrada."; Task { await cargar() } } }
        .sheet(isPresented: $nueva) { FormularioCuenta(cuenta: nil) { aviso = $0; Task { await cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func fila(_ c: Cuenta) -> some View {
        let saldo = Double(c.saldo) ?? 0
        return HStack(spacing: 12) {
            Avatar(url: c.banco?.logoUrl, nombre: c.banco?.nombre ?? c.nombre, color: Formato.color(c.color), tamano: 40, cuadrado: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.nombre).font(.subheadline.weight(.medium))
                Text([c.tipoCuenta?.nombre, comunes.quien(c.userId)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if !c.activo { Insignia(texto: "Inactiva", color: .secondary) }
            }
            Spacer()
            Text(Formato.dinero(saldo)).fontWeight(.semibold).foregroundStyle(saldo < 0 ? Semantica.egreso : .primary)
        }
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<[Cuenta]> = try await API.shared.get("/cuentas")
            cuentas = r.data
        } catch { self.error = error.localizedDescription }
        cargando = false
    }
}

@Observable
final class CuentaModelo {
    let id: Int
    var cuenta: Cuenta?
    var ciclo: CicloEfectivo?
    var resumen: ResumenCuenta?
    var movimientos: [MovimientoCuenta] = []
    var cargando = true
    var error: String?
    var tipo: String?
    private var cicloConsultado: String?
    private var pagina = 1
    private var hayMas = false
    private var cargandoMas = false

    init(id: Int) { self.id = id }

    func cargar() async {
        error = nil
        do {
            let r: PaginaCuenta = try await API.shared.get("/cuentas/\(id)", ["ciclo": cicloConsultado, "tipo": tipo, "page": "1", "per_page": "30"])
            cuenta = r.cuenta; ciclo = r.ciclo; resumen = r.resumen; movimientos = r.data
            pagina = 1; hayMas = r.meta.currentPage < r.meta.lastPage
        } catch { self.error = error.localizedDescription }
        cargando = false
    }

    func cargarMas() async {
        guard hayMas, !cargandoMas else { return }
        cargandoMas = true
        if let r: PaginaCuenta = try? await API.shared.get("/cuentas/\(id)", ["ciclo": cicloConsultado, "tipo": tipo, "page": "\(pagina + 1)", "per_page": "30"]) {
            movimientos += r.data; pagina = r.meta.currentPage; hayMas = r.meta.currentPage < r.meta.lastPage
        }
        cargandoMas = false
    }

    func irA(_ fecha: String?) async { cicloConsultado = fecha; movimientos = []; await cargar() }
    func filtrar(_ t: String?) async { tipo = t; movimientos = []; await cargar() }
}

/// Una cuenta por ciclo: saldo, resumen y movimientos; registrar, transferir o editar la cuenta.
struct CuentaDetalleView: View {
    @State private var modelo: CuentaModelo
    @State private var nuevo = false
    @State private var editando: MovimientoCuenta?
    @State private var transferir = false
    @State private var editarCuenta = false
    @State private var transferencia: TransferenciaMini?
    @State private var aviso: String?
    @Environment(\.dismiss) private var salir
    private let comunes = Comunes.shared

    init(id: Int) { _modelo = State(initialValue: CuentaModelo(id: id)) }

    var body: some View {
        List {
            if let c = modelo.cuenta {
                encabezado(c)
                if modelo.movimientos.isEmpty {
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
            } else if modelo.cargando {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ErrorConReintento(mensaje: modelo.error ?? "No se pudo cargar.") { Task { await modelo.cargar() } }
            }
        }
        .navigationTitle(modelo.cuenta?.nombre ?? "Cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let c = modelo.cuenta {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if modelo.ciclo?.esActual == true && c.activo {
                            Button { nuevo = true } label: { Label("Registrar movimiento", systemImage: "plus") }
                            Button { transferir = true } label: { Label("Transferir desde esta cuenta", systemImage: "arrow.left.arrow.right") }
                        }
                        Button { editarCuenta = true } label: { Label("Editar cuenta", systemImage: "pencil") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task { if modelo.cuenta == nil { await modelo.cargar() } }
        .refreshable { await modelo.cargar() }
        .sheet(isPresented: $nuevo) {
            FormularioEfectivo(movimiento: nil, inicioCiclo: modelo.ciclo?.inicio, base: "/cuentas/\(modelo.id)/movimientos") { aviso = $0; Task { await modelo.cargar() } }
        }
        .sheet(item: $editando) { m in
            FormularioEfectivo(movimiento: m, inicioCiclo: modelo.ciclo?.inicio, base: "/cuentas/\(modelo.id)/movimientos") { aviso = $0; Task { await modelo.cargar() } }
        }
        .sheet(isPresented: $transferir) {
            FormularioTransferencia(origen: "cuenta:\(modelo.id)", destino: "efectivo") { aviso = "Transferencia registrada."; Task { await modelo.cargar() } }
        }
        .sheet(isPresented: $editarCuenta) {
            if let c = modelo.cuenta { FormularioCuenta(cuenta: c) { aviso = $0; Task { await modelo.cargar() } } alEliminar: { salir() } }
        }
        .confirmationDialog(transferencia.map { "Transferencia \($0.origen) → \($0.destino)" } ?? "", isPresented: Binding(get: { transferencia != nil }, set: { if !$0 { transferencia = nil } }), titleVisibility: .visible, presenting: transferencia) { t in
            if t.eliminable {
                Button("Eliminar transferencia", role: .destructive) { Task { await eliminar(t) } }
            }
        } message: { t in
            Text(t.eliminable ? "Se elimina completa: se revierten sus dos movimientos." : "Es de un ciclo cerrado y ya no se puede eliminar.")
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    @ViewBuilder
    private func encabezado(_ c: Cuenta) -> some View {
        Section {
            HStack(spacing: 12) {
                Avatar(url: c.banco?.logoUrl, nombre: c.banco?.nombre ?? c.nombre, color: Formato.color(c.color), tamano: 44, cuadrado: true)
                VStack(alignment: .leading) {
                    Text("Saldo actual").font(.caption).foregroundStyle(.secondary)
                    Text(Formato.dinero(c.saldo)).font(.title2.bold())
                }
                Spacer()
                if let q = comunes.quien(c.userId) { Text(q).font(.caption).foregroundStyle(.secondary) }
            }
            NavegadorCiclo(ciclo: modelo.ciclo) { fecha in Task { await modelo.irA(fecha) } }
            if let r = modelo.resumen {
                HStack {
                    cifra("Inicio", r.saldoInicial)
                    cifra("Ingresos", r.ingresos)
                    cifra("Egresos", r.egresos)
                    cifra("Final", r.saldoFinal)
                }
            }
            Picker("Tipo", selection: Binding(get: { modelo.tipo ?? "" }, set: { t in Task { await modelo.filtrar(t.isEmpty ? nil : t) } })) {
                Text("Todos").tag(""); Text("Ingresos").tag("ingreso"); Text("Egresos").tag("egreso")
            }
            .pickerStyle(.segmented)
        }
    }

    private func cifra(_ etiqueta: String, _ valor: String) -> some View {
        VStack {
            Text(etiqueta).font(.caption2).foregroundStyle(.secondary)
            Text(Formato.dinero(valor)).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }

    private func fila(_ m: MovimientoCuenta) -> some View {
        let ingreso = m.tipo == "ingreso"
        return HStack(spacing: 12) {
            if m.transferencia != nil || (m.categoria == nil && m.contacto == nil) {
                Image(systemName: "arrow.left.arrow.right").frame(width: 36, height: 36).background(Color(.secondarySystemFill), in: Circle())
            } else {
                Avatar(url: m.contacto?.fotoUrl, nombre: m.contacto?.nombre ?? m.categoria?.nombre ?? "?", color: Formato.color(m.categoria?.color), tamano: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.descripcion).font(.subheadline).lineLimit(2)
                Text([m.categoria?.nombre, m.contacto?.nombre, comunes.quien(m.userId), m.gestionadoEn].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !m.editable && m.transferencia == nil { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
            Text((ingreso ? "+" : "−") + Formato.dinero(m.monto)).fontWeight(.semibold).foregroundStyle(ingreso ? Semantica.ingreso : Semantica.egreso)
        }
        .contentShape(Rectangle())
    }

    private func abrir(_ m: MovimientoCuenta) {
        if let t = m.transferencia { transferencia = t; return }
        if m.editable { editando = m; return }
        aviso = m.gestionadoEn.map { "Este movimiento se modifica desde \($0)." } ?? "Es de un ciclo cerrado: ya no se modifica."
    }

    private func eliminar(_ t: TransferenciaMini) async {
        do {
            try await API.shared.borrar("/transferencias/\(t.id)")
            aviso = "Transferencia eliminada: se revirtieron sus dos movimientos."
            await modelo.cargar()
        } catch { aviso = error.localizedDescription }
    }
}

/// "‹ 23 sep – 22 oct · ciclo actual ›"
struct NavegadorCiclo: View {
    let ciclo: CicloEfectivo?
    let ir: (String?) -> Void

    var body: some View {
        HStack {
            Button { ir(ciclo?.anterior) } label: { Image(systemName: "chevron.left") }
                .disabled(ciclo?.anterior == nil).buttonStyle(.borderless).accessibilityLabel("Ciclo anterior")
            Spacer()
            Text(ciclo.map { Formato.rango($0.inicio, $0.fin) + ($0.esActual ? " · ciclo actual" : "") } ?? "")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button { ir(ciclo?.siguiente) } label: { Image(systemName: "chevron.right") }
                .disabled(ciclo?.siguiente == nil).buttonStyle(.borderless).accessibilityLabel("Ciclo siguiente")
        }
    }
}

/// Mover dinero entre efectivo y cuentas; desde una tarjeta es un avance.
struct FormularioTransferencia: View {
    var origen: String? = nil
    var destino: String? = nil
    let alGuardar: () -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var opciones: OpcionesTransferencia?
    @State private var desde: String?
    @State private var hacia: String?
    @State private var monto = ""
    @State private var fecha = Date()
    @State private var nota = ""
    @State private var userId: Int?
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                if let o = opciones {
                    Section {
                        Picker("Desde", selection: $desde) {
                            ForEach(o.origenes, id: \.valor) { Text(etiqueta($0)).tag($0.valor as String?) }
                        }
                        ErrorCampo(texto: errores["origen"])
                        if desde?.hasPrefix("tarjeta:") == true {
                            Text("Es un avance de efectivo: queda como deuda en la tarjeta y suele cobrar comisión e intereses desde el primer día.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Picker("Hacia", selection: $hacia) {
                            Text("Elegir…").tag(nil as String?)
                            ForEach(o.destinos.filter { $0.valor != desde }, id: \.valor) { Text(etiqueta($0)).tag($0.valor as String?) }
                        }
                        ErrorCampo(texto: errores["destino"])
                    }
                    Section {
                        CampoMonto(etiqueta: "Monto", valor: $monto, error: errores["monto"])
                        DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                        ErrorCampo(texto: errores["fecha"])
                        TextField("Nota (opcional), ej: Chivo 17/10", text: $nota)
                        if comunes.miembros.count > 1 {
                            Picker("¿Quién lo hizo?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                        }
                    }
                    if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Transferir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Transferir") { Task { await guardar() } }.disabled(guardando || opciones == nil) }
            }
            .onChange(of: desde) { _, nuevo in if hacia == nuevo { hacia = nil } }
            .task { await iniciar() }
        }
    }

    private func etiqueta(_ o: OpcionTransferencia) -> String {
        "\(o.nombre) (\(o.valor.hasPrefix("tarjeta:") ? "disponible " : "")\(Formato.dinero(o.saldo)))"
    }

    private func iniciar() async {
        userId = comunes.usuario?.id
        do {
            let r: Envoltura<OpcionesTransferencia> = try await API.shared.get("/transferencias/opciones")
            opciones = r.data
            desde = origen ?? "efectivo"
            hacia = destino ?? r.data.destinos.first { $0.valor != desde }?.valor
        } catch { self.error = error.localizedDescription }
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if desde == nil { e["origen"] = "Elige de dónde sale." }
        if hacia == nil { e["destino"] = "Elige a dónde va." }
        if !Formato.montoValido(monto) { e["monto"] = "Monto positivo con máximo dos decimales." }
        errores = e
        guard e.isEmpty, let desde, let hacia else { return }
        guardando = true
        let nota = self.nota.trimmingCharacters(in: .whitespaces)
        do {
            try await API.shared.enviar("POST", "/transferencias", TransferenciaBody(origen: desde, destino: hacia, monto: monto, fecha: Formato.textoLocal(fecha),
                                                                                    descripcion: nota.isEmpty ? nil : nota, userId: userId))
            alGuardar()
            cerrar()
        } catch let f as FallaAPI {
            errores = f.campos; error = f.mensaje
        } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

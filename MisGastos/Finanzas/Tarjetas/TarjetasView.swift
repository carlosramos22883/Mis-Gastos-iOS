import SwiftUI

/// Formas de ordenar (las mismas de la web y Android).
let ordenesTarjeta: [(String, String)] = [
    ("disponible", "Más disponible"), ("deuda", "Más endeudada"), ("uso", "Más usada (% del límite)"),
    ("corte", "Corte más próximo"), ("pago", "Pago más próximo"), ("limite", "Límite más alto"), ("nombre", "Nombre"),
]

private func num(_ t: String?) -> Double { Double(t ?? "") ?? 0 }

extension Array where Element == Tarjeta {
    /// Activas primero; dentro, según el orden elegido; empata por nombre.
    func ordenadas(_ orden: String) -> [Tarjeta] {
        sorted { a, b in
            if a.activo != b.activo { return a.activo }
            let clave: (Tarjeta) -> Double? = { t in
                switch orden {
                case "disponible": -num(t.disponible)
                case "deuda": -num(t.deuda)
                case "uso": -num(t.deuda) / Swift.max(num(t.limiteCredito), 1)
                case "limite": -num(t.limiteCredito)
                default: nil
                }
            }
            if let x = clave(a), let y = clave(b), x != y { return x < y }
            if orden == "corte", (a.proximoCorte ?? "9999") != (b.proximoCorte ?? "9999") { return (a.proximoCorte ?? "9999") < (b.proximoCorte ?? "9999") }
            if orden == "pago", (a.porPagar?.fecha ?? "9999") != (b.porPagar?.fecha ?? "9999") { return (a.porPagar?.fecha ?? "9999") < (b.porPagar?.fecha ?? "9999") }
            return a.nombre.localizedCaseInsensitiveCompare(b.nombre) == .orderedAscending
        }
    }
}

/// Tarjetas de crédito: resumen, orden y cada tarjeta con su color.
struct TarjetasView: View {
    @State private var tarjetas: [Tarjeta] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var nueva = false
    @State private var aviso: String?
    @AppStorage("tarjetas_orden") private var orden = "nombre"
    private let comunes = Comunes.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if cargando && tarjetas.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if let error, tarjetas.isEmpty {
                    ErrorConReintento(mensaje: error) { Task { await cargar() } }
                } else if tarjetas.isEmpty {
                    Text("Aún no hay tarjetas.").foregroundStyle(.secondary).padding(.top, 40)
                    Button("Agregar tarjeta") { nueva = true }
                } else {
                    let activas = tarjetas.filter(\.activo)
                    Seccion("Resumen") {
                        FilaValor(etiqueta: "Disponible", valor: Formato.dinero(activas.reduce(0) { $0 + num($1.disponible) }), negrita: true)
                        FilaValor(etiqueta: "Deuda total", valor: Formato.dinero(activas.reduce(0) { $0 + num($1.deuda) }))
                        FilaValor(etiqueta: "Por pagar (estados de cuenta)", valor: Formato.dinero(activas.reduce(0) { $0 + num($1.porPagar?.monto) }))
                    }
                    HStack {
                        Text("Ordenar por").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Picker("Ordenar por", selection: $orden) { ForEach(ordenesTarjeta, id: \.0) { Text($0.1).tag($0.0) } }
                    }
                    ForEach(tarjetas.ordenadas(orden)) { t in
                        NavigationLink(value: Ruta.tarjeta(t.id)) { TarjetaVisual(tarjeta: t) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Semantica.fondo)
        .navigationTitle("Tarjetas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva tarjeta") }
        }
        .task { await cargar() }
        .refreshable { await cargar() }
        .sheet(isPresented: $nueva) { FormularioTarjeta(tarjeta: nil) { aviso = $0; Task { await cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<[Tarjeta]> = try await API.shared.get("/tarjetas")
            tarjetas = r.data
        } catch { self.error = error.localizedDescription }
        cargando = false
    }
}

/// La tarjeta con su color; el texto usa el color de contraste que calcula el servidor. La foto del titular distingue tarjetas parecidas.
struct TarjetaVisual: View {
    let tarjeta: Tarjeta
    private let comunes = Comunes.shared

    var body: some View {
        let t = tarjeta
        let texto = t.colorTexto.map { Formato.color($0) } ?? Formato.textoSobre(t.color)
        let uso = min(max(num(t.deuda) / max(num(t.limiteCredito), 1), 0), 1)
        let titular = comunes.miembros.first { $0.id == t.userId }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Avatar(url: t.banco?.logoUrl, nombre: t.banco?.nombre ?? t.nombre, color: .white, tamano: 32, cuadrado: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.nombre).fontWeight(.semibold).lineLimit(1)
                    Text([comunes.quien(t.userId), t.ultimosDigitos.map { "•••• \($0)" }, t.activo ? nil : "Inactiva"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).opacity(0.85)
                }
                Spacer()
                if let m = t.marca?.logoUrl { Avatar(url: m, nombre: t.marca?.nombre ?? "", color: .white, tamano: 28, cuadrado: true) }
                if comunes.miembros.count > 1, let titular {
                    Avatar(url: Formato.urlAvatar(titular.avatar), nombre: titular.nombre, tamano: 34).padding(2).background(.white, in: Circle())
                }
            }
            Text("Disponible").font(.caption).opacity(0.85).padding(.top, 8)
            Text(Formato.dinero(t.disponible)).font(.title2.bold())
            if num(t.cargosSinRestar) > 0 {
                Text("\(Formato.dinero(num(t.cargosSinRestar))) de cargos del banco aún sin restar").font(.caption).opacity(0.85)
            }
            if num(t.interesesRetenidos) > 0 {
                Text("\(Formato.dinero(num(t.interesesRetenidos))) de intereses retenidos hasta el próximo corte").font(.caption).opacity(0.85)
            }
            ProgressView(value: uso).tint(texto)
            Text("Deuda \(Formato.dinero(t.deuda)) de \(Formato.dinero(t.limiteCredito))").font(.caption).opacity(0.9)
            Text(t.porPagar.map { "Pagar \(Formato.dinero($0.monto)) antes del \(Formato.fechaCorta($0.fecha))" } ?? "Sin pagos pendientes · corta el \(Formato.fechaCorta(t.proximoCorte))")
                .font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(texto.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .foregroundStyle(texto)
        .padding(16)
        .background(Formato.color(t.color, .gray), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Una tarjeta: por pagar, próximo corte, movimientos sin facturar, cuotas, cargos fijos, pagos y estados de cuenta.
struct TarjetaDetalleView: View {
    let id: Int
    @State private var d: TarjetaDetalle?
    @State private var error: String?
    @State private var nuevo = false
    @State private var editando: MovimientoTarjeta?
    @State private var avance = false
    @State private var editarTarjeta = false
    @State private var cargo: CargoFijo?
    @State private var nuevoCargo = false
    @State private var intereses: EstadoCuenta?
    @State private var aviso: String?
    @Environment(\.dismiss) private var salir
    private let comunes = Comunes.shared

    var body: some View {
        ScrollView {
            if let d {
                VStack(spacing: 12) { contenido(d) }.padding(16)
            } else if let error {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else {
                ProgressView().padding(.top, 40)
            }
        }
        .background(Semantica.fondo)
        .navigationTitle(d?.tarjeta.nombre ?? "Tarjeta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let t = d?.tarjeta {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if t.activo {
                            Button { nuevo = true } label: { Label("Registrar compra o cargo", systemImage: "plus") }
                            if t.permiteAvances { Button { avance = true } label: { Label("Avance de efectivo", systemImage: "arrow.left.arrow.right") } }
                        }
                        Button { editarTarjeta = true } label: { Label("Editar tarjeta", systemImage: "pencil") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task {
            await cargar()
            #if DEBUG
            if let h = ArranqueDebug.hoja {
                if h == "cargo-nuevo" { nuevoCargo = true }
                if h.hasPrefix("cargo:"), let c = d?.cargosFijos?.first(where: { "cargo:\($0.id)" == h }) { cargo = c }
            }
            #endif
        }
        .refreshable { await cargar() }
        .sheet(isPresented: $nuevo) {
            FormularioMovTarjeta(tarjetaId: id, movimiento: nil, titularId: d?.tarjeta.userId, desde: d?.periodoAbierto.desde) { aviso = $0; Task { await cargar() } }
        }
        .sheet(item: $editando) { m in
            FormularioMovTarjeta(tarjetaId: id, movimiento: m, titularId: nil, desde: d?.periodoAbierto.desde) { aviso = $0; Task { await cargar() } }
        }
        .sheet(isPresented: $avance) {
            FormularioTransferencia(origen: "tarjeta:\(id)", destino: "efectivo") { aviso = "Avance registrado."; Task { await cargar() } }
        }
        .sheet(isPresented: $nuevoCargo) {
            FormularioCargoFijo(tarjetaId: id, cargo: nil, proximoCorte: d?.periodoAbierto.corte) { aviso = $0; Task { await cargar() } }
        }
        .sheet(item: $cargo) { c in
            FormularioCargoFijo(tarjetaId: id, cargo: c, proximoCorte: d?.periodoAbierto.corte) { aviso = $0; Task { await cargar() } }
        }
        .sheet(item: $intereses) { e in
            FormularioIntereses(tarjetaId: id, estado: e) { aviso = $0; Task { await cargar() } }
        }
        .sheet(isPresented: $editarTarjeta) {
            if let t = d?.tarjeta { FormularioTarjeta(tarjeta: t) { aviso = $0; Task { await cargar() } } alEliminar: { salir() } }
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    @ViewBuilder
    private func contenido(_ d: TarjetaDetalle) -> some View {
        TarjetaVisual(tarjeta: d.tarjeta)
        if !d.porPagar.isEmpty {
            Seccion("Por pagar") {
                ForEach(d.porPagar) { p in
                    NavigationLink(value: Ruta.compromiso(p.compromiso.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.compromiso.descripcion).font(.subheadline).lineLimit(2)
                                Spacer()
                                Text(Formato.dinero(p.compromiso.saldoPendiente)).fontWeight(.semibold)
                            }
                            Text("Vence \(Formato.fechaLarga(p.compromiso.fechaEsperada))").font(.caption).foregroundStyle(.secondary)
                            if let c = p.costoDeNoPagar {
                                Text("No pagarlo completo costaría al menos \(Formato.dinero(c.interesMes)) de interés al mes (\(c.tasa.formatted()) % anual).")
                                    .font(.caption).foregroundStyle(Semantica.aviso)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        let cargos = num(d.cargosProximoCorte)
        Seccion("Próximo corte · \(Formato.fechaCorta(d.periodoAbierto.corte))") {
            FilaValor(etiqueta: "Lleva acumulado", valor: Formato.dinero(num(d.porFacturar.total) + cargos), negrita: true)
            if cargos > 0 {
                Text("Incluye \(Formato.dinero(cargos)) de cargos fijos que se suman al cortar.").font(.caption).foregroundStyle(.secondary)
            }
            if num(d.porFacturar.saldoAFavor) < 0 {
                Text("Incluye el saldo a favor del corte anterior (\(Formato.dinero(-num(d.porFacturar.saldoAFavor)))).").font(.caption).foregroundStyle(Semantica.ingreso)
            }
            ForEach(d.porFacturar.lineas.filter { $0.cuotaNumero != nil }, id: \.movimientoId) {
                FilaValor(etiqueta: "\($0.descripcion) (cuota \($0.cuotaNumero ?? 0)/\($0.cuotas ?? 0))", valor: Formato.dinero($0.monto))
            }
        }
        Seccion("Movimientos sin facturar") {
            if d.movimientos.isEmpty {
                Text("Nada desde el \(Formato.fechaCorta(d.periodoAbierto.desde)).").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(d.movimientos) { m in
                Button { abrir(m) } label: { filaMovimiento(m) }.buttonStyle(.plain)
                if m.id != d.movimientos.last?.id { Divider() }
            }
        }
        if !d.enCuotas.isEmpty {
            Seccion("Compras en cuotas") {
                ForEach(d.enCuotas) { e in
                    let m = e.movimiento
                    FilaValor(etiqueta: "\(m.descripcion) · \(e.cuotasCobradas)/\(m.cuotas ?? 1) cobradas", valor: "\(Formato.dinero(num(m.monto) / Double(m.cuotas ?? 1)))/mes")
                }
            }
        }
        let fijos = d.cargosFijos ?? []
        if !fijos.isEmpty || d.tarjeta.activo {
            Seccion("Cargos fijos", accion: {
                if d.tarjeta.activo { Button { nuevoCargo = true } label: { Image(systemName: "plus.circle") }.accessibilityLabel("Agregar cargo fijo") }
            }) {
                ForEach(fijos) { c in
                    Button { cargo = c } label: {
                        FilaValor(etiqueta: "\(c.descripcion)\(c.activo ? "" : " (inactivo)") · cada corte", valor: Formato.dinero(c.monto)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text("Seguro, membresía… se agregan solos a cada estado de cuenta, una vez por corte.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Seccion("Pagos realizados") {
            let pagos = d.pagos ?? []
            if pagos.isEmpty { Text("Aún no hay pagos registrados a esta tarjeta.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(pagos) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.descripcion).font(.subheadline).lineLimit(1)
                        Text("\(Formato.fechaCorta(p.fecha)) · desde \(p.desde)" + (comunes.quien(p.userId).map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formato.dinero(p.monto)).fontWeight(.semibold).foregroundStyle(Semantica.ingreso)
                }
            }
        }
        if !d.estadosCuenta.isEmpty {
            Seccion("Estados de cuenta") {
                ForEach(d.estadosCuenta) { e in
                    let fila = HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Corte \(Formato.fechaCorta(e.fechaCorte))").font(.subheadline)
                            Text("Límite \(Formato.fechaCorta(e.fechaLimitePago))").font(.caption).foregroundStyle(.secondary)
                            if num(e.total) < 0 {
                                Text("A favor: se descuenta del corte siguiente").font(.caption).foregroundStyle(Semantica.ingreso)
                            } else if num(e.saldoAnterior) < 0 {
                                Text("Incluye \(Formato.dinero(-num(e.saldoAnterior))) a favor del corte anterior").font(.caption).foregroundStyle(Semantica.ingreso)
                            }
                        }
                        Spacer()
                        switch e.estado {
                        case "pagado": Insignia(texto: "Pagado", color: Semantica.ingreso)
                        case "pendiente": Insignia(texto: "Pendiente", color: Semantica.info)
                        case "cancelado": Insignia(texto: "Cancelado", color: .secondary)
                        default: EmptyView()
                        }
                        Text(Formato.dinero(e.total)).fontWeight(.medium)
                    }.contentShape(Rectangle())
                    if let c = e.compromisoId {
                        NavigationLink(value: Ruta.compromiso(c)) { fila }.buttonStyle(.plain)
                    } else { fila }
                    // Intereses bonificables: se anotan en el último corte (son los que el banco aparta del disponible)
                    let bonificables = num(e.interesesBonificables)
                    if e.id == d.estadosCuenta.first?.id, d.tarjeta.activo {
                        Button(bonificables > 0 ? "Intereses bonificables: \(Formato.dinero(bonificables)) · cambiar" : "Anotar intereses bonificables") { intereses = e }
                            .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    } else if bonificables > 0 {
                        Text("Intereses bonificables: \(Formato.dinero(bonificables))").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func filaMovimiento(_ m: MovimientoTarjeta) -> some View {
        let abono = m.tipo == "credito"
        return HStack(spacing: 10) {
            Avatar(url: m.contacto?.fotoUrl, nombre: m.contacto?.nombre ?? m.categoria?.nombre ?? m.tipoTexto, color: Formato.color(m.categoria?.color, Color(.secondarySystemFill)), tamano: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.descripcion).font(.subheadline).lineLimit(2)
                Text([Formato.fechaCorta(m.fecha), m.tipo == "compra" ? nil : m.tipoTexto, (m.cuotas ?? 0) > 1 ? "\(m.cuotas!) cuotas" : nil, m.categoria?.nombre, comunes.quien(m.userId)]
                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !m.editable { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
            Text((abono ? "−" : "") + Formato.dinero(m.monto)).fontWeight(.semibold).foregroundStyle(abono ? Semantica.ingreso : .primary)
        }
        .contentShape(Rectangle())
    }

    private func abrir(_ m: MovimientoTarjeta) {
        if m.transferenciaId != nil { aviso = "Es un avance: se elimina desde la cuenta o el efectivo al que fue (su transferencia)."; return }
        if let g = m.gestionadoEn { aviso = "Este movimiento se modifica desde \(g)."; return }
        if !m.editable { aviso = "Ya está en un estado de cuenta: no se modifica."; return }
        editando = m
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<TarjetaDetalle> = try await API.shared.get("/tarjetas/\(id)")
            d = r.data
        } catch { self.error = error.localizedDescription }
    }
}

/// Compra (de contado o en cuotas), cargo del banco o crédito (devolución) en una tarjeta.
struct FormularioMovTarjeta: View {
    let tarjetaId: Int
    let movimiento: MovimientoTarjeta?
    let titularId: Int?
    let desde: String?
    let alGuardar: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var tipo = "compra"
    @State private var descripcion = ""
    @State private var monto = ""
    @State private var cuotas = ""
    @State private var fecha = Date()
    @State private var categoriaId: Int?
    @State private var userId: Int?
    @State private var contactoId: Int?
    @State private var comentario = ""
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    @State private var confirmarBorrar = false
    private let comunes = Comunes.shared
    private var primerDia: Date { desde.map { Formato.fechaLocal($0) } ?? .distantPast }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $tipo) { Text("Compra").tag("compra"); Text("Cargo").tag("cargo"); Text("Crédito").tag("credito") }
                        .pickerStyle(.segmented)
                } footer: {
                    Text(tipo == "cargo" ? "Intereses, seguro, comisiones o mora que cobra el banco."
                         : tipo == "credito" ? "Devolución o promoción: baja la deuda."
                         : "Con cuotas es una compra a plazos (tasa cero): cada corte cobra una parte.")
                }
                Section {
                    TextField("Descripción", text: $descripcion); ErrorCampo(texto: errores["descripcion"])
                    CampoMonto(etiqueta: "Monto", valor: $monto, error: errores["monto"])
                    if tipo == "compra" {
                        LabeledContent("Cuotas") {
                            TextField("Contado", text: $cuotas).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                .onChange(of: cuotas) { _, n in let l = String(n.filter(\.isNumber).prefix(2)); if l != n { cuotas = l } }
                        }
                        ErrorCampo(texto: errores["cuotas"])
                    }
                    DatePicker("Fecha", selection: $fecha, in: primerDia...Date(), displayedComponents: .date)
                    ErrorCampo(texto: errores["fecha"])
                }
                Section {
                    if tipo != "credito" {
                        Picker("Categoría", selection: $categoriaId) {
                            Text("Sin categoría").tag(nil as Int?)
                            ForEach(comunes.categoriasDe("egreso")) { Text($0.nombre).tag($0.id as Int?) }
                        }
                    }
                    if comunes.miembros.count > 1 {
                        Picker("¿Quién la usó?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                    Picker("¿Con quién?", selection: $contactoId) {
                        Text("Nadie").tag(nil as Int?)
                        ForEach(comunes.contactos.filter { $0.activo || $0.id == contactoId }) { Text($0.nombreCompleto).tag($0.id as Int?) }
                    }
                    TextField("Comentario (opcional)", text: $comentario)
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
                if movimiento != nil { Button("Eliminar movimiento", role: .destructive) { confirmarBorrar = true } }
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
        userId = titularId ?? comunes.usuario?.id
        guard let m = movimiento else { return }
        tipo = m.tipo; descripcion = m.descripcion; monto = m.monto; fecha = Formato.fechaLocal(m.fecha)
        cuotas = (m.cuotas ?? 0) > 1 ? "\(m.cuotas!)" : ""; categoriaId = m.categoria?.id; userId = m.userId
        contactoId = m.contacto?.id; comentario = m.comentario ?? ""
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if descripcion.trimmingCharacters(in: .whitespaces).isEmpty { e["descripcion"] = "Escribe una descripción." }
        if !Formato.montoValido(monto) { e["monto"] = "Monto positivo con máximo dos decimales." }
        let nCuotas = Int(cuotas)
        if !cuotas.isEmpty && !(2...60).contains(nCuotas ?? 0) { e["cuotas"] = "Entre 2 y 60 cuotas (vacío = de contado)." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        let nota = comentario.trimmingCharacters(in: .whitespaces)
        let cuerpo = MovimientoTarjetaBody(tipo: tipo, descripcion: descripcion.trimmingCharacters(in: .whitespaces), monto: monto, fecha: Formato.textoLocal(fecha),
                                           cuotas: tipo == "compra" ? nCuotas : nil, categoriaPersonalId: tipo == "credito" ? nil : categoriaId,
                                           comentario: nota.isEmpty ? nil : nota, userId: userId, contactoId: contactoId.map(String.init))
        do {
            if let m = movimiento {
                try await API.shared.enviar("PUT", "/tarjetas/\(tarjetaId)/movimientos/\(m.id)", cuerpo)
            } else {
                try await API.shared.enviar("POST", "/tarjetas/\(tarjetaId)/movimientos", cuerpo)
            }
            alGuardar(movimiento == nil ? "Movimiento registrado." : "Movimiento actualizado.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let m = movimiento else { return }
        do {
            try await API.shared.borrar("/tarjetas/\(tarjetaId)/movimientos/\(m.id)")
            alGuardar("Movimiento eliminado.")
            cerrar()
        } catch { self.error = error.localizedDescription }
    }
}

/// Cargo fijo de una tarjeta (seguro, membresía…): se suma solo a cada estado de cuenta desde el corte indicado.
struct FormularioCargoFijo: View {
    let tarjetaId: Int
    let cargo: CargoFijo?
    let proximoCorte: String?
    let alGuardar: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var descripcion = ""
    @State private var monto = ""
    @State private var desde = Date()
    @State private var categoriaId: Int?
    @State private var activo = true
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("¿Qué cobra? (ej: Seguro, membresía)", text: $descripcion); ErrorCampo(texto: errores["descripcion"])
                    CampoMonto(etiqueta: "Monto en cada corte", valor: $monto, error: errores["monto"])
                    DatePicker("Desde el corte del", selection: $desde, displayedComponents: .date)
                    ErrorCampo(texto: errores["desde"])
                    Picker("Categoría", selection: $categoriaId) {
                        Text("Sin categoría").tag(nil as Int?)
                        ForEach(comunes.categoriasDe("egreso")) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    if cargo != nil { Toggle("Activo", isOn: $activo) }
                } footer: { Text("Los cambios aplican desde el próximo corte; lo ya cobrado queda en sus estados de cuenta.") }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .barraFormulario(cargo == nil ? "Nuevo cargo fijo" : "Editar cargo fijo", guardando: guardando, guardar: { await guardar() },
                             eliminar: accionEliminar, queSeElimina: "este cargo fijo")
            .onAppear {
                guard let c = cargo else { desde = proximoCorte.map { Formato.fechaLocal($0) } ?? Date(); return }
                descripcion = c.descripcion; monto = c.monto; desde = Formato.fechaLocal(c.desde); categoriaId = c.categoriaPersonalId; activo = c.activo
            }
        }
    }

    private var accionEliminar: (() async -> Void)? {
        guard cargo != nil else { return nil }
        return { await eliminar() }
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if descripcion.trimmingCharacters(in: .whitespaces).isEmpty { e["descripcion"] = "Escribe qué cobra (ej. Seguro)." }
        if !Formato.montoValido(monto) { e["monto"] = "Monto positivo con máximo dos decimales." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        let cuerpo = CargoFijoBody(descripcion: descripcion.trimmingCharacters(in: .whitespaces), monto: monto, desde: Formato.textoLocal(desde), activo: activo, categoriaPersonalId: categoriaId)
        do {
            if let c = cargo {
                try await API.shared.enviar("PUT", "/tarjetas/\(tarjetaId)/cargos-fijos/\(c.id)", cuerpo)
            } else {
                try await API.shared.enviar("POST", "/tarjetas/\(tarjetaId)/cargos-fijos", cuerpo)
            }
            alGuardar(cargo == nil ? "Cargo fijo agregado: se sumará en cada corte." : "Cargo fijo actualizado.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let c = cargo else { return }
        do {
            try await API.shared.borrar("/tarjetas/\(tarjetaId)/cargos-fijos/\(c.id)")
            alGuardar("Cargo fijo eliminado: ya no se sumará en los próximos cortes.")
            cerrar()
        } catch { self.error = error.localizedDescription }
    }
}

/// Intereses bonificables de un corte, tal como vienen en el estado de cuenta del banco.
struct FormularioIntereses: View {
    let tarjetaId: Int
    let estado: EstadoCuenta
    let alGuardar: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var monto = ""
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CampoMonto(etiqueta: "Intereses bonificables", valor: $monto, error: errores["intereses_bonificables"])
                } footer: {
                    Text("Los trae tu estado de cuenta. El banco los aparta del disponible hasta el próximo corte, aunque ya hayas pagado. Si pagaste el total a tiempo, ahí te los devuelve; si no, te los cobra. Déjalo en 0 si tu banco no los aparta.")
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .barraFormulario("Intereses · corte \(Formato.fechaCorta(estado.fechaCorte))", guardando: guardando, guardar: { await guardar() })
            .onAppear {
                let actual = num(estado.interesesBonificables)
                monto = actual > 0 ? String(format: "%.2f", actual) : ""
            }
        }
    }

    private func guardar() async {
        let valor = monto.trimmingCharacters(in: .whitespaces).isEmpty ? "0" : monto.trimmingCharacters(in: .whitespaces)
        guard valor.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil else {
            errores = ["intereses_bonificables": "Monto de cero o más, con máximo dos decimales."]; return
        }
        errores = [:]
        guardando = true
        do {
            let t: Envoltura<Tarjeta> = try await API.shared.patch("/tarjetas/\(tarjetaId)/estados-cuenta/\(estado.id)/intereses", InteresesBody(interesesBonificables: valor))
            alGuardar("Intereses actualizados. Disponible: \(Formato.dinero(t.data.disponible)).")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

import SwiftUI

private func num(_ t: String?) -> Double { Double(t ?? "") ?? 0 }

/// Cómo se paga: "planilla" (descuento), "efectivo", "transferencia", "por_definir"…
func medioPago(_ medio: String?) -> String {
    switch medio {
    case "planilla": "Descuento de planilla"
    case "efectivo": "En ventanilla / efectivo"
    case "transferencia": "Transferencia"
    case "debito": "Débito automático"
    case "por_definir", nil: "Por definir"
    case let m?: m.prefix(1).uppercased() + m.dropFirst()
    }
}

/// Préstamos: resumen y cada préstamo con su avance.
struct PrestamosView: View {
    @State private var prestamos: [Prestamo] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var nuevo = false
    @State private var aviso: String?
    private let comunes = Comunes.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if cargando && prestamos.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if let error, prestamos.isEmpty {
                    ErrorConReintento(mensaje: error) { Task { await cargar() } }
                } else if prestamos.isEmpty {
                    Text("No hay préstamos registrados.").foregroundStyle(.secondary).padding(.top, 40)
                } else {
                    let activos = prestamos.filter(\.activo)
                    Seccion("Resumen") {
                        FilaValor(etiqueta: "Saldo total", valor: Formato.dinero(activos.reduce(0) { $0 + num($1.saldo) }), negrita: true)
                        FilaValor(etiqueta: "Cuotas al mes (con seguros)", valor: Formato.dinero(activos.reduce(0) { $0 + num($1.cuotaTotal) }))
                        FilaValor(etiqueta: "Intereses que faltan por pagar", valor: Formato.dinero(activos.reduce(0) { $0 + num($1.interesesRestantes) }))
                    }
                    ForEach(prestamos) { p in
                        NavigationLink(value: Ruta.prestamo(p.id)) { tarjeta(p) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Semantica.fondo)
        .navigationTitle("Préstamos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo préstamo") }
        }
        .task { await cargar() }
        .refreshable { await cargar() }
        .sheet(isPresented: $nuevo) { FormularioPrestamo(prestamo: nil) { aviso = $0; Task { await cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func tarjeta(_ p: Prestamo) -> some View {
        let color = Formato.color(p.color, .accentColor)
        return HStack(spacing: 0) {
            color.frame(width: 6)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Con banco: su logo; con una persona: la foto del contacto
                    if p.banco == nil, let c = p.contacto {
                        Avatar(url: c.fotoUrl, nombre: c.nombre, tamano: 40)
                    } else {
                        Avatar(url: p.banco?.logoUrl, nombre: p.banco?.nombre ?? p.nombre, color: color, tamano: 40, cuadrado: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.nombre).fontWeight(.semibold)
                        Text([p.acreedor, p.tipo, comunes.quien(p.userId)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !p.activo { Insignia(texto: "Pagado", color: .secondary) }
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text("Saldo").font(.caption2).foregroundStyle(.secondary)
                        Text(Formato.dinero(p.saldo)).font(.title3.bold())
                    }
                    Spacer()
                    if let c = p.cuotaTotal {
                        VStack(alignment: .trailing) {
                            Text("Cuota").font(.caption2).foregroundStyle(.secondary)
                            Text(Formato.dinero(c))
                        }
                    }
                }
                if let a = p.avance {
                    ProgressView(value: min(max(a / 100, 0), 1)).tint(color)
                    Text(String(format: "%.1f %% pagado", a) + (p.proximaFecha.map { " · próximo pago \(Formato.fechaCorta($0))" } ?? "")
                         + (p.fechaFin.map { " · termina \(Formato.fechaCorta($0))" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Semantica.tarjeta)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<[Prestamo]> = try await API.shared.get("/prestamos")
            prestamos = r.data
        } catch { self.error = error.localizedDescription }
        cargando = false
    }
}

/// Un préstamo: datos, pagos registrados y el simulador "¿Y si…?".
struct PrestamoDetalleView: View {
    let id: Int
    @State private var p: Prestamo?
    @State private var error: String?
    @State private var cajas: [String: String] = [:]
    @State private var extra = ""
    @State private var abono = ""
    @State private var modo = "plazo"
    @State private var proyeccion: Proyeccion?
    @State private var pagar = false
    @State private var editar = false
    @State private var borrar: PrestamoPago?
    @State private var aviso: String?
    @Environment(\.dismiss) private var salir
    private let comunes = Comunes.shared

    var body: some View {
        ScrollView {
            if let p {
                VStack(spacing: 12) { contenido(p) }.padding(16)
            } else if let error {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else {
                ProgressView().padding(.top, 40)
            }
        }
        .background(Semantica.fondo)
        .navigationTitle(p?.nombre ?? "Préstamo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if p != nil { ToolbarItem(placement: .primaryAction) { Button("Editar") { editar = true } } } }
        .task { await cargar() }
        .refreshable { await cargar() }
        // Recalcula los escenarios con una pausa corta mientras se escribe
        .task(id: "\(extra)|\(abono)|\(modo)") {
            try? await Task.sleep(for: .milliseconds(450))
            if !Task.isCancelled { await proyectar() }
        }
        .sheet(isPresented: $pagar) {
            if let p { FormularioPagoPrestamo(prestamo: p) { nuevo in self.p = nuevo; aviso = "Pago registrado."; Task { await proyectar() } } }
        }
        .sheet(isPresented: $editar) {
            if let p { FormularioPrestamo(prestamo: p) { aviso = $0; Task { await cargar() } } alEliminar: { salir() } }
        }
        .confirmationDialog("¿Eliminar el último pago?", isPresented: Binding(get: { borrar != nil }, set: { if !$0 { borrar = nil } }), titleVisibility: .visible, presenting: borrar) { pg in
            Button("Eliminar", role: .destructive) { Task { await eliminar(pg) } }
        } message: { pg in Text("\(Formato.dinero(pg.total)) del \(Formato.fechaCorta(pg.fecha)). Se revierte su egreso y el saldo vuelve a como estaba.") }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    @ViewBuilder
    private func contenido(_ p: Prestamo) -> some View {
        Seccion([p.acreedor, p.tipo].compactMap { $0 }.joined(separator: " · ")) {
            FilaValor(etiqueta: "Saldo", valor: Formato.dinero(p.saldo), negrita: true)
            FilaValor(etiqueta: "Monto original", valor: Formato.dinero(p.montoOriginal))
            if let t = p.tasaAnual { FilaValor(etiqueta: "Tasa anual", valor: "\(t) %") }
            if let c = p.cuota { FilaValor(etiqueta: "Cuota (capital + interés)", valor: Formato.dinero(c)) }
            ForEach(p.cargos, id: \.nombre) { FilaValor(etiqueta: $0.nombre, valor: Formato.dinero($0.monto)) }
            if let c = p.cuotaTotal { FilaValor(etiqueta: "Total al mes", valor: Formato.dinero(c), negrita: true) }
            if num(p.montoPlanilla) > 0 { FilaValor(etiqueta: "Descontado de planilla", valor: Formato.dinero(p.montoPlanilla)) }
            FilaValor(etiqueta: "Cómo se paga", valor: medioPago(p.medioPago))
            if let f = p.proximaFecha { FilaValor(etiqueta: "Próximo pago", valor: Formato.fechaLarga(f)) }
            if let f = p.fechaFin { FilaValor(etiqueta: "Termina", valor: "\(Formato.fechaCorta(f)) (\(p.mesesRestantes.map(String.init) ?? "?") meses)") }
            if let i = p.interesesRestantes { FilaValor(etiqueta: "Intereses por pagar", valor: Formato.dinero(i), color: Semantica.egreso) }
        }
        if p.activo {
            Button { pagar = true } label: { Text("Registrar pago").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
        }
        simulador
        Seccion("Pagos registrados") {
            let pagos = p.pagos ?? []
            if pagos.isEmpty { Text("Aún no hay pagos registrados en el sistema.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(pagos.enumerated()), id: \.element.id) { i, pg in
                if i > 0 { Divider() }
                Button { if i == 0 { borrar = pg } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(Formato.fechaCorta(pg.fecha)) · \(nombreOrigen(pg.origen, cajas))").font(.subheadline)
                            Spacer()
                            Text(Formato.dinero(pg.total)).fontWeight(.semibold)
                        }
                        Text("Capital \(Formato.dinero(pg.capital)) · interés \(Formato.dinero(pg.interes))"
                             + (num(pg.cargos) > 0 ? " · cargos \(Formato.dinero(pg.cargos))" : "") + (num(pg.mora) > 0 ? " · mora \(Formato.dinero(pg.mora))" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                        if i == 0 { Text("Toca para eliminar el último pago").font(.caption2).foregroundStyle(.tertiary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(i != 0)
            }
        }
    }

    /// "¿Y si…?": pagar todo hoy, abonar algo extra cada mes o hacer un abono único.
    private var simulador: some View {
        Seccion("¿Y si…?") {
            if let h = proyeccion?.pagarHoy {
                Text("Pagarlo todo hoy").font(.subheadline.weight(.semibold))
                FilaValor(etiqueta: "Habría que pagar", valor: Formato.dinero(h.monto), negrita: true)
                FilaValor(etiqueta: "Ahorro en intereses y cargos", valor: Formato.dinero(h.ahorro), color: Semantica.ingreso)
                Divider()
            }
            Text("Abonar algo extra cada mes").font(.subheadline.weight(.semibold))
            CampoMonto(etiqueta: "Extra mensual", valor: $extra)
            if let x = proyeccion?.extraMensual {
                FilaValor(etiqueta: "Terminaría", valor: "\(Formato.fechaCorta(x.tabla.fechaFin)) (\(x.mesesMenos) meses antes)")
                FilaValor(etiqueta: "Ahorro", valor: Formato.dinero(x.ahorro), color: Semantica.ingreso, negrita: true)
            }
            Divider()
            Text("Hacer un abono único hoy").font(.subheadline.weight(.semibold))
            CampoMonto(etiqueta: "Abono", valor: $abono)
            Picker("Modo", selection: $modo) { Text("Acortar el plazo").tag("plazo"); Text("Bajar la cuota").tag("cuota") }.pickerStyle(.segmented)
            if let a = proyeccion?.abono {
                FilaValor(etiqueta: "Terminaría", valor: Formato.fechaCorta(a.tabla.fechaFin) + (a.mesesMenos > 0 ? " (\(a.mesesMenos) meses antes)" : ""))
                if let c = a.cuotaNueva { FilaValor(etiqueta: "Cuota", valor: Formato.dinero(c)) }
                FilaValor(etiqueta: "Ahorro", valor: Formato.dinero(a.ahorro), color: Semantica.ingreso, negrita: true)
            }
        }
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<Prestamo> = try await API.shared.get("/prestamos/\(id)")
            p = r.data
        } catch { self.error = error.localizedDescription }
        if cajas.isEmpty {
            cajas = Dictionary(await cargarCajas(conTarjetas: false).map { ($0.valor, $0.nombre) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func proyectar() async {
        let r: Envoltura<Proyeccion>? = try? await API.shared.get("/prestamos/\(id)/proyeccion", [
            "extra_mensual": Formato.montoValido(extra) ? extra : nil, "abono": Formato.montoValido(abono) ? abono : nil, "modo": modo,
        ])
        if let r { proyeccion = r.data }
    }

    private func eliminar(_ pg: PrestamoPago) async {
        do {
            try await API.shared.borrar("/prestamo-pagos/\(pg.id)")
            aviso = "Pago eliminado."
            await cargar(); await proyectar()
        } catch { aviso = error.localizedDescription }
    }
}

/// Pago de un préstamo: los montos vienen de la sugerencia del sistema y se ajustan al recibo del banco.
struct FormularioPagoPrestamo: View {
    let prestamo: Prestamo
    let alGuardar: (Prestamo) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var fecha = Date()
    @State private var capital = ""
    @State private var interes = ""
    @State private var cargos = ""
    @State private var mora = ""
    @State private var origen = "efectivo"
    @State private var comentario = ""
    @State private var userId: Int?
    @State private var cajas: [(valor: String, nombre: String, saldo: String)] = []
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared
    private var total: Double { [capital, interes, cargos, mora].reduce(0) { $0 + num($1) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                    CampoMonto(etiqueta: "Capital", valor: $capital, error: errores["capital"])
                    CampoMonto(etiqueta: "Interés", valor: $interes, error: errores["interes"])
                    CampoMonto(etiqueta: "Seguros y cargos", valor: $cargos, error: errores["cargos"])
                    CampoMonto(etiqueta: "Mora", valor: $mora, error: errores["mora"])
                    FilaValor(etiqueta: "Total", valor: Formato.dinero(total), negrita: true)
                } footer: { Text("Los montos vienen de la sugerencia del sistema (interés = saldo × tasa × días / 365). Ajústalos al recibo del banco.") }
                Section {
                    Picker("¿De dónde salió?", selection: $origen) {
                        ForEach(cajas, id: \.valor) { Text("\($0.nombre) (\($0.saldo))").tag($0.valor) }
                        Text("Descuento de planilla").tag("planilla")
                        Text("Solo anotarlo").tag("ninguno")
                    }
                    ErrorCampo(texto: errores["origen"])
                    if origen == "planilla" {
                        Text("Si este préstamo se descuenta en un sueldo, lo normal es que se registre solo al registrar ese ingreso.").font(.caption).foregroundStyle(Semantica.aviso)
                    }
                    TextField("Comentario (opcional)", text: $comentario)
                    if comunes.miembros.count > 1 {
                        Picker("¿Quién lo pagó?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Registrar pago")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
            .task {
                let s = prestamo.sugerenciaPago
                capital = s?.capital ?? ""; interes = s?.interes ?? ""
                cargos = s?.cargos == "0.00" ? "" : s?.cargos ?? ""; mora = s?.mora == "0.00" ? "" : s?.mora ?? ""
                origen = prestamo.medioPago == "planilla" ? "planilla" : "efectivo"
                userId = prestamo.userId ?? comunes.usuario?.id
                cajas = await cargarCajas(conTarjetas: false)
            }
        }
    }

    private func guardar() async {
        let valido = { (t: String) in t.isEmpty || t.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil }
        var e: [String: String] = [:]
        if capital.isEmpty || !valido(capital) { e["capital"] = "Monto con máximo dos decimales (0 si no abona capital)." }
        if interes.isEmpty || !valido(interes) { e["interes"] = "Monto con máximo dos decimales (0 si no hay interés)." }
        if !valido(cargos) { e["cargos"] = "Máximo dos decimales." }
        if !valido(mora) { e["mora"] = "Máximo dos decimales." }
        if e.isEmpty && total <= 0 { e["capital"] = "El pago debe ser mayor que cero." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        let nota = comentario.trimmingCharacters(in: .whitespaces)
        do {
            let r: Envoltura<Prestamo> = try await API.shared.post("/prestamos/\(prestamo.id)/pagos", PrestamoPagoBody(
                fecha: Formato.textoLocal(fecha), capital: capital, interes: interes, cargos: cargos.isEmpty ? nil : cargos, mora: mora.isEmpty ? nil : mora,
                origen: origen, comentario: nota.isEmpty ? nil : nota, userId: userId))
            alGuardar(r.data)
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

/// Alta o edición de un préstamo (de un banco o de una persona).
struct FormularioPrestamo: View {
    let prestamo: Prestamo?
    let alGuardar: (String) -> Void
    var alEliminar: (() -> Void)? = nil

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var tipoId: Int?
    @State private var bancoId: Int?
    @State private var acreedor = ""
    @State private var contactoId: Int?
    @State private var montoOriginal = ""
    @State private var tasa = ""
    @State private var plazo = ""
    @State private var otorgado = Date()
    @State private var diaPago = ""
    @State private var cuota = ""
    @State private var saldoInicial = ""
    @State private var fechaSaldo = Date()
    @State private var medio = "transferencia"
    @State private var montoPlanilla = ""
    @State private var cargos: [CargoEditable] = []
    @State private var color = "#7C3AED"
    @State private var notas = ""
    @State private var activo = true
    @State private var crearCompromiso = true
    @State private var userId: Int?
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared
    private var tienePagos: Bool { !(prestamo?.pagos ?? []).isEmpty }

    struct CargoEditable: Identifiable { let id = UUID(); var nombre = ""; var monto = "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (ej: Préstamo de consumo, Carro)", text: $nombre); ErrorCampo(texto: errores["nombre"])
                    Picker("Tipo", selection: $tipoId) {
                        Text("Elegir…").tag(nil as Int?)
                        ForEach(comunes.catalogos?.tiposPrestamo ?? []) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    ErrorCampo(texto: errores["tipo_prestamo_id"])
                    Picker("Banco", selection: $bancoId) {
                        Text("No es de un banco").tag(nil as Int?)
                        ForEach(comunes.catalogos?.bancos ?? [], id: \.id) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    if bancoId == nil {
                        Picker("¿De quién? (contacto)", selection: $contactoId) {
                            Text("Nadie").tag(nil as Int?)
                            ForEach(comunes.contactos.filter { $0.activo || $0.id == contactoId }) { Text($0.nombreCompleto).tag($0.id as Int?) }
                        }
                    }
                    TextField("Acreedor (opcional)", text: $acreedor)
                }
                Section {
                    CampoMonto(etiqueta: "Monto original", valor: $montoOriginal, error: errores["monto_original"])
                    LabeledContent("Tasa anual %") { TextField("0", text: $tasa).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    ErrorCampo(texto: errores["tasa_anual"])
                    LabeledContent("Plazo (meses)") { TextField("Opcional", text: $plazo).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    ErrorCampo(texto: errores["plazo_meses"])
                    CampoDia(etiqueta: "Día de pago", valor: $diaPago, error: errores["dia_pago"])
                    DatePicker("Otorgado el", selection: $otorgado, in: ...Date(), displayedComponents: .date)
                    CampoMonto(etiqueta: "Cuota fija (capital + interés)", valor: $cuota, error: errores["cuota"])
                } footer: { Text("Cuota vacía = se calcula con la tasa y el plazo.") }
                Section {
                    CampoMonto(etiqueta: "Saldo", valor: $saldoInicial, error: errores["saldo_inicial"]).disabled(tienePagos)
                    DatePicker("A la fecha", selection: $fechaSaldo, in: ...Date(), displayedComponents: .date).disabled(tienePagos)
                } header: { Text("Punto de partida") } footer: { if tienePagos { Text("Ya tiene pagos: el saldo y su fecha ya no cambian.") } }
                Section {
                    Picker("¿Cómo se paga?", selection: $medio) {
                        Text("Desde una cuenta").tag("transferencia"); Text("En efectivo").tag("efectivo")
                        Text("Descuento de planilla").tag("planilla"); Text("Por definir").tag("por_definir")
                    }
                    CampoMonto(etiqueta: "Parte de planilla (opcional)", valor: $montoPlanilla, error: errores["monto_planilla"])
                } footer: { Text("La parte de planilla sirve si se paga mitad por planilla y mitad en ventanilla.") }
                Section("Cargos mensuales (seguros, IVA…)") {
                    ForEach($cargos) { $c in
                        HStack {
                            TextField("Nombre", text: $c.nombre)
                            CampoMonto(etiqueta: "Monto", valor: $c.monto).frame(width: 120)
                            Button { cargos.removeAll { $0.id == c.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.borderless).accessibilityLabel("Quitar cargo")
                        }
                    }
                    Button { cargos.append(CargoEditable()) } label: { Label("Agregar cargo", systemImage: "plus") }
                }
                Section {
                    if comunes.miembros.count > 1 {
                        Picker("Titular", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                    TextField("Notas (opcional)", text: $notas, axis: .vertical)
                    SelectorColor(color: $color)
                    if prestamo == nil {
                        Toggle("Crear el compromiso mensual", isOn: $crearCompromiso)
                    } else {
                        Toggle("Activo", isOn: $activo)
                    }
                } footer: { if prestamo == nil { Text("Aparece cada mes en Compromisos para no olvidar el pago.") } }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .barraFormulario(prestamo == nil ? "Nuevo préstamo" : "Editar préstamo", guardando: guardando, guardar: { await guardar() },
                             eliminar: accionEliminar, queSeElimina: "este préstamo")
            .task { await llenar() }
        }
    }

    private var accionEliminar: (() async -> Void)? {
        guard prestamo != nil else { return nil }
        return { await eliminar() }
    }

    private func llenar() async {
        await comunes.cargarCatalogos()
        userId = comunes.usuario?.id
        guard let p = prestamo else { tipoId = comunes.catalogos?.tiposPrestamo?.first?.id; return }
        let d = p.datos
        nombre = p.nombre; tipoId = p.tipoPrestamoId; bancoId = p.bancoId; acreedor = d?.acreedor ?? ""; contactoId = d?.contactoId
        montoOriginal = p.montoOriginal
        tasa = p.tasaAnual.flatMap(Double.init).map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? ""
        plazo = p.plazoMeses.map(String.init) ?? ""; otorgado = p.fechaOtorgamiento.map { Formato.fechaLocal($0) } ?? Date()
        diaPago = p.diaPago.map(String.init) ?? ""; cuota = d?.cuota ?? ""; saldoInicial = d?.saldoInicial ?? ""
        fechaSaldo = d?.fechaSaldo.map { Formato.fechaLocal($0) } ?? Date(); medio = p.medioPago ?? "por_definir"
        montoPlanilla = num(p.montoPlanilla) > 0 ? p.montoPlanilla ?? "" : ""
        cargos = p.cargos.map { CargoEditable(nombre: $0.nombre, monto: $0.monto ?? "") }
        color = p.color ?? color; notas = d?.notas ?? ""; activo = p.activo; crearCompromiso = false; userId = p.userId
    }

    private func guardar() async {
        let dinero = { (t: String) in t.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil }
        var e: [String: String] = [:]
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { e["nombre"] = "Escribe un nombre." }
        if tipoId == nil { e["tipo_prestamo_id"] = "Elige el tipo." }
        if !Formato.montoValido(montoOriginal) { e["monto_original"] = "Monto con máximo dos decimales." }
        if !(0...100).contains(Double(tasa) ?? -1) { e["tasa_anual"] = "Tasa anual entre 0 y 100 (0 si no cobra interés)." }
        if !dinero(saldoInicial) { e["saldo_inicial"] = "¿Cuánto se debe a la fecha indicada?" }
        if !plazo.isEmpty && !(1...600).contains(Int(plazo) ?? 0) { e["plazo_meses"] = "Entre 1 y 600 meses." }
        if !diaPago.isEmpty && CampoDia.valido(diaPago) == nil { e["dia_pago"] = "Día del 1 al 31." }
        if !cuota.isEmpty && !dinero(cuota) { e["cuota"] = "Máximo dos decimales." }
        if !montoPlanilla.isEmpty && !dinero(montoPlanilla) { e["monto_planilla"] = "Máximo dos decimales." }
        errores = e
        guard e.isEmpty, let tipoId else { return }
        guardando = true
        func opcional(_ t: String) -> String? { let v = t.trimmingCharacters(in: .whitespacesAndNewlines); return v.isEmpty ? nil : v }
        let cuerpo = PrestamoBody(
            nombre: nombre.trimmingCharacters(in: .whitespaces), tipoPrestamoId: tipoId, bancoId: bancoId, acreedor: opcional(acreedor),
            montoOriginal: montoOriginal, tasaAnual: tasa, plazoMeses: Int(plazo), fechaOtorgamiento: Formato.textoLocal(otorgado), diaPago: Int(diaPago),
            cuota: opcional(cuota), saldoInicial: saldoInicial, fechaSaldo: Formato.textoLocal(fechaSaldo), medioPago: medio, montoPlanilla: opcional(montoPlanilla),
            color: color, notas: opcional(notas), activo: activo,
            cargos: cargos.filter { !$0.nombre.trimmingCharacters(in: .whitespaces).isEmpty && dinero($0.monto) }.map { CargoPrestamo(nombre: $0.nombre.trimmingCharacters(in: .whitespaces), monto: $0.monto) },
            crearCompromiso: prestamo == nil ? crearCompromiso : nil, contactoId: bancoId == nil ? contactoId.map(String.init) : nil, userId: userId)
        do {
            if let p = prestamo { try await API.shared.enviar("PUT", "/prestamos/\(p.id)", cuerpo) } else { try await API.shared.enviar("POST", "/prestamos", cuerpo) }
            alGuardar(prestamo == nil ? "Préstamo creado." : "Préstamo actualizado.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let p = prestamo else { return }
        do {
            try await API.shared.borrar("/prestamos/\(p.id)")
            cerrar()
            alEliminar?()
        } catch { self.error = error.localizedDescription }
    }
}

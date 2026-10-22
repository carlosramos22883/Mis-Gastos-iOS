import SwiftUI

private func num(_ t: String?) -> Double { Double(t ?? "") ?? 0 }

func textoFrecuencia(_ f: FuenteIngreso) -> String {
    switch f.frecuencia {
    case "mensual": "Mensual" + (f.diaPago.map { " · día \($0)" } ?? "")
    case "quincenal": "Quincenal" + (f.diaPago.map { d in " · días \(d)" + (f.diaPago2.map { " y \($0)" } ?? "") } ?? "")
    case "semanal": "Semanal"
    case "eventual": "Eventual"
    default: f.frecuencia.prefix(1).uppercased() + f.frecuencia.dropFirst()
    }
}

/// Fuentes de ingreso (sueldos, servicios…).
struct IngresosView: View {
    @State private var fuentes: [FuenteIngreso] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var nueva = false
    @State private var aviso: String?
    private let comunes = Comunes.shared

    var body: some View {
        List {
            if cargando && fuentes.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, fuentes.isEmpty {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else if fuentes.isEmpty {
                Text("No hay fuentes de ingreso. Créala con el botón +.").foregroundStyle(.secondary)
            } else {
                ForEach(fuentes) { f in
                    NavigationLink(value: Ruta.ingreso(f.id)) {
                        HStack(spacing: 12) {
                            Circle().fill(Formato.color(f.color, Semantica.ingreso)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.nombre)
                                Text([f.tipo, textoFrecuencia(f), comunes.quien(f.userId)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if num(f.montoBruto) > 0 { Text(Formato.dinero(f.montoBruto)).fontWeight(.semibold) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ingresos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva fuente de ingreso") }
        }
        .task { await cargar() }
        .refreshable { await cargar() }
        .sheet(isPresented: $nueva) { FormularioFuente(fuente: nil) { aviso = $0; Task { await cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<[FuenteIngreso]> = try await API.shared.get("/ingresos")
            fuentes = r.data
        } catch { self.error = error.localizedDescription }
        cargando = false
    }
}

/// Una fuente: su plantilla de descuentos y los pagos recibidos; registrar un pago.
struct IngresoDetalleView: View {
    let id: Int
    @State private var f: FuenteIngreso?
    @State private var error: String?
    @State private var cajas: [String: String] = [:]
    @State private var registrar = false
    @State private var editar = false
    @State private var borrar: Recibo?
    @State private var aviso: String?
    @Environment(\.dismiss) private var salir

    var body: some View {
        ScrollView {
            if let f {
                VStack(spacing: 12) { contenido(f) }.padding(16)
            } else if let error {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else {
                ProgressView().padding(.top, 40)
            }
        }
        .background(Semantica.fondo)
        .navigationTitle(f?.nombre ?? "Ingreso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if f != nil { ToolbarItem(placement: .primaryAction) { Button("Editar") { editar = true } } } }
        .task { await cargar() }
        .refreshable { await cargar() }
        .sheet(isPresented: $registrar) {
            if let f { FormularioRecibo(fuente: f) { nueva, neto in self.f = nueva; aviso = "Pago registrado: entraron \(Formato.dinero(neto))." } }
        }
        .sheet(isPresented: $editar) {
            if let f { FormularioFuente(fuente: f) { aviso = $0; Task { await cargar() } } alEliminar: { salir() } }
        }
        .confirmationDialog("¿Eliminar este pago recibido?", isPresented: Binding(get: { borrar != nil }, set: { if !$0 { borrar = nil } }), titleVisibility: .visible, presenting: borrar) { r in
            Button("Eliminar", role: .destructive) { Task { await eliminar(r) } }
        } message: { r in Text("\(Formato.dinero(r.neto)) del \(Formato.fechaCorta(r.fecha)). Se revierte el ingreso y los pagos de préstamo que generó.") }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    @ViewBuilder
    private func contenido(_ f: FuenteIngreso) -> some View {
        let titulo = [f.tipo, f.pagador].compactMap { $0 }.joined(separator: " · ")
        Seccion(titulo.isEmpty ? "Fuente de ingreso" : titulo) {
            FilaValor(etiqueta: "Frecuencia", valor: textoFrecuencia(f))
            if num(f.montoBruto) > 0 { FilaValor(etiqueta: "Bruto habitual", valor: Formato.dinero(f.montoBruto)) }
            FilaValor(etiqueta: "Entra a", valor: nombreOrigen(f.destino, cajas))
            if !f.conceptos.isEmpty {
                Divider()
                ForEach(f.conceptos, id: \.nombre) { c in
                    FilaValor(etiqueta: (c.tipo == "descuento" ? "− " : "+ ") + c.nombre,
                              valor: num(c.monto) > 0 ? Formato.dinero(c.monto)
                                : c.porcentaje.map { "\($0) %" + (num(c.tope) > 0 ? " (máx. \(Formato.dinero(c.tope)))" : "") } ?? "Variable")
                }
            }
        }
        if f.activo {
            Button { registrar = true } label: { Text("Registrar pago recibido").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
        }
        Seccion("Pagos recibidos") {
            let recibos = f.recibos ?? []
            if recibos.isEmpty { Text("Aún no hay pagos registrados.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(recibos.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Divider() }
                Button { borrar = r } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(Formato.fechaCorta(r.fecha)) · \(nombreOrigen(r.destino, cajas))").font(.subheadline)
                            Spacer()
                            Text(Formato.dinero(r.neto)).fontWeight(.semibold).foregroundStyle(Semantica.ingreso)
                        }
                        Text("Bruto \(Formato.dinero(r.bruto))" + r.lineas.map { " · \($0.nombre) \(Formato.dinero($0.monto))" }.joined())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<FuenteIngreso> = try await API.shared.get("/ingresos/\(id)")
            f = r.data
        } catch { self.error = error.localizedDescription }
        if cajas.isEmpty {
            cajas = Dictionary(await cargarCajas(conTarjetas: false).map { ($0.valor, $0.nombre) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func eliminar(_ r: Recibo) async {
        do { try await API.shared.borrar("/recibos/\(r.id)"); aviso = "Pago eliminado."; await cargar() } catch { aviso = error.localizedDescription }
    }
}

/// Pago recibido: el servidor propone los descuentos de la plantilla para el bruto; se ajustan a la boleta.
struct FormularioRecibo: View {
    let fuente: FuenteIngreso
    let alGuardar: (FuenteIngreso, Double) -> Void

    struct Linea: Identifiable { let id = UUID(); let nombre: String; let tipo: String; var monto: String; let prestamoId: Int? }

    @Environment(\.dismiss) private var cerrar
    @State private var fecha = Date()
    @State private var bruto = ""
    @State private var lineas: [Linea] = []
    @State private var destino = "efectivo"
    @State private var comentario = ""
    @State private var cajas: [(valor: String, nombre: String, saldo: String)] = []
    @State private var calculando = false
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false

    private var neto: Double {
        num(bruto) - lineas.filter { $0.tipo == "descuento" }.reduce(0) { $0 + num($1.monto) } + lineas.filter { $0.tipo == "adicion" }.reduce(0) { $0 + num($1.monto) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                    CampoMonto(etiqueta: "Bruto", valor: $bruto, error: errores["bruto"])
                } footer: { Text("Los descuentos se calculan solos; ajústalos a tu boleta.") }
                if !lineas.isEmpty || calculando {
                    Section("Descuentos y adiciones") {
                        if calculando { ProgressView() }
                        ForEach(Array(lineas.enumerated()), id: \.element.id) { i, l in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text((l.tipo == "descuento" ? "− " : "+ ") + l.nombre).font(.subheadline)
                                    Spacer()
                                    CampoMonto(etiqueta: "0.00", valor: $lineas[i].monto).frame(width: 120)
                                }
                                if l.prestamoId != nil { Text("Se registra como pago del préstamo").font(.caption).foregroundStyle(.secondary) }
                                ErrorCampo(texto: errores["lineas.\(i).monto"])
                            }
                        }
                        .onDelete { lineas.remove(atOffsets: $0) }
                    }
                }
                Section {
                    FilaValor(etiqueta: "Neto que entra", valor: Formato.dinero(neto), color: neto < 0 ? Semantica.egreso : Semantica.ingreso, negrita: true)
                    Picker("¿A dónde entra?", selection: $destino) {
                        ForEach(cajas, id: \.valor) { Text("\($0.nombre) (\($0.saldo))").tag($0.valor) }
                        Text("Solo anotarlo").tag("ninguno")
                    }
                    ErrorCampo(texto: errores["destino"])
                    TextField("Comentario (opcional)", text: $comentario)
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Pago recibido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando || calculando) }
            }
            .task {
                bruto = num(fuente.montoBruto) > 0 ? fuente.montoBruto ?? "" : ""
                destino = fuente.destino ?? "efectivo"
                cajas = await cargarCajas(conTarjetas: false)
            }
            // El servidor recalcula la plantilla (ISSS, AFP, renta, préstamos…) cuando cambia el bruto
            .task(id: bruto) {
                calculando = true
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                if let r: Envoltura<Propuesta> = try? await API.shared.get("/ingresos/\(fuente.id)/propuesta", ["bruto": Formato.montoValido(bruto) ? bruto : nil]) {
                    lineas = r.data.lineas.map { Linea(nombre: $0.nombre, tipo: $0.tipo, monto: $0.monto > 0 ? String(format: "%.2f", $0.monto) : "", prestamoId: $0.prestamoId) }
                }
                calculando = false
            }
        }
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if !Formato.montoValido(bruto) { e["bruto"] = "Monto positivo con máximo dos decimales." } else if neto < 0 { e["bruto"] = "Los descuentos superan el bruto." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        let nota = comentario.trimmingCharacters(in: .whitespaces)
        let cuerpo = ReciboBody(fecha: Formato.textoLocal(fecha), bruto: bruto, destino: destino, comentario: nota.isEmpty ? nil : nota,
                                lineas: lineas.filter { num($0.monto) > 0 }.map { LineaReciboBody(nombre: $0.nombre, tipo: $0.tipo, monto: $0.monto, prestamoId: $0.prestamoId) },
                                userId: fuente.userId)
        do {
            let r: Envoltura<FuenteIngreso> = try await API.shared.post("/ingresos/\(fuente.id)/recibos", cuerpo)
            alGuardar(r.data, neto)
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

/// Alta o edición de una fuente de ingreso (la plantilla de descuentos se edita en la web).
struct FormularioFuente: View {
    let fuente: FuenteIngreso?
    let alGuardar: (String) -> Void
    var alEliminar: (() -> Void)? = nil

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var tipoId: Int?
    @State private var pagador = ""
    @State private var frecuencia = "mensual"
    @State private var diaPago = ""
    @State private var diaPago2 = ""
    @State private var bruto = ""
    @State private var destino = "efectivo"
    @State private var color = "#16A34A"
    @State private var activo = true
    @State private var userId: Int?
    @State private var cajas: [(valor: String, nombre: String, saldo: String)] = []
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (ej: Sueldo Stefany)", text: $nombre); ErrorCampo(texto: errores["nombre"])
                    Picker("Tipo", selection: $tipoId) {
                        Text("Elegir…").tag(nil as Int?)
                        ForEach(comunes.catalogos?.tiposIngreso ?? []) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    ErrorCampo(texto: errores["tipo_ingreso_id"])
                    TextField("¿Quién paga? (opcional)", text: $pagador)
                }
                Section {
                    Picker("Frecuencia", selection: $frecuencia) { Text("Mensual").tag("mensual"); Text("Quincenal").tag("quincenal") }
                    CampoDia(etiqueta: frecuencia == "quincenal" ? "Primer día" : "Día de pago", valor: $diaPago, error: errores["dia_pago"])
                    if frecuencia == "quincenal" { CampoDia(etiqueta: "Segundo día", valor: $diaPago2, error: errores["dia_pago_2"]) }
                    CampoMonto(etiqueta: "Bruto habitual (opcional)", valor: $bruto, error: errores["monto_bruto"])
                    Picker("¿A dónde entra?", selection: $destino) { ForEach(cajas, id: \.valor) { Text($0.nombre).tag($0.valor) } }
                    if comunes.miembros.count > 1 {
                        Picker("¿De quién es?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                }
                Section {
                    SelectorColor(color: $color)
                    if fuente != nil { Toggle("Activa", isOn: $activo) }
                } footer: { Text("Los descuentos de planilla (ISSS, AFP, renta, préstamos) se configuran en la web.") }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .barraFormulario(fuente == nil ? "Nueva fuente de ingreso" : "Editar fuente", guardando: guardando, guardar: { await guardar() },
                             eliminar: accionEliminar, queSeElimina: "esta fuente")
            .task { await llenar() }
        }
    }

    private var accionEliminar: (() async -> Void)? {
        guard fuente != nil else { return nil }
        return { await eliminar() }
    }

    private func llenar() async {
        await comunes.cargarCatalogos()
        cajas = await cargarCajas(conTarjetas: false)
        userId = comunes.usuario?.id
        guard let s = fuente else { tipoId = comunes.catalogos?.tiposIngreso?.first?.id; return }
        nombre = s.nombre; tipoId = s.tipoIngresoId; pagador = s.pagador ?? ""; frecuencia = s.frecuencia
        diaPago = s.diaPago.map(String.init) ?? ""; diaPago2 = s.diaPago2.map(String.init) ?? ""
        bruto = num(s.montoBruto) > 0 ? s.montoBruto ?? "" : ""; destino = s.destino ?? "efectivo"; color = s.color ?? color; activo = s.activo; userId = s.userId
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { e["nombre"] = "Escribe un nombre." }
        if tipoId == nil { e["tipo_ingreso_id"] = "Elige el tipo." }
        if !diaPago.isEmpty && CampoDia.valido(diaPago) == nil { e["dia_pago"] = "Día del 1 al 31." }
        if frecuencia == "quincenal" && CampoDia.valido(diaPago2) == nil { e["dia_pago_2"] = "Día del 1 al 31." }
        if !bruto.isEmpty && bruto.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) == nil { e["monto_bruto"] = "Máximo dos decimales." }
        errores = e
        guard e.isEmpty, let tipoId else { return }
        guardando = true
        let p = pagador.trimmingCharacters(in: .whitespaces)
        let cuerpo = FuenteBody(nombre: nombre.trimmingCharacters(in: .whitespaces), tipoIngresoId: tipoId, pagador: p.isEmpty ? nil : p, frecuencia: frecuencia,
                                diaPago: Int(diaPago), diaPago2: frecuencia == "quincenal" ? Int(diaPago2) : nil, montoBruto: bruto.isEmpty ? nil : bruto,
                                destino: destino, color: color, activo: activo, userId: userId)
        do {
            if let s = fuente { try await API.shared.enviar("PUT", "/ingresos/\(s.id)", cuerpo) } else { try await API.shared.enviar("POST", "/ingresos", cuerpo) }
            alGuardar(fuente == nil ? "Fuente creada." : "Fuente actualizada.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let s = fuente else { return }
        do {
            try await API.shared.borrar("/ingresos/\(s.id)")
            cerrar()
            alEliminar?()
        } catch { self.error = error.localizedDescription }
    }
}

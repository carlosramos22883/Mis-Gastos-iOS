import SwiftUI

/// Nuevo compromiso (una vez o recurrente), editar un pago o editar la regla de su serie.
struct FormularioCompromiso: View {
    enum Modo { case nuevo, pago(Compromiso), serie(Compromiso) }

    let modo: Modo
    let alGuardar: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var descripcion = ""
    @State private var monto = ""
    @State private var medio = "por_definir"
    @State private var categoriaId: Int?
    @State private var contactoId: Int?
    @State private var userId: Int?
    @State private var comentario = ""
    @State private var recurrente = false
    @State private var fechaEsperada = Date()
    @State private var frecuencia = "mensual"
    @State private var diaSemana = 1
    @State private var diaPago = String(Calendar.current.component(.day, from: Date()))
    @State private var diaPago2 = ""
    @State private var fechaInicio = Date()
    @State private var finalizacion = "indefinido"
    @State private var fechaFin = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var totalCuotas = ""
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    private var compromiso: Compromiso? {
        switch modo { case .nuevo: nil; case .pago(let c), .serie(let c): c }
    }
    private var esSerie: Bool { if case .serie = modo { true } else { false } }
    private var titulo: String { compromiso == nil ? "Nuevo compromiso" : esSerie ? "Editar la serie" : "Editar pago" }

    var body: some View {
        NavigationStack {
            Form {
                if compromiso == nil {
                    Picker("Tipo", selection: $recurrente) { Text("Una sola vez").tag(false); Text("Se repite").tag(true) }.pickerStyle(.segmented)
                }
                Section {
                    TextField("¿Qué hay que pagar? (ej: Internet, colegio)", text: $descripcion); ErrorCampo(texto: errores["descripcion"])
                    CampoMonto(etiqueta: recurrente ? "Monto de cada pago" : "Monto", valor: $monto, error: errores["monto"])
                } footer: {
                    if esSerie { Text("Cambia la regla que se repite. Se aplica a los pagos de hoy en adelante que aún no tienen abonos; los pagados o abonados no cambian.") }
                }
                if recurrente { reglas } else {
                    Section { DatePicker("Fecha esperada", selection: $fechaEsperada, displayedComponents: .date); ErrorCampo(texto: errores["fecha_esperada"]) }
                }
                Section {
                    Picker("¿Cómo se paga?", selection: $medio) {
                        Text("Por definir").tag("por_definir"); Text("Efectivo").tag("efectivo"); Text("Transferencia").tag("transferencia"); Text("Tarjeta").tag("tarjeta")
                    }
                    Picker("Categoría", selection: $categoriaId) {
                        Text("Se elige al pagar").tag(nil as Int?)
                        ForEach(comunes.categoriasDe("egreso")) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    Picker("¿A quién?", selection: $contactoId) {
                        Text("Nadie").tag(nil as Int?)
                        ForEach(comunes.contactos.filter { $0.activo || $0.id == contactoId }) { Text($0.nombreCompleto).tag($0.id as Int?) }
                    }
                    if comunes.miembros.count > 1 {
                        Picker("¿Quién lo registra?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                    TextField("Comentario (opcional)", text: $comentario, axis: .vertical)
                } footer: {
                    if compromiso != nil && !esSerie { Text("Solo cambia este pago; los demás de la serie siguen igual.") }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
            .onAppear(perform: llenar)
        }
    }

    @ViewBuilder
    private var reglas: some View {
        Section {
            Picker("Frecuencia", selection: $frecuencia) { Text("Mensual").tag("mensual"); Text("Quincenal").tag("quincenal"); Text("Semanal").tag("semanal") }
            if frecuencia == "semanal" {
                Picker("Día de la semana", selection: $diaSemana) {
                    ForEach([(1, "Lunes"), (2, "Martes"), (3, "Miércoles"), (4, "Jueves"), (5, "Viernes"), (6, "Sábado"), (0, "Domingo")], id: \.0) { Text($0.1).tag($0.0) }
                }
            } else {
                CampoDia(etiqueta: frecuencia == "quincenal" ? "Primer día" : "Día de pago", valor: $diaPago, error: errores["dia_pago"])
                if frecuencia == "quincenal" { CampoDia(etiqueta: "Segundo día", valor: $diaPago2, error: errores["dia_pago_2"]) }
            }
            if !esSerie { DatePicker("Desde", selection: $fechaInicio, displayedComponents: .date) }
            Picker("¿Hasta cuándo?", selection: $finalizacion) {
                Text("Sin fecha de fin").tag("indefinido"); Text("Hasta una fecha").tag("fecha"); Text("Un número de pagos").tag("cuotas")
            }
            if finalizacion == "fecha" {
                DatePicker("Hasta", selection: $fechaFin, in: fechaInicio..., displayedComponents: .date)
                ErrorCampo(texto: errores["fecha_fin"])
            } else if finalizacion == "cuotas" {
                LabeledContent("Número de pagos") { TextField("12", text: $totalCuotas).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                ErrorCampo(texto: errores["total_cuotas"])
            }
        } footer: { if frecuencia != "semanal" { Text("31 = último día de cada mes.") } }
    }

    private func llenar() {
        userId = comunes.usuario?.id
        switch modo {
        case .nuevo: break
        case .pago(let c):
            descripcion = c.descripcion; monto = c.monto; medio = c.medioPago ?? "por_definir"; categoriaId = c.categoria?.id
            contactoId = c.contacto?.id; userId = c.userId; comentario = c.comentario ?? ""
            fechaEsperada = c.fechaEsperada.map { Formato.fechaLocal($0) } ?? Date()
        case .serie(let c):
            let r = c.recurrente
            recurrente = true
            descripcion = r?.descripcion ?? c.descripcion; monto = r?.monto ?? c.monto; medio = r?.medioPago ?? "por_definir"
            categoriaId = r?.categoriaPersonalId; contactoId = c.contacto?.id; userId = c.userId; comentario = c.comentario ?? ""
            frecuencia = r?.frecuencia ?? "mensual"; diaSemana = r?.diaSemana ?? 1
            diaPago = r?.diaPago.map(String.init) ?? ""; diaPago2 = r?.diaPago2.map(String.init) ?? ""
            fechaInicio = r?.fechaInicio.map { Formato.fechaLocal($0) } ?? Date()
            finalizacion = r?.fechaFin != nil ? "fecha" : r?.totalCuotas != nil ? "cuotas" : "indefinido"
            if let f = r?.fechaFin { fechaFin = Formato.fechaLocal(f) }
            totalCuotas = r?.totalCuotas.map(String.init) ?? ""
        }
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if descripcion.trimmingCharacters(in: .whitespaces).isEmpty { e["descripcion"] = "Escribe qué hay que pagar." }
        if !Formato.montoValido(monto) { e["monto"] = "Monto positivo con máximo dos decimales." }
        if recurrente {
            if frecuencia != "semanal" && CampoDia.valido(diaPago) == nil { e["dia_pago"] = "Día del 1 al 31 (31 = último día del mes)." }
            if frecuencia == "quincenal" && (CampoDia.valido(diaPago2) == nil || diaPago2 == diaPago) { e["dia_pago_2"] = "Otro día del 1 al 31." }
            if finalizacion == "cuotas" && !(1...600).contains(Int(totalCuotas) ?? 0) { e["total_cuotas"] = "Entre 1 y 600." }
            if finalizacion == "fecha" && Formato.textoLocal(fechaFin) < Formato.textoLocal(fechaInicio) { e["fecha_fin"] = "Debe ser después del inicio." }
        }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        let nota = comentario.trimmingCharacters(in: .whitespacesAndNewlines)
        var cuerpo = CompromisoBody(descripcion: descripcion.trimmingCharacters(in: .whitespaces), monto: monto, medioPago: medio, categoriaPersonalId: categoriaId,
                                    comentario: nota.isEmpty ? nil : nota, contactoId: contactoId.map(String.init), userId: userId,
                                    recurrenciaTipo: compromiso != nil ? nil : recurrente ? "recurrente" : "unica",
                                    fechaEsperada: recurrente ? nil : Formato.textoLocal(fechaEsperada))
        if recurrente {
            cuerpo.frecuencia = frecuencia
            cuerpo.diaSemana = frecuencia == "semanal" ? diaSemana : nil
            cuerpo.diaPago = frecuencia != "semanal" ? Int(diaPago) : nil
            cuerpo.diaPago2 = frecuencia == "quincenal" ? Int(diaPago2) : nil
            cuerpo.fechaInicio = esSerie ? nil : Formato.textoLocal(fechaInicio)
            cuerpo.finalizacion = finalizacion
            cuerpo.fechaFin = finalizacion == "fecha" ? Formato.textoLocal(fechaFin) : nil
            cuerpo.totalCuotas = finalizacion == "cuotas" ? Int(totalCuotas) : nil
        }
        do {
            switch modo {
            case .nuevo: try await API.shared.enviar("POST", "/compromisos", cuerpo)
            case .pago(let c): try await API.shared.enviar("PUT", "/compromisos/\(c.id)", cuerpo)
            case .serie(let c): try await API.shared.enviar("PUT", "/compromisos/\(c.id)/serie", cuerpo)
            }
            alGuardar(compromiso == nil ? "Compromiso creado." : esSerie ? "Serie actualizada." : "Pago actualizado.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

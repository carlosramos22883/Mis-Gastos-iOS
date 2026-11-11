import SwiftUI

/// Colores para cuentas, tarjetas, préstamos y categorías (los mismos de la web y Android).
let paletaColores = [
    "#0369A1", "#0284C7", "#1155CC", "#4A86E8", "#7C3AED", "#C026D3", "#FF00FF", "#DB2777", "#DC2626", "#EA580C",
    "#F1C232", "#FFD966", "#16A34A", "#00A651", "#B6D7A8", "#0891B2", "#434343", "#999999", "#1E293B", "#92400E",
]

struct SelectorColor: View {
    @Binding var color: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(paletaColores, id: \.self) { hex in
                    let elegido = hex.caseInsensitiveCompare(color) == .orderedSame
                    Circle().fill(Formato.color(hex)).frame(width: 34, height: 34)
                        .overlay { if elegido { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Formato.textoSobre(hex)) } }
                        .overlay(Circle().stroke(Color.primary, lineWidth: elegido ? 2 : 0).padding(-3))
                        .onTapGesture { color = hex }
                        .accessibilityLabel(elegido ? "Color elegido" : "Elegir color")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Campo de día del mes (1–31).
struct CampoDia: View {
    let etiqueta: String
    @Binding var valor: String
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(etiqueta) {
                TextField("1–31", text: $valor).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .onChange(of: valor) { _, nuevo in
                        let limpio = String(nuevo.filter(\.isNumber).prefix(2))
                        if limpio != nuevo { valor = limpio }
                    }
            }
            ErrorCampo(texto: error)
        }
    }

    static func valido(_ t: String) -> Int? { Int(t).flatMap { (1...31).contains($0) ? $0 : nil } }
}

/// Barra común de los formularios de alta: Cancelar, Guardar y, al editar, Eliminar con confirmación.
struct BarraFormulario: ViewModifier {
    let titulo: String
    let guardando: Bool
    let guardar: () async -> Void
    var eliminar: (() async -> Void)?
    var queSeElimina = "este registro"
    @Environment(\.dismiss) private var cerrar
    @State private var confirmar = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
                if eliminar != nil {
                    ToolbarItem(placement: .bottomBar) { Button("Eliminar", role: .destructive) { confirmar = true }.tint(.red) }
                }
            }
            // El botón Eliminar flota abajo: que no tape el final del formulario
            .contentMargins(.bottom, eliminar == nil ? 0 : 72, for: .scrollContent)
            .confirmationDialog("¿Eliminar \(queSeElimina)?", isPresented: $confirmar, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) { Task { await eliminar?() } }
            } message: { Text("Solo se puede si no tiene historial; si lo tiene, desactívalo.") }
    }
}

extension View {
    func barraFormulario(_ titulo: String, guardando: Bool, guardar: @escaping () async -> Void, eliminar: (() async -> Void)? = nil, queSeElimina: String = "este registro") -> some View {
        modifier(BarraFormulario(titulo: titulo, guardando: guardando, guardar: guardar, eliminar: eliminar, queSeElimina: queSeElimina))
    }
}

// MARK: - Cuenta

struct FormularioCuenta: View {
    let cuenta: Cuenta?
    let alGuardar: (String) -> Void
    var alEliminar: (() -> Void)? = nil

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var tipoId: Int?
    @State private var bancoId: Int?
    @State private var color = "#0369A1"
    @State private var saldoInicial = ""
    @State private var fechaInicial = Date()
    @State private var activo = true
    @State private var userId: Int?
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (ej: Agrícola Stefany, Chivo)", text: $nombre); ErrorCampo(texto: errores["nombre"])
                    Picker("Tipo", selection: $tipoId) {
                        Text("Elegir…").tag(nil as Int?)
                        ForEach(comunes.catalogos?.tiposCuenta ?? []) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    ErrorCampo(texto: errores["tipo_cuenta_id"])
                    Picker("Banco o emisor", selection: $bancoId) {
                        Text("Ninguno").tag(nil as Int?)
                        ForEach(comunes.catalogos?.bancos ?? [], id: \.id) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    if comunes.miembros.count > 1 {
                        Picker("Titular", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                }
                if cuenta == nil {
                    Section {
                        CampoMonto(etiqueta: "Saldo inicial", valor: $saldoInicial, error: errores["saldo_inicial"])
                        DatePicker("¿Desde cuándo?", selection: $fechaInicial, in: ...Date(), displayedComponents: .date)
                    } footer: { Text("El saldo y la fecha inicial solo se fijan al crearla.") }
                }
                Section {
                    SelectorColor(color: $color)
                    if cuenta != nil {
                        Toggle("Activa", isOn: $activo)
                    }
                } footer: { if cuenta != nil { Text("Una cuenta inactiva no recibe movimientos nuevos.") } }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .barraFormulario(cuenta == nil ? "Nueva cuenta" : "Editar cuenta", guardando: guardando, guardar: { await guardar() },
                             eliminar: accionEliminar, queSeElimina: "esta cuenta")
            .task { await llenar() }
        }
    }

    private var accionEliminar: (() async -> Void)? {
        guard cuenta != nil else { return nil }
        return { await eliminar() }
    }

    private func llenar() async {
        await comunes.cargarCatalogos()
        userId = comunes.usuario?.id
        guard let c = cuenta else { tipoId = comunes.catalogos?.tiposCuenta?.first?.id; return }
        nombre = c.nombre; tipoId = c.tipoCuenta?.id; bancoId = c.banco?.id; color = c.color ?? color; activo = c.activo; userId = c.userId
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { e["nombre"] = "Escribe el nombre." }
        if tipoId == nil { e["tipo_cuenta_id"] = "Elige el tipo." }
        if cuenta == nil && saldoInicial.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) == nil { e["saldo_inicial"] = "Saldo con máximo dos decimales (0 si está vacía)." }
        errores = e
        guard e.isEmpty, let tipoId else { return }
        guardando = true
        let cuerpo = CuentaBody(nombre: nombre.trimmingCharacters(in: .whitespaces), tipoCuentaId: tipoId, bancoId: bancoId, color: color,
                                saldoInicial: cuenta == nil ? saldoInicial : nil, fechaInicial: cuenta == nil ? Formato.textoLocal(fechaInicial) : nil,
                                activo: activo, userId: userId)
        do {
            if let c = cuenta { try await API.shared.enviar("PUT", "/cuentas/\(c.id)", cuerpo) } else { try await API.shared.enviar("POST", "/cuentas", cuerpo) }
            alGuardar(cuenta == nil ? "Cuenta creada." : "Cuenta actualizada.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let c = cuenta else { return }
        do {
            try await API.shared.borrar("/cuentas/\(c.id)")
            cerrar()
            alEliminar?()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Tarjeta

struct FormularioTarjeta: View {
    let tarjeta: Tarjeta?
    let alGuardar: (String) -> Void
    var alEliminar: (() -> Void)? = nil

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var bancoId: Int?
    @State private var marcaId: Int?
    @State private var digitos = ""
    @State private var color = "#1155CC"
    @State private var limite = ""
    @State private var tasa = ""
    @State private var diaCorte = ""
    @State private var diaPago = ""
    @State private var activo = true
    @State private var avances = true
    @State private var cargosRestan = true
    @State private var disponible = ""
    @State private var tienePendiente = false
    @State private var pendienteMonto = ""
    @State private var pendienteFecha = Date()
    @State private var userId: Int?
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (ej: Bac Walmart Stef)", text: $nombre); ErrorCampo(texto: errores["nombre"])
                    Picker("Banco o tienda", selection: $bancoId) {
                        Text("Ninguno").tag(nil as Int?)
                        ForEach(comunes.catalogos?.bancos ?? [], id: \.id) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    Picker("Red", selection: $marcaId) {
                        Text("Ninguna").tag(nil as Int?)
                        ForEach(comunes.catalogos?.marcasRed ?? [], id: \.id) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    LabeledContent("Últimos 4 dígitos") {
                        TextField("1234", text: $digitos).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .onChange(of: digitos) { _, n in let l = String(n.filter(\.isNumber).prefix(4)); if l != n { digitos = l } }
                    }
                    ErrorCampo(texto: errores["ultimos_digitos"])
                    if comunes.miembros.count > 1 {
                        Picker("Titular", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                }
                Section {
                    CampoMonto(etiqueta: "Límite de crédito", valor: $limite, error: errores["limite_credito"])
                    CampoDia(etiqueta: "Día de corte", valor: $diaCorte, error: errores["dia_corte"])
                    CampoDia(etiqueta: "Día de pago", valor: $diaPago, error: errores["dia_pago"])
                    LabeledContent("Tasa anual % (opcional)") {
                        TextField("0", text: $tasa).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    ErrorCampo(texto: errores["tasa_interes"])
                } footer: { Text("La tasa sirve para calcular lo que cuesta no pagar completo.") }
                if tarjeta == nil {
                    Section {
                        CampoMonto(etiqueta: "Disponible hoy", valor: $disponible, error: errores["disponible"])
                        Toggle("Tiene un estado de cuenta por pagar", isOn: $tienePendiente)
                        if tienePendiente {
                            CampoMonto(etiqueta: "Monto a pagar", valor: $pendienteMonto, error: errores["pendiente_monto"])
                            DatePicker("Fecha límite", selection: $pendienteFecha, displayedComponents: .date)
                        }
                    } footer: { Text("La deuda inicial = límite − disponible.") }
                }
                Section {
                    SelectorColor(color: $color)
                    Toggle("Permite avances de efectivo", isOn: $avances)
                    Toggle("Los cargos del banco restan del disponible", isOn: $cargosRestan)
                    if tarjeta != nil { Toggle("Activa", isOn: $activo) }
                } footer: { Text("Apaga «los cargos del banco» si el banco solo resta el capital (Davivienda): intereses, comisiones e IVA bajan el disponible al pagarlos.") }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .barraFormulario(tarjeta == nil ? "Nueva tarjeta" : "Editar tarjeta", guardando: guardando, guardar: { await guardar() },
                             eliminar: accionEliminar, queSeElimina: "esta tarjeta")
            .task { await llenar() }
        }
    }

    private var accionEliminar: (() async -> Void)? {
        guard tarjeta != nil else { return nil }
        return { await eliminar() }
    }

    private func llenar() async {
        await comunes.cargarCatalogos()
        userId = comunes.usuario?.id
        guard let t = tarjeta else { return }
        nombre = t.nombre; bancoId = t.banco?.id; marcaId = t.marca?.id; digitos = t.ultimosDigitos ?? ""; color = t.color ?? color
        limite = t.limiteCredito; tasa = t.tasaInteres ?? ""; diaCorte = "\(t.diaCorte)"; diaPago = "\(t.diaPago)"
        activo = t.activo; avances = t.permiteAvances; cargosRestan = t.cargosRestanDisponible ?? true; userId = t.userId
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { e["nombre"] = "Escribe el nombre." }
        if !Formato.montoValido(limite) { e["limite_credito"] = "Límite positivo con máximo dos decimales." }
        if CampoDia.valido(diaCorte) == nil { e["dia_corte"] = "Día del 1 al 31." }
        if CampoDia.valido(diaPago) == nil { e["dia_pago"] = "Día del 1 al 31." }
        if !digitos.isEmpty && digitos.count != 4 { e["ultimos_digitos"] = "Cuatro dígitos." }
        if tarjeta == nil {
            if disponible.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) == nil { e["disponible"] = "¿Cuánto tiene disponible hoy?" }
            else if (Double(disponible) ?? 0) > (Double(limite) ?? 0) { e["disponible"] = "No puede ser mayor que el límite." }
            if tienePendiente && !Formato.montoValido(pendienteMonto) { e["pendiente_monto"] = "Monto del estado de cuenta." }
        }
        errores = e
        guard e.isEmpty, let corte = CampoDia.valido(diaCorte), let pago = CampoDia.valido(diaPago) else { return }
        guardando = true
        let nueva = tarjeta == nil
        let cuerpo = TarjetaBody(nombre: nombre.trimmingCharacters(in: .whitespaces), bancoId: bancoId, marcaRedId: marcaId, ultimosDigitos: digitos.isEmpty ? nil : digitos,
                                 color: color, limiteCredito: limite, tasaInteres: tasa.isEmpty ? nil : tasa, diaCorte: corte, diaPago: pago, activo: activo,
                                 permiteAvances: avances, cargosRestanDisponible: cargosRestan, disponible: nueva ? disponible : nil, tienePendiente: nueva ? tienePendiente : nil,
                                 pendienteMonto: nueva && tienePendiente ? pendienteMonto : nil,
                                 pendienteFecha: nueva && tienePendiente ? Formato.textoLocal(pendienteFecha) : nil, userId: userId)
        do {
            if let t = tarjeta { try await API.shared.enviar("PUT", "/tarjetas/\(t.id)", cuerpo) } else { try await API.shared.enviar("POST", "/tarjetas", cuerpo) }
            alGuardar(nueva ? "Tarjeta creada." : "Tarjeta actualizada.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let t = tarjeta else { return }
        do {
            try await API.shared.borrar("/tarjetas/\(t.id)")
            cerrar()
            alEliminar?()
        } catch { self.error = error.localizedDescription }
    }
}

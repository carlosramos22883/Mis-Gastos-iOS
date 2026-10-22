import PhotosUI
import SwiftUI

/// "efectivo", "planilla", "cuenta:42"… → nombre legible (cajas: nombres de efectivo, cuentas y tarjetas).
func nombreOrigen(_ valor: String?, _ cajas: [String: String] = [:]) -> String {
    switch valor {
    case nil: ""
    case "efectivo": "Efectivo"
    case "planilla": "Descuento de planilla"
    case "ninguno": "Solo anotado"
    case "transferencia": "Transferencia"
    case let v?: cajas[v] ?? (v.split(separator: ":").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? v)
    }
}

/// Efectivo y cuentas con su saldo (y, si se piden, tarjetas activas con su disponible): para elegir de dónde sale o a dónde entra el dinero.
func cargarCajas(conTarjetas: Bool) async -> [(valor: String, nombre: String, saldo: String)] {
    var lista: [(String, String, String)] = []
    if let r: Envoltura<OpcionesTransferencia> = try? await API.shared.get("/transferencias/opciones") {
        lista = r.data.destinos.map { ($0.valor, $0.nombre, Formato.dinero($0.saldo)) }
    }
    if conTarjetas, let t: Envoltura<[Tarjeta]> = try? await API.shared.get("/tarjetas") {
        lista += t.data.filter(\.activo).map { ("tarjeta:\($0.id)", "Tarjeta \($0.nombre)", "disponible " + Formato.dinero($0.disponible)) }
    }
    return lista
}

/// Contactos con lo que nos deben; buscar y filtrar.
struct ContactosView: View {
    var soloDeben = false
    @State private var contactos: [Contacto] = []
    @State private var filtroDeben = false
    @State private var busqueda = ""
    @State private var cargando = true
    @State private var error: String?
    @State private var nuevo = false
    @State private var aviso: String?
    @State private var iniciado = false

    var body: some View {
        let lista = contactos.filter { busqueda.isEmpty || $0.nombreCompleto.localizedCaseInsensitiveContains(busqueda.trimmingCharacters(in: .whitespaces)) }
        let total = contactos.reduce(0) { $0 + (Double($1.pendiente ?? "") ?? 0) }
        List {
            Section {
                Picker("Mostrar", selection: $filtroDeben) { Text("Todos").tag(false); Text("Nos deben").tag(true) }.pickerStyle(.segmented)
                if total > 0 { FilaValor(etiqueta: "Nos deben", valor: Formato.dinero(total), color: Semantica.ingreso, negrita: true) }
            }
            if cargando && contactos.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, contactos.isEmpty {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else if lista.isEmpty {
                Text(filtroDeben ? "Nadie les debe. 🎉" : "No hay contactos con ese nombre.").foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(lista) { c in NavigationLink(value: Ruta.contacto(c.id)) { fila(c) } }
                }
            }
        }
        .searchable(text: $busqueda, prompt: "Buscar por nombre")
        .navigationTitle("Contactos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { nuevo = true } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Nuevo contacto") }
        }
        .task {
            if !iniciado { filtroDeben = soloDeben; iniciado = true }
            await cargar()
        }
        .onChange(of: filtroDeben) { _, _ in contactos = []; cargando = true; Task { await cargar() } }
        .refreshable { await cargar() }
        .sheet(isPresented: $nuevo) { FormularioContacto(contacto: nil) { aviso = $0; Task { await cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func fila(_ c: Contacto) -> some View {
        let pendiente = Double(c.pendiente ?? "") ?? 0
        return HStack(spacing: 12) {
            Avatar(url: c.fotoUrl, nombre: c.nombreCompleto, tamano: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.nombreCompleto)
                HStack(spacing: 6) {
                    if let t = c.tipo { Text(t).font(.caption).foregroundStyle(.secondary) }
                    if !c.activo { Insignia(texto: "Inactivo", color: .secondary) }
                }
            }
            Spacer()
            if pendiente > 0 {
                VStack(alignment: .trailing) {
                    Text("Debe").font(.caption2).foregroundStyle(.secondary)
                    Text(Formato.dinero(pendiente)).fontWeight(.semibold).foregroundStyle(Semantica.ingreso)
                }
            }
        }
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<[Contacto]> = try await API.shared.get("/contactos", ["filtro": filtroDeben ? "deben" : nil])
            contactos = r.data
        } catch { self.error = error.localizedDescription }
        cargando = false
    }
}

/// Ficha de un contacto: foto (tocarla para cambiarla), lo que debe, sus deudas con pagos; prestar o registrar un pago.
struct ContactoDetalleView: View {
    let id: Int
    @State private var c: Contacto?
    @State private var error: String?
    @State private var cajas: [String: String] = [:]
    @State private var formDeuda: Bool?
    @State private var editar = false
    @State private var borrarDeuda: Deuda?
    @State private var borrarPago: DeudaPago?
    @State private var foto: PhotosPickerItem?
    @State private var subiendo = false
    @State private var aviso: String?
    private let comunes = Comunes.shared

    var body: some View {
        ScrollView {
            if let c {
                VStack(alignment: .leading, spacing: 12) { contenido(c) }.padding(16)
            } else if let error {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else {
                ProgressView().padding(.top, 40)
            }
        }
        .background(Semantica.fondo)
        .navigationTitle(c?.nombreCompleto ?? "Contacto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if c != nil { ToolbarItem(placement: .primaryAction) { Button("Editar") { editar = true } } }
        }
        .task { await cargar() }
        .refreshable { await cargar() }
        .onChange(of: foto) { _, item in if let item { Task { await subirFoto(item) } } }
        .sheet(isPresented: $editar) { if let c { FormularioContacto(contacto: c) { aviso = $0; Task { await cargar() } } } }
        .sheet(isPresented: Binding(get: { formDeuda != nil }, set: { if !$0 { formDeuda = nil } })) {
            if let c, let pago = formDeuda {
                FormularioDeuda(contacto: c, pago: pago) { nuevo in self.c = nuevo; aviso = pago ? "Pago registrado." : "Deuda registrada." }
            }
        }
        .confirmationDialog("¿Eliminar esta deuda?", isPresented: Binding(get: { borrarDeuda != nil }, set: { if !$0 { borrarDeuda = nil } }), titleVisibility: .visible, presenting: borrarDeuda) { d in
            Button("Eliminar", role: .destructive) { Task { await eliminar("/deudas/\(d.id)", "Deuda eliminada.") } }
        } message: { d in Text("\(d.descripcion) · \(Formato.dinero(d.monto)). Si salió dinero, se revierte ese gasto.") }
        .confirmationDialog("¿Eliminar este pago?", isPresented: Binding(get: { borrarPago != nil }, set: { if !$0 { borrarPago = nil } }), titleVisibility: .visible, presenting: borrarPago) { p in
            Button("Eliminar", role: .destructive) { Task { await eliminar("/deuda-pagos/\(p.id)", "Pago eliminado.") } }
        } message: { p in Text("\(Formato.dinero(p.monto)) del \(Formato.fechaCorta(p.fecha)). Si entró dinero, se revierte ese ingreso.") }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    @ViewBuilder
    private func contenido(_ c: Contacto) -> some View {
        HStack(spacing: 14) {
            // Tocar la foto para cambiarla (se recorta en cuadrado de 512 px, como en la web)
            PhotosPicker(selection: $foto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(url: c.fotoUrl, nombre: c.nombreCompleto, tamano: 104)
                    Image(systemName: subiendo ? "hourglass" : "camera.fill").font(.caption).padding(6)
                        .background(.regularMaterial, in: Circle())
                }
            }
            .disabled(subiendo)
            .accessibilityLabel("Cambiar la foto")
            VStack(alignment: .leading, spacing: 4) {
                Text(c.nombreCompleto).font(.title3.weight(.semibold))
                Text([c.tipo, c.telefono, c.email].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                if !c.activo { Insignia(texto: "Inactivo", color: .secondary) }
            }
        }
        if let n = c.notas, !n.isEmpty { Text(n).font(.subheadline) }
        Seccion("Lo que nos debe") {
            FilaValor(etiqueta: "Prestado", valor: Formato.dinero(c.prestado))
            FilaValor(etiqueta: "Pagado", valor: Formato.dinero(c.pagado))
            FilaValor(etiqueta: "Pendiente", valor: Formato.dinero(c.pendiente), color: Semantica.ingreso, negrita: true)
        }
        HStack {
            Button { formDeuda = false } label: { Text("Prestar / anotar").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            Button { formDeuda = true } label: { Text("Nos pagó").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                .disabled((Double(c.pendiente ?? "") ?? 0) <= 0)
        }
        ForEach(c.deudas ?? []) { d in
            Seccion(d.descripcion, accion: {
                Insignia(texto: d.estado == "pagada" ? "Pagada" : "Pendiente \(Formato.dinero(d.pendiente))", color: d.estado == "pagada" ? Semantica.ingreso : Semantica.aviso)
            }) {
                FilaValor(etiqueta: "\(Formato.fechaCorta(d.fecha)) · \(nombreOrigen(d.origen, cajas))" + (comunes.quien(d.userId).map { " · \($0)" } ?? ""), valor: Formato.dinero(d.monto))
                if let com = d.comentario, !com.isEmpty { Text(com).font(.caption).foregroundStyle(.secondary) }
                ForEach(d.pagos) { p in
                    Divider()
                    Button { borrarPago = p } label: {
                        HStack {
                            Text("Pagó el \(Formato.fechaCorta(p.fecha)) · \(nombreOrigen(p.destino, cajas))").font(.caption)
                            Spacer()
                            Text(Formato.dinero(p.monto)).font(.caption).foregroundStyle(Semantica.ingreso)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if d.pagos.isEmpty {
                    Button("Eliminar esta deuda", role: .destructive) { borrarDeuda = d }.font(.caption).buttonStyle(.borderless)
                }
            }
        }
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<Contacto> = try await API.shared.get("/contactos/\(id)")
            c = r.data
        } catch { self.error = error.localizedDescription }
        if cajas.isEmpty {
            cajas = Dictionary(await cargarCajas(conTarjetas: true).map { ($0.valor, $0.nombre) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func eliminar(_ ruta: String, _ texto: String) async {
        do { try await API.shared.borrar(ruta); aviso = texto; await cargar() } catch { aviso = error.localizedDescription }
    }

    private func subirFoto(_ item: PhotosPickerItem) async {
        defer { foto = nil; subiendo = false }
        guard let c, let datos = try? await item.loadTransferable(type: Data.self), let jpeg = Imagen.paraSubir(datos) else { aviso = "No se pudo leer la foto."; return }
        subiendo = true
        // El formulario exige todos los datos: viajan junto a la foto
        var campos = ["_method": "PUT", "nombre": c.nombre ?? c.nombreCompleto, "activo": c.activo ? "1" : "0"]
        campos["apellido"] = c.apellido; campos["telefono"] = c.telefono; campos["email"] = c.email; campos["notas"] = c.notas
        campos["tipo_contacto_id"] = c.tipoContactoId.map(String.init)
        do {
            let _: Envoltura<Contacto> = try await API.shared.subir("/contactos/\(c.id)", campos: campos, archivo: "foto", datos: jpeg)
            API.shared.olvidarImagen(c.fotoUrl)
            await cargar()
            await comunes.refrescarListas()
            aviso = "Foto actualizada."
        } catch { aviso = error.localizedDescription }
    }
}

/// Recorta al centro en cuadrado de 512 px y comprime en JPEG (como la web).
enum Imagen {
    static func paraSubir(_ datos: Data, lado: CGFloat = 512) -> Data? {
        guard let original = UIImage(data: datos) else { return nil }
        let menor = min(original.size.width, original.size.height)
        let escala = lado / menor
        let tamano = CGSize(width: original.size.width * escala, height: original.size.height * escala)
        let formato = UIGraphicsImageRendererFormat(); formato.scale = 1
        let recortada = UIGraphicsImageRenderer(size: CGSize(width: lado, height: lado), format: formato).image { _ in
            original.draw(in: CGRect(x: (lado - tamano.width) / 2, y: (lado - tamano.height) / 2, width: tamano.width, height: tamano.height))
        }
        return recortada.jpegData(compressionQuality: 0.85)
    }
}

/// "Prestar o anotar deuda" (pago == false) o "Nos pagó" (pago == true).
struct FormularioDeuda: View {
    let contacto: Contacto
    let pago: Bool
    let alGuardar: (Contacto) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var descripcion = ""
    @State private var monto = ""
    @State private var fecha = Date()
    @State private var origen = "efectivo"
    @State private var deudaId: Int?
    @State private var comentario = ""
    @State private var userId: Int?
    @State private var cajas: [(valor: String, nombre: String, saldo: String)] = []
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        let abiertas = (contacto.deudas ?? []).filter { $0.estado != "pagada" }
        NavigationStack {
            Form {
                Section {
                    if !pago {
                        TextField("¿Qué fue? (ej: camiseta, para el bus)", text: $descripcion); ErrorCampo(texto: errores["descripcion"])
                    }
                    CampoMonto(etiqueta: "Monto", valor: $monto, error: errores["monto"])
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                } footer: {
                    if pago { Text("Debe \(Formato.dinero(contacto.pendiente)): se aplica de la deuda más antigua a la más reciente.") }
                }
                Section {
                    Picker(pago ? "¿A dónde entró?" : "¿De dónde salió?", selection: $origen) {
                        ForEach(cajas.filter { !pago || !$0.valor.hasPrefix("tarjeta:") }, id: \.valor) { Text("\($0.nombre) (\($0.saldo))").tag($0.valor) }
                        Text(pago ? "Solo anotarlo (no entró dinero)" : "Solo anotarlo (no salió dinero)").tag("ninguno")
                    }
                    ErrorCampo(texto: errores[pago ? "destino" : "origen"])
                    if pago && abiertas.count > 1 {
                        Picker("¿A cuál deuda?", selection: $deudaId) {
                            Text("A la más antigua primero").tag(nil as Int?)
                            ForEach(abiertas) { Text("\($0.descripcion) (\(Formato.dinero($0.pendiente)))").tag($0.id as Int?) }
                        }
                    }
                    TextField("Comentario (opcional)", text: $comentario)
                    if comunes.miembros.count > 1 {
                        Picker("¿Quién lo registró?", selection: $userId) { ForEach(comunes.miembros) { Text($0.nombre).tag($0.id as Int?) } }
                    }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(pago ? "Nos pagó" : "Prestar o anotar deuda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
            .task {
                userId = comunes.usuario?.id
                cajas = await cargarCajas(conTarjetas: !pago)
            }
        }
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if !pago && descripcion.trimmingCharacters(in: .whitespaces).isEmpty { e["descripcion"] = "¿Qué le prestaron o qué debe?" }
        if !Formato.montoValido(monto) { e["monto"] = "Monto positivo con máximo dos decimales." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        let nota = comentario.trimmingCharacters(in: .whitespaces)
        do {
            let r: Envoltura<Contacto>
            if pago {
                r = try await API.shared.post("/contactos/\(contacto.id)/pagos", DeudaPagoBody(monto: monto, fecha: Formato.textoLocal(fecha), destino: origen, deudaId: deudaId,
                                                                                               comentario: nota.isEmpty ? nil : nota, userId: userId))
            } else {
                r = try await API.shared.post("/contactos/\(contacto.id)/deudas", DeudaBody(descripcion: descripcion.trimmingCharacters(in: .whitespaces), monto: monto,
                                                                                            fecha: Formato.textoLocal(fecha), origen: origen, comentario: nota.isEmpty ? nil : nota, userId: userId))
            }
            alGuardar(r.data)
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

/// Crear o editar los datos de un contacto (la foto se cambia tocándola en la ficha).
struct FormularioContacto: View {
    let contacto: Contacto?
    let alGuardar: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var apellido = ""
    @State private var tipoId: Int?
    @State private var telefono = ""
    @State private var email = ""
    @State private var notas = ""
    @State private var activo = true
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $nombre); ErrorCampo(texto: errores["nombre"])
                    TextField("Apellido (opcional)", text: $apellido)
                    Picker("Tipo", selection: $tipoId) {
                        Text("Elegir…").tag(nil as Int?)
                        ForEach(comunes.catalogos?.tiposContacto ?? []) { Text($0.nombre).tag($0.id as Int?) }
                    }
                    ErrorCampo(texto: errores["tipo_contacto_id"])
                }
                Section {
                    TextField("Teléfono (opcional)", text: $telefono).keyboardType(.phonePad)
                    TextField("Correo (opcional)", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    ErrorCampo(texto: errores["email"])
                    TextField("Notas (opcional)", text: $notas, axis: .vertical)
                }
                if contacto != nil {
                    Section { Toggle("Activo", isOn: $activo) } footer: { Text("Para cambiar la foto, tócala en la ficha del contacto.") }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(contacto == nil ? "Nuevo contacto" : "Editar contacto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
            .task {
                await comunes.cargarCatalogos()
                guard let c = contacto else { tipoId = comunes.catalogos?.tiposContacto.first?.id; return }
                nombre = c.nombre ?? c.nombreCompleto; apellido = c.apellido ?? ""; tipoId = c.tipoContactoId
                telefono = c.telefono ?? ""; email = c.email ?? ""; notas = c.notas ?? ""; activo = c.activo
            }
        }
    }

    private func guardar() async {
        var e: [String: String] = [:]
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { e["nombre"] = "Escribe el nombre." }
        if tipoId == nil { e["tipo_contacto_id"] = "Elige el tipo." }
        errores = e
        guard e.isEmpty, let tipoId else { return }
        guardando = true
        func opcional(_ t: String) -> String? { let v = t.trimmingCharacters(in: .whitespacesAndNewlines); return v.isEmpty ? nil : v }
        let cuerpo = ContactoBody(nombre: nombre.trimmingCharacters(in: .whitespaces), apellido: opcional(apellido), tipoContactoId: tipoId,
                                  telefono: opcional(telefono), email: opcional(email), notas: opcional(notas), activo: activo)
        do {
            if let c = contacto { try await API.shared.enviar("PUT", "/contactos/\(c.id)", cuerpo) } else { try await API.shared.enviar("POST", "/contactos", cuerpo) }
            await comunes.refrescarListas()
            alGuardar(contacto == nil ? "Contacto creado." : "Contacto actualizado.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

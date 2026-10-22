import PhotosUI
import SwiftUI

/// Mi perfil: foto, nombre y correo.
struct PerfilView: View {
    @State private var nombre = ""
    @State private var email = ""
    @State private var emailOriginal = ""
    @State private var foto: String?
    @State private var elegida: PhotosPickerItem?
    @State private var subiendo = false
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    @State private var aviso: String?
    private let comunes = Comunes.shared

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    PhotosPicker(selection: $elegida, matching: .images) {
                        Avatar(url: foto, nombre: nombre.isEmpty ? "?" : nombre, tamano: 120)
                    }
                    PhotosPicker(subiendo ? "Subiendo foto…" : "Cambiar foto", selection: $elegida, matching: .images).disabled(subiendo)
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                TextField("Nombre", text: $nombre).textContentType(.name); ErrorCampo(texto: errores["name"])
                TextField("Correo", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                ErrorCampo(texto: errores["email"])
            } footer: {
                if email.trimmingCharacters(in: .whitespaces).lowercased() != emailOriginal.lowercased() {
                    Text("Al cambiar el correo te llegará un enlace para verificarlo de nuevo.")
                }
            }
            if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Mi perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) } }
        .task {
            await comunes.cargar(refrescar: true)
            guard let u = comunes.usuario else { return }
            nombre = u.name; email = u.email; emailOriginal = u.email; foto = Formato.urlAvatar(u.avatar)
        }
        .onChange(of: elegida) { _, item in if let item { Task { await subir(item) } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func subir(_ item: PhotosPickerItem) async {
        defer { elegida = nil; subiendo = false }
        guard let datos = try? await item.loadTransferable(type: Data.self), let jpeg = Imagen.paraSubir(datos) else { error = "No se pudo leer la foto."; return }
        subiendo = true
        do {
            let r: AvatarRespuesta = try await API.shared.subir("/profile/avatar", campos: ["_method": "PATCH"], archivo: "avatar", datos: jpeg)
            // ?v= evita que se muestre la foto anterior guardada en caché
            foto = r.avatarUrl.map { "\($0)?v=\(Int(Date().timeIntervalSince1970))" }
            await comunes.cargar(refrescar: true)
            aviso = "Foto actualizada."
        } catch { self.error = error.localizedDescription }
    }

    private func guardar() async {
        var e: [String: String] = [:]
        let correo = email.trimmingCharacters(in: .whitespaces).lowercased()
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { e["name"] = "Escribe tu nombre." }
        if correo.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil { e["email"] = "Correo no válido." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        do {
            try await API.shared.enviar("PATCH", "/profile", PerfilBody(name: nombre.trimmingCharacters(in: .whitespaces), email: correo))
            await comunes.cargar(refrescar: true)
            emailOriginal = correo
            aviso = "Perfil actualizado."
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }
}

/// Categorías de ingresos y egresos del hogar.
struct CategoriasView: View {
    @State private var categorias: [Categoria] = []
    @State private var tipo = "egreso"
    @State private var cargando = true
    @State private var error: String?
    @State private var editando: Categoria?
    @State private var nueva = false
    @State private var aviso: String?

    var body: some View {
        List {
            Section {
                Picker("Tipo", selection: $tipo) {
                    Text("Egresos (\(categorias.filter { $0.tipo == "egreso" }.count))").tag("egreso")
                    Text("Ingresos (\(categorias.filter { $0.tipo == "ingreso" }.count))").tag("ingreso")
                }.pickerStyle(.segmented)
            }
            if cargando && categorias.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, categorias.isEmpty {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else {
                Section {
                    ForEach(categorias.filter { $0.tipo == tipo }) { c in
                        Button { abrir(c) } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Formato.color(c.color)).frame(width: 14, height: 14)
                                Text(c.nombre).foregroundStyle(c.activo ? .primary : .secondary)
                                Spacer()
                                if !c.activo { Insignia(texto: "Inactiva", color: .secondary) }
                                if c.editable == false { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Categorías")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva categoría") } }
        .task { await cargar() }
        .refreshable { await cargar() }
        .sheet(isPresented: $nueva) { FormularioCategoria(categoria: nil, tipoInicial: tipo) { aviso = $0; Task { await cargar() } } }
        .sheet(item: $editando) { c in FormularioCategoria(categoria: c, tipoInicial: c.tipo) { aviso = $0; Task { await cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func abrir(_ c: Categoria) {
        if c.editable == false { aviso = "«\(c.nombre)» la usa el sistema y no se modifica."; return }
        editando = c
    }

    private func cargar() async {
        error = nil
        do {
            let r: Envoltura<[Categoria]> = try await API.shared.get("/categorias")
            categorias = r.data.sorted { $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
        cargando = false
    }
}

struct FormularioCategoria: View {
    let categoria: Categoria?
    let tipoInicial: String
    let alGuardar: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var tipo = "egreso"
    @State private var color = "#1155CC"
    @State private var activo = true
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $nombre); ErrorCampo(texto: errores["nombre"])
                    Picker("Tipo", selection: $tipo) { Text("Egreso").tag("egreso"); Text("Ingreso").tag("ingreso") }.pickerStyle(.segmented)
                }
                Section {
                    SelectorColor(color: $color)
                    if categoria != nil { Toggle("Activa", isOn: $activo) }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .barraFormulario(categoria == nil ? "Nueva categoría" : "Editar categoría", guardando: guardando, guardar: { await guardar() },
                             eliminar: accionEliminar, queSeElimina: "esta categoría")
            .onAppear {
                tipo = tipoInicial
                guard let c = categoria else { return }
                nombre = c.nombre; color = c.color ?? color; activo = c.activo
            }
        }
    }

    private var accionEliminar: (() async -> Void)? {
        guard categoria != nil else { return nil }
        return { await eliminar() }
    }

    private func guardar() async {
        guard !nombre.trimmingCharacters(in: .whitespaces).isEmpty else { errores = ["nombre": "Escribe el nombre."]; return }
        errores = [:]
        guardando = true
        let cuerpo = CategoriaBody(nombre: nombre.trimmingCharacters(in: .whitespaces), tipo: tipo, color: color, activo: activo)
        do {
            if let c = categoria { try await API.shared.enviar("PUT", "/categorias/\(c.id)", cuerpo) } else { try await API.shared.enviar("POST", "/categorias", cuerpo) }
            await Comunes.shared.refrescarListas()
            alGuardar(categoria == nil ? "Categoría creada." : "Categoría actualizada.")
            cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
        guardando = false
    }

    private func eliminar() async {
        guard let c = categoria else { return }
        do {
            try await API.shared.borrar("/categorias/\(c.id)")
            await Comunes.shared.refrescarListas()
            alGuardar("Categoría eliminada.")
            cerrar()
        } catch { self.error = error.localizedDescription }
    }
}

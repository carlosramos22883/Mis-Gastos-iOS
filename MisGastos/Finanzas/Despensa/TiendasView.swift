import SwiftUI

/// Tiendas donde compra el hogar (con precios en línea o anotados).
struct TiendasView: View {
    private let comunes = Comunes.shared
    @State private var tiendas: [Tienda] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var aviso: String?
    @State private var editando: Editando?
    @State private var eliminar: Tienda?

    struct Editando: Identifiable { let tienda: Tienda?; var id: Int { tienda?.id ?? 0 } }

    var body: some View {
        List {
            Section { Button("Agregar las de siempre") { Task { await comunesTiendas() } } }
            if cargando && tiendas.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, tiendas.isEmpty {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else {
                ForEach(tiendas) { t in
                    Button { editando = Editando(tienda: t) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(t.nombre).fontWeight(.semibold).foregroundStyle(.primary)
                                Text(t.fuente != nil ? "Precios en línea" : "Precio anotado").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !t.activo { Insignia(texto: "Inactiva", color: .secondary) }
                        }
                    }
                    .swipeActions { if (t.preciosCount ?? 0) == 0 { Button("Eliminar", role: .destructive) { eliminar = t } } }
                }
            }
        }
        .navigationTitle("Tiendas")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { editando = Editando(tienda: nil) } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva tienda") } }
        .task { await comunes.cargarCatalogos(); await cargar() }
        .refreshable { await cargar() }
        .sheet(item: $editando) { e in FormularioTienda(tienda: e.tienda, fuentes: comunes.catalogos?.despensa?.fuentes ?? [:]) { Task { await cargar() } } }
        .confirmationDialog("¿Eliminar \(eliminar?.nombre ?? "")?", isPresented: Binding(get: { eliminar != nil }, set: { if !$0 { eliminar = nil } }), titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { if let t = eliminar { Task { await borrar(t) } } }
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func cargar() async {
        do { let r: Envoltura<[Tienda]> = try await API.shared.get("/tiendas"); tiendas = r.data; error = nil } catch { self.error = error.localizedDescription }
        cargando = false
    }

    private func comunesTiendas() async {
        do {
            let r: TiendasComunes = try await API.shared.post("/tiendas/comunes", Vacio())
            tiendas = r.data
            aviso = r.agregadas == 0 ? "Ya tienes todas las tiendas comunes." : r.agregadas == 1 ? "Se agregó 1 tienda." : "Se agregaron \(r.agregadas) tiendas."
        } catch { aviso = error.localizedDescription }
    }

    private func borrar(_ t: Tienda) async {
        do { try await API.shared.borrar("/tiendas/\(t.id)"); await cargar() } catch { aviso = error.localizedDescription }
    }
}

private struct FormularioTienda: View {
    let tienda: Tienda?
    let fuentes: [String: String]
    let alGuardar: () -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var fuente: String?
    @State private var notas = ""
    @State private var activo = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $nombre)
                Picker("Precios en línea", selection: $fuente) {
                    Text("No (precio anotado)").tag(String?.none)
                    ForEach(fuentes.sorted(by: { $0.key < $1.key }), id: \.key) { Text($0.value).tag(Optional($0.key)) }
                }
                TextField("Notas", text: $notas, axis: .vertical)
                if tienda != nil { Toggle("Activa", isOn: $activo) }
                if (tienda?.preciosCount ?? 0) > 0 { Text("Tiene precios o compras: no se elimina, se desactiva.").font(.caption).foregroundStyle(.secondary) }
                ErrorCampo(texto: error)
            }
            .navigationTitle(tienda == nil ? "Nueva tienda" : "Editar tienda").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } } }
            }
            .onAppear { if let t = tienda { nombre = t.nombre; fuente = t.fuente; notas = t.notas ?? ""; activo = t.activo } }
        }
    }

    private func guardar() async {
        let body = TiendaBody(nombre: nombre.trimmingCharacters(in: .whitespaces), fuente: fuente, notas: notas.isEmpty ? nil : notas, activo: activo)
        do {
            if let t = tienda { let _: Envoltura<Tienda> = try await API.shared.put("/tiendas/\(t.id)", body) } else { let _: Envoltura<Tienda> = try await API.shared.post("/tiendas", body) }
            alGuardar(); cerrar()
        } catch { self.error = error.localizedDescription }
    }
}

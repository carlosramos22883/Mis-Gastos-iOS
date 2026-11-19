import SwiftUI

/// Despensa: productos con lo que hay en casa (sumar, restar, «se está acabando», «se acabó»), escanear y crear.
struct DespensaView: View {
    @State private var productos: [Producto] = []
    @State private var pestana = "todos"
    @State private var faltan = 0
    @State private var porVencer = 0
    @State private var busqueda = ""
    @State private var cargando = true
    @State private var error: String?
    @State private var aviso: String?
    @State private var enviando: Int?
    @State private var escaneando = false
    @State private var nuevo: NuevoProducto?

    struct NuevoProducto: Identifiable { let codigo: String?; var id: String { codigo ?? "nuevo" } }

    var body: some View {
        let lista = productos.filter {
            let b = busqueda.trimmingCharacters(in: .whitespaces)
            return b.isEmpty || $0.nombreCompleto.localizedCaseInsensitiveContains(b) || ($0.codigoBarras?.contains(b) ?? false)
        }
        List {
            Section {
                Picker("Mostrar", selection: $pestana) {
                    Text("Todos").tag("todos"); Text(faltan > 0 ? "Faltan (\(faltan))" : "Faltan").tag("faltan"); Text("Ya no los compro").tag("archivados")
                }.pickerStyle(.segmented)
                if porVencer > 0 && pestana != "archivados" {
                    Text(porVencer == 1 ? "Un producto vence pronto o ya venció." : "\(porVencer) productos vencen pronto o ya vencieron.").font(.caption).foregroundStyle(Semantica.aviso)
                }
            }
            if cargando && productos.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, productos.isEmpty {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else if lista.isEmpty {
                Text(!busqueda.isEmpty ? "Ningún producto coincide con la búsqueda." : pestana == "faltan" ? "No falta nada. La despensa está completa."
                     : pestana == "archivados" ? "No hay productos archivados." : "Aún no tienes productos. Agrega lo que compras siempre o escanea su código de barras.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lista) { p in
                    NavigationLink(value: RutaDespensa.producto(p.id)) { fila(p) }
                }
            }
        }
        .searchable(text: $busqueda, prompt: "Producto, marca o código")
        .navigationTitle("Despensa")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { escaneando = true } label: { Image(systemName: "barcode.viewfinder") }.accessibilityLabel("Escanear código de barras")
                NavigationLink(value: RutaDespensa.tiendas) { Image(systemName: "storefront") }.accessibilityLabel("Tiendas")
                NavigationLink(value: RutaDespensa.compras) { Image(systemName: "cart") }.accessibilityLabel("Lista de compras")
                Button { nuevo = NuevoProducto(codigo: nil) } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo producto")
            }
        }
        .task { await cargar() }
        .onChange(of: pestana) { _, _ in productos = []; cargando = true; Task { await cargar() } }
        .refreshable { await cargar() }
        .sheet(isPresented: $escaneando) { EscanerCodigo { codigo in Task { await alEscanear(codigo) } } }
        .sheet(item: $nuevo) { n in NavigationStack { ProductoView(id: nil, codigoInicial: n.codigo) }.onDisappear { Task { await cargar() } } }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
        .navigationDestination(item: $abrir) { id in ProductoView(id: id, codigoInicial: nil) }
    }

    private func fila(_ p: Producto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Avatar(url: p.fotoUrl, nombre: p.nombre, tamano: 56, cuadrado: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.nombre).font(.headline)
                    Text([p.marca, p.presentacion].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("Sin marca")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if p.basico { Insignia(texto: "Básico", color: .accentColor) }
                        if let e = p.estado, e.falta { Insignia(texto: "Falta · comprar \(e.porComprar)", color: Semantica.egreso) }
                        if let v = p.estado?.vencimiento, v.aviso { Insignia(texto: v.texto, color: Semantica.aviso) }
                    }
                }
            }
            if p.activo, let e = p.estado {
                HStack(spacing: 10) {
                    Text("En casa").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await ajustar(p, "restar") } } label: { Image(systemName: "minus.circle.fill") }.disabled(enviando == p.id || (e.enCasa ?? 0) == 0)
                    Text(e.enCasa.map(String.init) ?? "?").font(.headline)
                    Button { Task { await ajustar(p, "sumar") } } label: { Image(systemName: "plus.circle.fill") }.disabled(enviando == p.id)
                    if let ideal = p.cantidadIdeal { Text("de \(ideal)").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(e.porAcabarse ? "Se está acabando ✓" : "Se está acabando") { Task { await ajustar(p, "por_acabarse", e.porAcabarse ? "0" : "1") } }
                        .font(.caption).tint(Semantica.aviso)
                    if e.enCasa != 0 { Button("Se acabó") { Task { await ajustar(p, "se_acabo") } }.font(.caption).tint(Semantica.egreso) }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func cargar() async {
        var filtros: [String: String?] = [:]
        if pestana == "faltan" { filtros["faltan"] = "1" }
        if pestana == "archivados" { filtros["archivados"] = "1" }
        do {
            let r: ListaProductos = try await API.shared.get("/productos", filtros)
            productos = r.data; faltan = r.meta.resumen.faltan; porVencer = r.meta.resumen.porVencer; error = nil
        } catch { self.error = error.localizedDescription }
        cargando = false
    }

    private func ajustar(_ p: Producto, _ accion: String, _ valor: String? = nil) async {
        enviando = p.id
        defer { enviando = nil }
        do {
            let r: EstadoRespuesta = try await API.shared.patch("/productos/\(p.id)/despensa", DespensaBody(accion: accion, valor: valor))
            if let i = productos.firstIndex(where: { $0.id == p.id }) { productos[i].estado = r.estado }
        } catch { aviso = error.localizedDescription }
    }

    /// Si el código está en la despensa se abre; si no, se crea un producto con ese código.
    private func alEscanear(_ codigo: String) async {
        if let r: Envoltura<Producto> = try? await API.shared.get("/productos/codigo/\(codigo)") {
            abrir = r.data.id
        } else {
            nuevo = NuevoProducto(codigo: codigo)
        }
    }

    @State private var abrir: Int?
}

extension String {
    func ifEmpty(_ otro: String) -> String { isEmpty ? otro : self }
}

/// Rutas del módulo (en su propio NavigationStack de la pestaña donde se abra).
enum RutaDespensa: Hashable {
    case producto(Int)
    case tiendas
    case compras
    case lista(Int)
}

extension View {
    func destinosDespensa() -> some View {
        navigationDestination(for: RutaDespensa.self) { ruta in
            switch ruta {
            case .producto(let id): ProductoView(id: id, codigoInicial: nil)
            case .tiendas: TiendasView()
            case .compras: ComprasView()
            case .lista(let id): ListaCompraView(id: id)
            }
        }
    }
}

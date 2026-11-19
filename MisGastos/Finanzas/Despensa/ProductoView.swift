import PhotosUI
import SwiftUI

/// Producto de la despensa: formulario (con foto y código de barras), sus precios por tienda y su liga con las tiendas en línea.
/// id nil = nuevo (con el código escaneado, si lo hay).
struct ProductoView: View {
    let id: Int?
    let codigoInicial: String?

    @Environment(\.dismiss) private var cerrar
    private let comunes = Comunes.shared
    @State private var producto: Producto?
    @State private var tiendas: [Tienda] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var aviso: String?
    @State private var errores: [String: String] = [:]
    @State private var guardando = false
    @State private var confirmarEliminar = false
    @State private var escaneando = false
    @State private var anotando = false
    @State private var buscandoEn: Fuente?
    @State private var quitarLiga: String?
    @State private var foto: PhotosPickerItem?
    @State private var fotoNueva: Data?

    // Formulario
    @State private var nombre = ""
    @State private var marca = ""
    @State private var cantidad = ""
    @State private var unidad: String?
    @State private var codigo = ""
    @State private var categoria: Int?
    @State private var importancia = "basico"
    @State private var duracion = "duradero"
    @State private var otraMarca = false
    @State private var ideal = ""
    @State private var avisar = ""
    @State private var enCasa = ""
    @State private var vence: Date?
    @State private var notas = ""
    @State private var activo = true

    struct Fuente: Identifiable { let clave: String; var id: String { clave } }

    private var valores: ValoresDespensa? { comunes.catalogos?.despensa }

    var body: some View {
        Form {
            if cargando {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else {
                formulario
                if let p = producto {
                    precios(p)
                    enLinea(p)
                    Section { Button("Eliminar producto", role: .destructive) { confirmarEliminar = true } }
                }
            }
        }
        .navigationTitle(producto?.nombre ?? "Nuevo producto")
        .toolbar {
            if id == nil && producto == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            ToolbarItem(placement: .confirmationAction) { Button(guardando ? "Guardando…" : "Guardar") { Task { await guardar() } }.disabled(guardando || cargando) }
        }
        .task { if cargando { await cargar() } }
        .onChange(of: foto) { _, item in
            guard let item else { return }
            Task { if let d = try? await item.loadTransferable(type: Data.self) { fotoNueva = Imagen.paraSubir(d, lado: 600) } }
        }
        .sheet(isPresented: $escaneando) { EscanerCodigo { codigo = $0 } }
        .sheet(isPresented: $anotando) { HojaPrecio(tiendas: tiendas.filter(\.activo)) { t, precio, u, fecha in await anotarPrecio(t, precio, u, fecha) } }
        .sheet(item: $buscandoEn) { f in
            if let p = producto { HojaBuscarEnLinea(producto: p, fuente: f.clave, nombre: nombreFuente(f.clave, valores)) { nuevo in producto = nuevo } }
        }
        .confirmationDialog("¿Eliminar el producto?", isPresented: $confirmarEliminar, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { Task { await eliminar() } }
        } message: { Text("Se borra con su foto y sus precios.") }
        .confirmationDialog("¿Quitar la liga?", isPresented: Binding(get: { quitarLiga != nil }, set: { if !$0 { quitarLiga = nil } }), titleVisibility: .visible) {
            Button("Quitar", role: .destructive) { if let f = quitarLiga { Task { await desenlazar(f) } } }
        } message: { Text("Ya no se consultará su precio en esa tienda. Los precios leídos se quedan.") }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    @ViewBuilder private var formulario: some View {
        Section {
            HStack(spacing: 12) {
                PhotosPicker(selection: $foto, matching: .images) {
                    if let fotoNueva, let img = UIImage(data: fotoNueva) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Avatar(url: producto?.fotoUrl, nombre: nombre.ifEmpty("?"), tamano: 80, cuadrado: true)
                    }
                }
                Text(fotoNueva != nil ? "Foto lista: se sube al guardar." : "Toca para elegir una foto (se recorta cuadrada).").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Producto (ej. Atún)", text: $nombre)
            ErrorCampo(texto: errores["nombre"])
            TextField("Marca", text: $marca)
            HStack {
                TextField("Presentación (ej. 140)", text: $cantidad).keyboardType(.decimalPad)
                Picker("Unidad", selection: $unidad) {
                    Text("—").tag(String?.none)
                    ForEach((valores?.unidades ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { Text($0.value).tag(Optional($0.key)) }
                }.labelsHidden()
            }
            ErrorCampo(texto: errores["cantidad"] ?? errores["unidad"])
            HStack {
                TextField("Código de barras", text: $codigo).keyboardType(.numberPad)
                Button { escaneando = true } label: { Image(systemName: "barcode.viewfinder") }.buttonStyle(.borderless).accessibilityLabel("Escanear")
            }
            ErrorCampo(texto: errores["codigo_barras"])
        }
        Section {
            Picker("Categoría", selection: $categoria) {
                ForEach(comunes.catalogos?.categoriasDespensa ?? []) { Text($0.nombre).tag(Optional($0.id)) }
            }
            Picker("Importancia", selection: $importancia) { ForEach((valores?.importancias ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { Text($0.value).tag($0.key) } }
            Picker("Duración", selection: $duracion) { ForEach((valores?.duraciones ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { Text($0.value).tag($0.key) } }
            Toggle("Otra marca también sirve", isOn: $otraMarca)
        }
        Section("Lo que hay en casa") {
            LabeledContent("Cantidad ideal") { TextField("0", text: $ideal).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            ErrorCampo(texto: errores["cantidad_ideal"])
            LabeledContent("Avisar cuando queden") { TextField("0", text: $avisar).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            ErrorCampo(texto: errores["avisar_cuando"])
            LabeledContent("Hay en casa") { TextField("sin contar", text: $enCasa).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            if duracion == "perecedero" {
                Toggle("Tiene fecha de vencimiento", isOn: Binding(get: { vence != nil }, set: { vence = $0 ? (vence ?? Date()) : nil }))
                if let v = vence { DatePicker("Vence el", selection: Binding(get: { v }, set: { vence = $0 }), displayedComponents: .date) }
            }
            TextField("Notas", text: $notas, axis: .vertical)
            if producto != nil { Toggle("Lo sigo comprando", isOn: $activo) }
        }
    }

    private func precios(_ p: Producto) -> some View {
        Section {
            let lista = p.precios ?? []
            if lista.isEmpty { Text("Aún no hay precios. Anótalo cuando lo veas, o se guarda solo al comprarlo con la lista.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(lista.enumerated()), id: \.element.id) { i, pr in
                HStack {
                    VStack(alignment: .leading) {
                        HStack { Text(pr.tienda ?? "").fontWeight(.semibold); if i == 0 && lista.count > 1 { Insignia(texto: "Más barato", color: Semantica.ingreso) } }
                        Text("\(origen(pr.origen)) · \(Formato.fechaCorta(pr.fecha))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(Formato.dinero(pr.precio) + (pr.unidades > 1 ? " × \(pr.unidades)" : "")).fontWeight(.semibold)
                        if pr.unidades > 1 { Text("\(Formato.dinero(pr.porUnidad)) c/u").font(.caption) }
                    }
                }
            }
            Button("Anotar un precio que viste") { anotando = true }
        } header: { Text("Precios") }
    }

    @ViewBuilder private func enLinea(_ p: Producto) -> some View {
        let fuentes = Array(Set(tiendas.filter(\.activo).compactMap(\.fuente))).sorted()
        if !fuentes.isEmpty {
            Section {
                ForEach(fuentes, id: \.self) { f in
                    let enlace = p.enLinea?.first { $0.fuente == f }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nombreFuente(f, valores)).fontWeight(.semibold)
                            if let enlace {
                                if let u = enlace.url, let url = URL(string: u) { Link(enlace.nombre, destination: url).font(.caption) } else { Text(enlace.nombre).font(.caption) }
                                if enlace.unidades > 1 { Text("Paquete de \(enlace.unidades)").font(.caption2).foregroundStyle(.secondary) }
                                if let e = enlace.error { Text(e == "no_encontrado" ? "La tienda ya no lo tenía: búscalo otra vez." : "No mostraba precio.").font(.caption2).foregroundStyle(Semantica.aviso) }
                            } else { Text("Sin ligar").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button(enlace == nil ? "Buscar" : "Cambiar") { buscandoEn = Fuente(clave: f) }.buttonStyle(.borderless)
                        if enlace != nil { Button("Quitar", role: .destructive) { quitarLiga = f }.buttonStyle(.borderless) }
                    }
                }
            } header: { Text("En línea") } footer: {
                if fuentes.contains("walmart") && fuentes.contains("donjuan") { Text("Walmart y Don Juan comparten catálogo: al ligar uno se liga también el otro.") }
            }
        }
    }

    private func origen(_ o: String) -> String { o == "en_linea" ? "En línea" : o == "compra" ? "Compra" : "Anotado" }

    // MARK: - Datos

    private func cargar() async {
        await comunes.cargarCatalogos()
        if let t: Envoltura<[Tienda]> = try? await API.shared.get("/tiendas") { tiendas = t.data }
        if let id = producto?.id ?? id {
            do { let r: Envoltura<Producto> = try await API.shared.get("/productos/\(id)"); llenar(r.data); error = nil } catch { self.error = error.localizedDescription }
        } else if nombre.isEmpty {
            codigo = codigoInicial ?? ""
            categoria = comunes.catalogos?.categoriasDespensa?.first?.id
        }
        cargando = false
    }

    private func llenar(_ p: Producto) {
        producto = p
        nombre = p.nombre; marca = p.marca ?? ""; cantidad = p.cantidad ?? ""; unidad = p.unidad; codigo = p.codigoBarras ?? ""
        categoria = p.categoriaDespensaId; importancia = p.importancia; duracion = p.duracion; otraMarca = p.aceptaOtraMarca
        ideal = p.cantidadIdeal.map(String.init) ?? ""; avisar = p.avisarCuando.map(String.init) ?? ""; enCasa = p.estado?.enCasa.map(String.init) ?? ""
        vence = p.estado?.venceEl.flatMap { Date(iso: $0) }; notas = p.notas ?? ""; activo = p.activo
    }

    private var cuerpo: ProductoBody {
        func t(_ s: String) -> String? { let x = s.trimmingCharacters(in: .whitespaces); return x.isEmpty ? nil : x }
        return ProductoBody(nombre: nombre.trimmingCharacters(in: .whitespaces), marca: t(marca), cantidad: t(cantidad.replacingOccurrences(of: ",", with: ".")),
                            unidad: t(cantidad) == nil ? nil : unidad, codigoBarras: t(codigo.filter(\.isNumber)), categoriaDespensaId: categoria,
                            importancia: importancia, duracion: duracion, aceptaOtraMarca: otraMarca, cantidadIdeal: Int(ideal), avisarCuando: Int(avisar),
                            enCasa: Int(enCasa), venceEl: duracion == "perecedero" ? vence.map(Formato.texto) : nil, notas: t(notas), activo: activo)
    }

    private func guardar() async {
        guardando = true; errores = [:]
        defer { guardando = false }
        do {
            var r: Envoltura<Producto> = producto == nil ? try await API.shared.post("/productos", cuerpo) : try await API.shared.put("/productos/\(producto!.id)", cuerpo)
            if let fotoNueva {
                API.shared.olvidarImagen(r.data.fotoUrl)
                r = try await API.shared.subir("/productos/\(r.data.id)", campos: cuerpo.campos.merging(["_method": "PUT"]) { $1 }, archivo: "foto", datos: fotoNueva)
                self.fotoNueva = nil
            }
            let nuevo = producto == nil
            llenar(r.data)
            if nuevo && id == nil { cerrar() } else { aviso = "Producto actualizado." }
        } catch let f as FallaAPI { errores = f.campos; aviso = f.mensaje } catch { aviso = error.localizedDescription }
    }

    private func eliminar() async {
        guard let p = producto else { return }
        do { try await API.shared.borrar("/productos/\(p.id)"); cerrar() } catch { aviso = error.localizedDescription }
    }

    private func anotarPrecio(_ tienda: Int, _ precio: String, _ unidades: Int?, _ fecha: String) async -> String? {
        guard let p = producto else { return nil }
        do {
            let r: Envoltura<Producto> = try await API.shared.post("/productos/\(p.id)/precios", PrecioBody(tiendaId: tienda, precio: precio, unidades: unidades, fecha: fecha))
            producto = r.data; return nil
        } catch { return error.localizedDescription }
    }

    private func desenlazar(_ fuente: String) async {
        guard let p = producto else { return }
        do { try await API.shared.borrar("/productos/\(p.id)/en-linea/\(fuente)"); await cargar() } catch { aviso = error.localizedDescription }
    }
}

/// Anotar un precio visto: tienda, precio, «paquete de» y fecha. Devuelve el error (o nil si se guardó).
private struct HojaPrecio: View {
    let tiendas: [Tienda]
    let guardar: (Int, String, Int?, String) async -> String?
    @Environment(\.dismiss) private var cerrar
    @State private var tienda: Int?
    @State private var precio = ""
    @State private var unidades = ""
    @State private var fecha = Date()
    @State private var error: String?
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                if tiendas.isEmpty { Text("Primero agrega tus tiendas (Despensa → Tiendas).") }
                Picker("Tienda", selection: $tienda) { ForEach(tiendas) { Text($0.nombre).tag(Optional($0.id)) } }
                CampoMonto(etiqueta: "Precio", valor: $precio)
                TextField("Paquete de (opcional)", text: $unidades).keyboardType(.numberPad)
                Text("Ej. 3 latas por $5.25: escribe 5.25 y 3; se compara por unidad.").font(.caption).foregroundStyle(.secondary)
                DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                ErrorCampo(texto: error)
            }
            .navigationTitle("Anotar precio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anotar") {
                        guard let tienda, Formato.montoValido(precio) else { error = "Elige la tienda y escribe el precio."; return }
                        guardando = true
                        Task { error = await guardar(tienda, precio, Int(unidades), Formato.texto(fecha)); guardando = false; if error == nil { cerrar() } }
                    }.disabled(guardando)
                }
            }
            .onAppear { tienda = tienda ?? tiendas.first?.id }
        }
    }
}

/// Buscar el producto en una tienda en línea y ligarlo («Es este»).
private struct HojaBuscarEnLinea: View {
    let producto: Producto
    let fuente: String
    let nombre: String
    let alLigar: (Producto) -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var texto = ""
    @State private var resultados: [ResultadoEnLinea]?
    @State private var buscando = false
    @State private var error: String?
    @State private var unidades = "1"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Buscar", text: $texto).onSubmit { Task { await buscar(texto) } }
                        Button("Buscar") { Task { await buscar(texto) } }.disabled(buscando)
                    }
                    if resultados?.isEmpty == false { LabeledContent("Allá se vende en paquete de") { TextField("1", text: $unidades).keyboardType(.numberPad).multilineTextAlignment(.trailing) } }
                }
                if buscando { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(.red) }
                if let r = resultados, r.isEmpty { Text("No salió nada. Prueba con menos palabras (ej. solo la marca y el producto).").foregroundStyle(.secondary) }
                ForEach(resultados ?? []) { r in
                    HStack(spacing: 10) {
                        Avatar(url: r.imagen, nombre: r.nombre, tamano: 44, cuadrado: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.nombre).font(.subheadline)
                            HStack {
                                Text(r.precio.map { Formato.dinero($0) } ?? "sin precio").font(.caption)
                                if r.mismoCodigo == true { Insignia(texto: "Mismo código de barras", color: Semantica.ingreso) }
                            }
                        }
                        Spacer()
                        Button("Es este") { Task { await ligar(r) } }.buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("Buscar en \(nombre)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } } }
            .task { texto = producto.nombreCompleto; await buscar(nil) }
        }
    }

    private func buscar(_ q: String?) async {
        buscando = true; error = nil
        defer { buscando = false }
        do { let r: ResultadosEnLinea = try await API.shared.get("/productos/\(producto.id)/en-linea/\(fuente)", ["q": q]); resultados = r.data }
        catch { resultados = nil; self.error = error.localizedDescription }
    }

    private func ligar(_ r: ResultadoEnLinea) async {
        var elegido = r
        elegido.unidades = max(1, Int(unidades) ?? 1)
        elegido.mismoCodigo = nil
        do { let p: Envoltura<Producto> = try await API.shared.post("/productos/\(producto.id)/en-linea/\(fuente)", elegido); alLigar(p.data); cerrar() }
        catch { self.error = error.localizedDescription }
    }
}

private extension ResultadosEnLinea { var data: [ResultadoEnLinea] { resultados } }

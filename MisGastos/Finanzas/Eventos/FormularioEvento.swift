import SwiftUI
import PhotosUI

/// Crear o editar un evento como la hoja de cálculo: personas (filas), productos con su precio (columnas) y en cada
/// celda cuántos pidió cada uno. Lo que le toca a cada uno se calcula en vivo (igual que el servidor).
struct FormularioEvento: View {
    let evento: Evento?
    let alGuardar: (Evento) -> Void

    private static let nuevo = "__nuevo"
    private static let anchoNombre: CGFloat = 110
    private static let anchoProducto: CGFloat = 72
    private static let anchoResumen: CGFloat = 88
    private static let altoFila: CGFloat = 40

    struct FilaPersona: Identifiable { let id: Int; var quien: String; var nuevo = ""; var festejado = false }
    struct FilaProducto: Identifiable {
        /// compartido: el precio es el del producto completo y cant son las porciones de cada uno.
        let id: Int; var descripcion = ""; var precio = ""; var compartido = false; var cant: [Int: String] = [:]
        func cantidad(_ uid: Int) -> Int { max(0, Int(cant[uid] ?? "") ?? 0) }
    }

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var fecha = Date()
    @State private var lugar = ""
    @State private var personas: [FilaPersona] = []
    @State private var pagador: Int?
    @State private var productos: [FilaProducto] = []
    @State private var propinaTipo = "porcentaje"
    @State private var propinaValor = "10"
    @State private var origen = "efectivo"
    @State private var categoriaId: Int?
    @State private var opciones: OpcionesEvento?
    @State private var elegida: PhotosPickerItem?
    @State private var fotoNueva: Data?
    @State private var quitarFoto = false
    @State private var siguiente = 1000
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    @State private var pregunta: String?
    @State private var listo = false
    private let comunes = Comunes.shared

    private var pagaElHogar: Bool { personas.first { $0.id == pagador }?.quien.hasPrefix("miembro:") == true }
    private var hayPropina: Bool { propinaTipo != "ninguna" }
    private var hayFestejo: Bool { personas.contains(where: \.festejado) }
    private var tieneFoto: Bool { fotoNueva != nil || (evento?.fotoUrl != nil && !quitarFoto) }
    private func producto(_ p: FilaProducto) -> CalculoEvento.Producto {
        .init(centavos: Int(((Double(p.precio) ?? 0) * 100).rounded()), compartido: p.compartido, cant: Dictionary(uniqueKeysWithValues: personas.map { ($0.id, p.cantidad($0.id)) }))
    }

    /// Producto compartido: todos comieron de él (una porción cada uno).
    private func todosComieron() -> [Int: String] { Dictionary(uniqueKeysWithValues: personas.map { ($0.id, "1") }) }

    private var reparto: CalculoEvento.Reparto {
        CalculoEvento.calcular(personas.map { .init(uid: $0.id, festejado: $0.festejado) },
                               productos.map { producto($0) },
                               propinaTipo: propinaTipo, propinaValor: propinaValor)
    }

    private func nombre(_ p: FilaPersona) -> String {
        if p.quien == Self.nuevo { return p.nuevo.isEmpty ? "Nuevo" : p.nuevo }
        return opciones?.participantes.first { $0.valor == p.quien }?.etiqueta.components(separatedBy: " (").first ?? "¿Quién?"
    }

    private func dinero(_ centavos: Int) -> String { Formato.dinero(Double(centavos) / 100) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { lector in
            Form {
                Section("¿Qué celebraron?") {
                    TextField("Nombre (ej. Cumpleaños de Rocío)", text: $nombre); ErrorCampo(texto: errores["nombre"])
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date); ErrorCampo(texto: errores["fecha"])
                    TextField("Lugar (opcional)", text: $lugar)
                }
                Section {
                    ForEach($personas) { $p in
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Persona", selection: $p.quien) {
                                Text("Elegir…").tag("")
                                ForEach(opciones?.participantes ?? [], id: \.valor) { Text($0.etiqueta).tag($0.valor) }
                                Text("+ Nuevo contacto…").tag(Self.nuevo)
                            }
                            if p.quien == Self.nuevo { TextField("Nombre del nuevo contacto", text: $p.nuevo) }
                            Toggle("Festejado", isOn: $p.festejado)
                            Button { pagador = p.id } label: {
                                Label("Pagó la cuenta", systemImage: pagador == p.id ? "largecircle.fill.circle" : "circle")
                            }.buttonStyle(.borderless)
                        }
                    }
                    .onDelete { indices in
                        let quitados = indices.map { personas[$0].id }
                        personas.remove(atOffsets: indices)
                        for i in productos.indices { quitados.forEach { productos[i].cant[$0] = nil } }
                        if let pagador, quitados.contains(pagador) { self.pagador = personas.first?.id }
                    }
                    Button { personas.append(FilaPersona(id: siguiente, quien: "")); siguiente += 1 } label: { Label("Agregar persona", systemImage: "plus") }
                    ErrorCampo(texto: errores["participantes"])
                } header: { Text("¿Quiénes estuvieron?") } footer: { Text("Un festejado no paga: lo suyo se reparte entre los demás. Desliza para quitar.") }

                Section {
                    ForEach($productos) { $c in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("Producto", text: $c.descripcion)
                                CampoMonto(etiqueta: c.compartido ? "Precio total" : "Precio", valor: $c.precio).frame(width: 110)
                            }
                            HStack {
                                Toggle("Compartido", isOn: Binding(get: { c.compartido }, set: { valor in
                                    c.compartido = valor
                                    if valor && personas.allSatisfy({ c.cantidad($0.id) == 0 }) { c.cant = todosComieron() }
                                })).font(.caption).fixedSize()
                                Spacer()
                                if c.compartido { Button("Todos comieron") { c.cant = todosComieron() }.font(.caption).buttonStyle(.borderless) }
                            }
                        }
                    }
                    .onDelete { productos.remove(atOffsets: $0) }
                    Button { productos.append(FilaProducto(id: siguiente)); siguiente += 1 } label: { Label("Agregar producto", systemImage: "plus") }
                } header: { Text("Productos") } footer: { Text("Con su precio, como en la cuenta (ej. Corona $2.50). Si comieron de un mismo plato (ej. una bandeja), márcalo como compartido: pon su precio total y un 1 a cada quien comió (2 si comió el doble). Desliza para quitar.") }

                // Como la hoja: una fila por persona, una columna por producto; en cada celda, cuántos pidió
                Section {
                    tabla
                    ErrorCampo(texto: errores["consumos"])
                } header: { Text("¿Cuántos pidió cada uno?") }
                .id("tabla")

                Section("Propina") {
                    Picker("Propina", selection: $propinaTipo) {
                        Text("Sin propina").tag("ninguna"); Text("Porcentaje del total de cada uno").tag("porcentaje"); Text("Monto fijo dividido entre todos").tag("monto")
                    }
                    if hayPropina {
                        TextField(propinaTipo == "porcentaje" ? "Porcentaje (%)" : "Monto ($)", text: $propinaValor).keyboardType(.decimalPad)
                        ErrorCampo(texto: errores["propina_valor"])
                    }
                }

                Section {
                    if let fotoNueva, let imagen = UIImage(data: fotoNueva) {
                        Image(uiImage: imagen).resizable().scaledToFit().frame(maxHeight: 260)
                    } else if let url = evento?.fotoUrl, !quitarFoto {
                        FotoPrivada(url: url).frame(maxHeight: 260)
                    }
                    PhotosPicker(tieneFoto ? "Cambiar foto" : "Elegir foto", selection: $elegida, matching: .images)
                    if tieneFoto { Button("Quitar foto", role: .destructive) { fotoNueva = nil; quitarFoto = true } }
                } header: { Text("Foto de la cuenta (opcional)") } footer: { Text("Se comparte junto con la tabla, para que todos vean el total del restaurante.") }

                if pagaElHogar {
                    Section {
                        Picker("Pagado desde", selection: $origen) { ForEach(opciones?.origenes ?? [], id: \.valor) { Text($0.etiqueta).tag($0.valor) } }
                        if origen != "ninguno" {
                            Picker("Categoría del gasto", selection: $categoriaId) {
                                Text("Elegir…").tag(nil as Int?)
                                ForEach(comunes.categoriasDe("egreso")) { Text($0.nombre).tag($0.id as Int?) }
                            }
                            ErrorCampo(texto: errores["categoria_personal_id"])
                        }
                    } header: { Text("¿Con qué se pagó la cuenta?") } footer: { Text("Un solo movimiento por el total. Lo de cada contacto queda en \"Nos deben\" y, al cobrarle, el dinero entra solo.") }
                } else {
                    Section { Text("Pagó otra persona: en el evento podrás marcar quién ya le pagó (y registrar tu parte).").font(.callout).foregroundStyle(.secondary) }
                }

                Section {
                    FilaValor(etiqueta: "Consumo", valor: dinero(reparto.subtotal))
                    FilaValor(etiqueta: "Propina", valor: dinero(reparto.propina))
                    FilaValor(etiqueta: "Total", valor: dinero(reparto.total), negrita: true)
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(evento == nil ? "Nuevo evento" : "Editar evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando || !listo) }
            }
            .task {
                await preparar()
                #if DEBUG
                if ArranqueDebug.hoja == "editar:tabla" { try? await Task.sleep(for: .milliseconds(400)); withAnimation { lector.scrollTo("tabla", anchor: .top) } }
                #endif
            }
            .onChange(of: elegida) { _, item in
                guard let item else { return }
                Task {
                    if let datos = try? await item.loadTransferable(type: Data.self), let jpeg = Imagen.reducida(datos) { fotoNueva = jpeg; quitarFoto = false }
                    else { error = "No se pudo leer la foto." }
                    elegida = nil
                }
            }
            .alert("¿Registrar de todas formas?", isPresented: Binding(get: { pregunta != nil }, set: { if !$0 { pregunta = nil } })) {
                Button("Cancelar", role: .cancel) {}
                Button("Sí, registrar") { Task { await guardar(confirmado: true) } }
            } message: { Text(pregunta ?? "") }
            }
        }
    }

    /// La tabla: nombres fijos a la izquierda; productos y columnas calculadas se desplazan a lo ancho.
    private var tabla: some View {
        let r = reparto
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: Self.altoFila + 8)
                ForEach(personas) { p in
                    Text(nombre(p) + (p.festejado ? " 🎂" : "")).font(.caption).lineLimit(2).frame(width: Self.anchoNombre, height: Self.altoFila, alignment: .leading)
                }
                Text("Total").font(.caption.bold()).frame(width: Self.anchoNombre, height: Self.altoFila, alignment: .leading)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach($productos) { $c in
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.descripcion.isEmpty ? "Producto" : c.descripcion).font(.caption2).lineLimit(2)
                                Text(Formato.dinero(c.precio) + (c.compartido ? " ÷" : "")).font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: Self.anchoProducto - 6, height: Self.altoFila + 8, alignment: .bottomLeading)
                            let montos = c.compartido ? CalculoEvento.montos(producto(c), personas.map(\.id)) : [:]
                            ForEach(personas) { p in
                                TextField("0", text: Binding(get: { c.cant[p.id] ?? "" }, set: { c.cant[p.id] = String($0.filter(\.isNumber).prefix(3)) }))
                                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                                    .frame(width: Self.anchoProducto - 10, height: Self.altoFila - 8)
                                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator)))
                                    .overlay(alignment: .bottom) {
                                        // Producto compartido: lo que le toca de él
                                        if let m = montos[p.id] { Text(Formato.dinero(Double(m) / 100)).font(.system(size: 9)).foregroundStyle(.secondary).padding(.bottom, 1) }
                                    }
                                    .frame(width: Self.anchoProducto, height: Self.altoFila)
                            }
                            let suma = personas.reduce(0) { $0 + c.cantidad($1.id) }
                            Text(suma > 0 ? "\(suma)" : "").font(.caption.bold()).frame(width: Self.anchoProducto, height: Self.altoFila)
                        }
                    }
                    resumen("Total", personas.map { r.por[$0.id]?.consumo }, r.subtotal)
                    if hayPropina {
                        resumen("Propina", personas.map { r.por[$0.id]?.propina }, r.propina)
                        resumen("Con propina", personas.map { r.por[$0.id].map { $0.consumo + $0.propina } }, r.total)
                    }
                    if hayFestejo { resumen("Cumpleañero", personas.map { $0.festejado ? nil : r.por[$0.id]?.festejo }, r.festejo) }
                    resumen("A pagar", personas.map { $0.festejado ? nil : r.por[$0.id]?.total }, r.total, negrita: true)
                }
            }
        }
    }

    private func resumen(_ titulo: String, _ valores: [Int?], _ total: Int, negrita: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(titulo).font(.caption2.bold()).frame(width: Self.anchoResumen, height: Self.altoFila + 8, alignment: .bottomTrailing)
            ForEach(Array(valores.enumerated()), id: \.offset) { _, v in
                Text(v.map(dinero) ?? "—").font(negrita ? .caption.bold() : .caption).frame(width: Self.anchoResumen, height: Self.altoFila, alignment: .trailing)
            }
            Text(dinero(total)).font(.caption.bold()).frame(width: Self.anchoResumen, height: Self.altoFila, alignment: .trailing)
        }
    }

    private func preparar() async {
        guard !listo else { return }
        await comunes.cargar()
        opciones = (try? await API.shared.get("/eventos/opciones") as Envoltura<OpcionesEvento>)?.data
        origen = opciones?.origenes.first?.valor ?? "efectivo"
        if let e = evento {
            nombre = e.nombre; fecha = Formato.fechaLocal(e.fecha); lugar = e.lugar ?? ""
            personas = e.participantes.map { FilaPersona(id: $0.id, quien: $0.quien, festejado: $0.esFestejado) }
            pagador = e.pagador?.id
            let ids = e.participantes.map(\.id)
            productos = e.consumos.map { c in
                FilaProducto(id: -c.id, descripcion: c.descripcion, precio: c.precio, compartido: c.compartido,
                             cant: Dictionary(uniqueKeysWithValues: zip(ids, c.cantidades).filter { $0.1 > 0 }.map { ($0.0, String($0.1)) }))
            }
            propinaTipo = e.propinaTipo; propinaValor = e.propinaTipo == "ninguna" ? "" : e.propinaValor
            origen = e.origenValor ?? origen; categoriaId = e.categoriaPersonalId
        } else {
            personas = [FilaPersona(id: 1, quien: comunes.usuario.map { "miembro:\($0.id)" } ?? "")]
            pagador = 1
            productos = [FilaProducto(id: 2)]
        }
        listo = true
    }

    private func quien(_ p: FilaPersona) -> String {
        let n = p.nuevo.trimmingCharacters(in: .whitespaces)
        return p.quien == Self.nuevo ? (n.isEmpty ? "" : "nuevo:\(n)") : p.quien
    }

    private func guardar(confirmado: Bool = false) async {
        var e: [String: String] = [:]
        if nombre.trimmingCharacters(in: .whitespaces).isEmpty { e["nombre"] = "Escribe el nombre del evento." }
        if personas.contains(where: { quien($0).isEmpty }) { e["participantes"] = "Elige a cada persona (o escribe el nombre del nuevo contacto)." }
        if !personas.isEmpty && personas.allSatisfy(\.festejado) { e["participantes"] = "Al menos una persona debe pagar: no pueden ser todos festejados." }
        if productos.isEmpty || productos.contains(where: { $0.descripcion.trimmingCharacters(in: .whitespaces).isEmpty || !Formato.montoValido($0.precio) }) {
            e["consumos"] = "Cada producto necesita nombre y precio."
        } else if let vacio = productos.first(where: { p in personas.allSatisfy { p.cantidad($0.id) == 0 } }) {
            e["consumos"] = vacio.compartido ? "Nadie comió de «\(vacio.descripcion)»: marca a quienes lo compartieron o quítalo." : "Nadie pidió «\(vacio.descripcion)»: anota cuántos pidió cada uno o quítalo."
        }
        if pagaElHogar && origen != "ninguno" && categoriaId == nil { e["categoria_personal_id"] = "Elige la categoría del gasto." }
        errores = e
        guard e.isEmpty else { return }

        let posicion = personas.map(\.id)
        let cuerpo = EventoCuerpo(
            nombre: nombre.trimmingCharacters(in: .whitespaces), fecha: Formato.textoLocal(fecha), lugar: lugar.isEmpty ? nil : lugar,
            propinaTipo: propinaTipo, propinaValor: hayPropina ? propinaValor : nil,
            participantes: personas.map { ParticipanteEventoCuerpo(quien: quien($0), esFestejado: $0.festejado) },
            pagador: posicion.firstIndex(of: pagador ?? -1) ?? 0,
            consumos: productos.map { c in ConsumoEventoCuerpo(descripcion: c.descripcion.trimmingCharacters(in: .whitespaces), precio: c.precio, compartido: c.compartido, cantidades: posicion.map { c.cantidad($0) }) },
            origen: pagaElHogar ? origen : nil, categoriaPersonalId: pagaElHogar && origen != "ninguno" ? categoriaId : nil,
            confirmar: confirmado ? true : nil
        )
        guardando = true
        defer { guardando = false }
        do {
            var r: Envoltura<Evento> = evento == nil ? try await API.shared.post("/eventos", cuerpo) : try await API.shared.put("/eventos/\(evento!.id)", cuerpo)
            // La foto de la cuenta va aparte (multipart); si falla, el evento ya quedó guardado
            do {
                if let fotoNueva {
                    r = try await API.shared.subir("/eventos/\(r.data.id)/foto", campos: [:], archivo: "foto", datos: fotoNueva)
                } else if quitarFoto && evento?.fotoUrl != nil {
                    r = try await API.shared.borrarDevolviendo("/eventos/\(r.data.id)/foto")
                }
            } catch { self.error = "El evento se guardó, pero la foto no: \(error.localizedDescription)" }
            alGuardar(r.data); cerrar()
        } catch let f as FallaAPI {
            if let p = f.campos["confirmar"] { pregunta = p } else { errores = f.campos; error = f.mensaje }
        } catch { self.error = error.localizedDescription }
    }
}

/// Una imagen privada de la API (con el token), ajustada al ancho.
struct FotoPrivada: View {
    let url: String
    @State private var imagen: UIImage?

    var body: some View {
        Group {
            if let imagen { Image(uiImage: imagen).resizable().scaledToFit() } else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
        }
        .task(id: url) { imagen = await API.shared.imagen(url).flatMap(UIImage.init(data:)) }
    }
}

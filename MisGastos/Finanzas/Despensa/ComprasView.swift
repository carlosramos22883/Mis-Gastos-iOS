import SwiftUI

/// Listas de compras: la abierta (o crear una con lo que falta) y el historial.
struct ComprasView: View {
    @State private var compras: Compras?
    @State private var cargando = true
    @State private var error: String?
    @State private var aviso: String?
    @State private var creando = false
    @State private var abrir: Int?

    var body: some View {
        List {
            if cargando && compras == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, compras == nil {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else if let c = compras {
                Section {
                    if let a = c.abierta {
                        NavigationLink(value: RutaDespensa.lista(a.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.nombre).font(.headline)
                                Text("\(a.compradosCount ?? 0) de \(a.itemsCount ?? 0) en el carrito" + (a.resumen.map { " · " + Formato.dinero($0.total) } ?? "")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(c.faltan > 0 ? "En tu despensa faltan \(c.faltan) \(c.faltan == 1 ? "producto" : "productos"): la lista nueva los trae solos."
                             : "No falta nada en la despensa. Puedes armar la lista a mano.").font(.callout).foregroundStyle(.secondary)
                        Button(creando ? "Creando…" : "Nueva lista de compras") { Task { await nueva() } }.disabled(creando)
                    }
                }
                if !c.historial.isEmpty {
                    Section("Historial") {
                        ForEach(c.historial) { l in
                            NavigationLink(value: RutaDespensa.lista(l.id)) {
                                VStack(alignment: .leading) {
                                    Text(l.nombre)
                                    Text("\(l.compradosCount ?? 0) de \(l.itemsCount ?? 0) comprados · \(Formato.fechaCorta(l.terminadaAt))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Lista de compras")
        .task { await cargar() }
        .refreshable { await cargar() }
        .navigationDestination(item: $abrir) { ListaCompraView(id: $0) }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func cargar() async {
        do { compras = try await API.shared.get("/compras"); error = nil } catch { self.error = error.localizedDescription }
        cargando = false
    }

    private func nueva() async {
        creando = true
        defer { creando = false }
        do { let r: Envoltura<ListaCompra> = try await API.shared.post("/compras", Vacio()); abrir = r.data.id; await cargar() } catch { aviso = error.localizedDescription }
    }
}

/// Una lista: tienda donde se está, carrito con precios, «No había», pagar aquí, consultar precios en línea y ruta.
struct ListaCompraView: View {
    let id: Int
    @Environment(\.dismiss) private var cerrar
    @State private var lista: ListaCompra?
    @State private var tiendas: [Tienda] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var aviso: String?
    @State private var enviando: Int?
    @State private var avance: String?
    @State private var agregando = false
    @State private var precioDe: ItemLista?
    @State private var precioTexto = ""
    @State private var pago: DatosPago?
    @State private var ruta: RutaCompra?
    @State private var confirmarTerminar = false
    @State private var confirmarEliminar = false
    @State private var deshacer: Int?

    var body: some View {
        List {
            if cargando && lista == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error, lista == nil {
                ErrorConReintento(mensaje: error) { Task { await cargar() } }
            } else if let l = lista {
                if l.abierta { cabecera(l) }
                if let p = l.pendientes, !p.isEmpty {
                    Section(l.abierta ? "Por comprar" : "No se compró") { ForEach(p) { fila($0, l) } }
                }
                if let c = l.comprados, !c.isEmpty {
                    Section(l.abierta ? "En el carrito" : "Comprado") { ForEach(c) { fila($0, l) } }
                }
                if (l.pendientes ?? []).isEmpty && (l.comprados ?? []).isEmpty { Text("La lista está vacía. Agrega lo que quieres comprar.").foregroundStyle(.secondary) }
                if let pagos = l.pagos, !pagos.isEmpty {
                    Section("Pagos") {
                        ForEach(pagos) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Formato.dinero(p.total)) en \(p.tienda ?? "una tienda")").fontWeight(.semibold)
                                    Text("\(Formato.fechaCorta(p.fecha)) · \(p.origenNombre)").font(.caption).foregroundStyle(.secondary)
                                    Text(p.gastos.map { "\($0.categoria ?? "Sin categoría") \(Formato.dinero($0.monto))" }.joined(separator: " · ")).font(.caption)
                                }
                                Spacer()
                                if l.abierta { Button("Deshacer", role: .destructive) { deshacer = p.id }.buttonStyle(.borderless) }
                            }
                        }
                    }
                }
                Section {
                    if l.abierta {
                        Button("Agregar a la lista") { agregando = true }
                        Button("Agregar lo que falta") { Task { await accion { try await API.shared.post("/compras/\(id)/faltantes", Vacio()) } } }
                        Button("Terminar compra") { confirmarTerminar = true }.fontWeight(.semibold)
                    }
                    Button("Eliminar lista", role: .destructive) { confirmarEliminar = true }
                }
            }
        }
        .navigationTitle(lista?.nombre ?? "Lista de compras").navigationBarTitleDisplayMode(.inline)
        .task {
            await cargar()
            #if DEBUG
            if ArranqueDebug.hoja == "pagar" { await abrirPago() }
            if ArranqueDebug.hoja == "ruta" { await abrirRuta() }
            #endif
        }
        .refreshable { await cargar() }
        .sheet(isPresented: $agregando) { HojaAgregar { body in await agregar(body) } }
        .sheet(item: $pago) { d in HojaPagar(listaId: id, datos: d) { nueva in lista = nueva; aviso = "Pago registrado." } }
        .sheet(item: $ruta) { r in HojaRuta(listaId: id, inicial: r, tiendas: tiendas) { t in Task { await elegirTienda(t) } } }
        .alert("Precio c/u", isPresented: Binding(get: { precioDe != nil }, set: { if !$0 { precioDe = nil } })) {
            TextField("0.00", text: $precioTexto).keyboardType(.decimalPad)
            Button("Guardar") { if let i = precioDe { Task { await cambiar(i, ItemCambio(precio: precioTexto)) } } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Terminar la compra?", isPresented: $confirmarTerminar, titleVisibility: .visible) {
            Button("Terminar") { Task { await terminar() } }
        } message: {
            let n = lista?.resumen?.porPagar ?? 0
            Text((n > 0 ? "Aún no has pagado \(n) \(n == 1 ? "cosa" : "cosas") del carrito: si terminas, no se registrará su gasto. " : "") + "Lo del carrito se sumará a tu despensa; lo demás queda como no comprado.")
        }
        .confirmationDialog("¿Eliminar la lista?", isPresented: $confirmarEliminar, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { Task { do { try await API.shared.borrar("/compras/\(id)"); cerrar() } catch { aviso = error.localizedDescription } } }
        } message: { Text("Si tiene pagos, sus gastos quedan como movimientos normales.") }
        .confirmationDialog("¿Deshacer este pago?", isPresented: Binding(get: { deshacer != nil }, set: { if !$0 { deshacer = nil } }), titleVisibility: .visible) {
            Button("Deshacer", role: .destructive) { if let p = deshacer { Task { await accion { try await API.shared.borrarDevolviendo("/compras/\(id)/pagos/\(p)") }; aviso = "Pago deshecho." } } }
        } message: { Text("Se eliminan sus gastos y lo comprado vuelve al carrito sin pagar. Los extras se quitan de la lista.") }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func cabecera(_ l: ListaCompra) -> some View {
        Section {
            if tiendas.isEmpty {
                Text("Para anotar precios y lo que no había, agrega tus tiendas (Despensa → Tiendas).").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("¿En qué tienda estás?", selection: Binding(get: { l.tiendaActualId }, set: { t in Task { await elegirTienda(t) } })) {
                    Text("Elige la tienda…").tag(Int?.none)
                    ForEach(tiendas) { Text($0.nombre).tag(Optional($0.id)) }
                }
            }
            if let r = l.resumen {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(r.enCarrito) de \(r.totalItems) en el carrito").font(.caption).foregroundStyle(.secondary)
                        if r.sinPrecio > 0 { Text(r.sinPrecio == 1 ? "1 sin precio" : "\(r.sinPrecio) sin precio").font(.caption).foregroundStyle(Semantica.aviso) }
                        if (Double(r.pagado) ?? 0) > 0 { Text("Pagado: \(Formato.dinero(r.pagado))").font(.caption).foregroundStyle(Semantica.ingreso) }
                    }
                    Spacer()
                    Text(Formato.dinero(r.total)).font(.title2.bold())
                }
                if l.tiendaActualId != nil {
                    Button(r.porPagar > 0 ? "Pagar aquí · \(Formato.dinero(r.porPagarTotal))" : "Registrar un pago aquí") { Task { await abrirPago() } }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                }
            }
            Text(avance ?? (l.consultasRestantes.map { $0 == 1 ? "Precios en línea: te queda 1 consulta hoy." : "Precios en línea: te quedan \($0) consultas hoy." } ?? ""))
                .font(.caption).foregroundStyle(avance != nil ? Color.accentColor : .secondary)
            HStack {
                Button("Consultar precios") { Task { await consultarPrecios() } }.disabled(avance != nil || !tiendas.contains { $0.fuente != nil })
                Spacer()
                Button("Ruta de compra") { Task { await abrirRuta() } }
            }.buttonStyle(.borderless)
        }
    }

    private func fila(_ item: ItemLista, _ l: ListaCompra) -> some View {
        let editable = l.abierta && !item.pagado
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { Task { await cambiar(item, ItemCambio(comprado: !item.comprado)) } } label: {
                    Image(systemName: item.comprado ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(item.comprado ? Semantica.ingreso : .secondary)
                }.buttonStyle(.borderless).disabled(!editable || enviando == item.id).accessibilityLabel(item.comprado ? "Sacar del carrito" : "Al carrito")
                Avatar(url: item.fotoUrl, nombre: item.descripcion, tamano: 44, cuadrado: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.descripcion).strikethrough(item.comprado)
                    Text([item.categoria ?? (item.extra ? "Extra" : "Anotado"), item.automatico ? "faltaba" : nil, item.basico ? "básico" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let n = item.noHabia { Text(n).font(.caption.weight(.medium)).foregroundStyle(Semantica.aviso) }
                    if item.pagado { Insignia(texto: "Pagado", color: Semantica.ingreso) }
                }
                Spacer()
                if editable {
                    Stepper("\(item.cantidad)", value: Binding(get: { item.cantidad }, set: { n in Task { await cambiar(item, ItemCambio(cantidad: n)) } }), in: 1...999).fixedSize()
                } else { Text("× \(item.cantidad)").fontWeight(.semibold) }
            }
            if item.comprado {
                Button {
                    precioTexto = item.precio ?? ""; precioDe = item
                } label: {
                    Text(item.precio.map { "Precio c/u \(Formato.dinero($0))" + (item.subtotal.map { " = \(Formato.dinero($0))" } ?? "") } ?? "Sin precio: tocar para escribirlo")
                        + Text(item.tienda.map { " · en \($0)" } ?? "").foregroundColor(.secondary)
                }.buttonStyle(.borderless).disabled(!editable).font(.callout)
            }
            if !item.comprado && !item.comparacion.isEmpty {
                ForEach(Array(item.comparacion.enumerated()), id: \.offset) { i, c in
                    let mejor = i == 0 && item.comparacion.count > 1
                    HStack {
                        Text(c.tienda).lineLimit(1)
                        Spacer()
                        Text("\(Formato.dinero(c.porUnidad))  \(c.cuando)").foregroundStyle(c.viejo ? Semantica.aviso : .secondary)
                    }
                    .font(.caption.weight(mejor ? .semibold : .regular)).foregroundStyle(mejor ? Semantica.ingreso : .secondary)
                }
            }
        }
        .swipeActions {
            if editable {
                Button("Quitar", role: .destructive) { Task { await accion { try await API.shared.borrarDevolviendo("/compras/\(id)/items/\(item.id)") } } }
                if !item.comprado && l.tiendaActualId != nil {
                    Button(item.noHabia != nil ? "Sí había" : "No había") { Task { await cambiar(item, ItemCambio(noHabia: item.noHabia == nil)) } }.tint(.orange)
                }
            }
        }
    }

    // MARK: - Datos

    private func cargar() async {
        if let t: Envoltura<[Tienda]> = try? await API.shared.get("/tiendas") { tiendas = t.data.filter(\.activo) }
        do { let r: Envoltura<ListaCompra> = try await API.shared.get("/compras/\(id)"); lista = r.data; error = nil } catch { self.error = error.localizedDescription }
        cargando = false
    }

    /// Ejecuta una acción que devuelve la lista actualizada.
    private func accion(_ hacer: () async throws -> Envoltura<ListaCompra>) async {
        do { lista = try await hacer().data } catch { aviso = error.localizedDescription }
    }

    private func cambiar(_ item: ItemLista, _ cambio: ItemCambio) async {
        enviando = item.id
        defer { enviando = nil }
        await accion { try await API.shared.patch("/compras/\(id)/items/\(item.id)", cambio) }
    }

    private func elegirTienda(_ t: Int?) async { await accion { try await API.shared.patch("/compras/\(id)/tienda", TiendaActualBody(tiendaId: t)) } }

    private func agregar(_ body: ItemBody) async -> String? {
        do { let r: Envoltura<ListaCompra> = try await API.shared.post("/compras/\(id)/items", body); lista = r.data; return nil } catch { return error.localizedDescription }
    }

    private func terminar() async {
        await accion { try await API.shared.post("/compras/\(id)/terminar", Vacio()) }
        aviso = "Compra terminada: lo comprado subió en tu despensa."
    }

    private func abrirPago() async {
        do { pago = try await API.shared.get("/compras/\(id)/pagar") } catch { aviso = error.localizedDescription }
    }

    private func abrirRuta() async {
        do { ruta = try await API.shared.get("/compras/\(id)/ruta") } catch { aviso = error.localizedDescription }
    }

    /// Pide los precios de uno en uno; el servidor dice cuánto esperar entre cada uno.
    private func consultarPrecios() async {
        avance = "Empezando…"
        defer { avance = nil }
        do {
            let inicio: InicioConsulta = try await API.shared.post("/compras/\(id)/consultas", Vacio())
            guard !inicio.alDia, let cid = inicio.consultaId, var e = inicio.estado else { aviso = inicio.message ?? "Los precios ya son de hoy."; return }
            while !e.terminada {
                avance = "Consultando \(min(e.hechos + 1, e.total)) de \(e.total)…"
                e = try await API.shared.post("/compras/\(id)/consultas/\(cid)/siguiente", Vacio())
                try await Task.sleep(for: .milliseconds(e.espera ?? 2100))
            }
            aviso = [e.nuevos > 0 ? (e.nuevos == 1 ? "Se leyó 1 precio." : "Se leyeron \(e.nuevos) precios.") : nil,
                     e.reusados > 0 ? (e.reusados == 1 ? "1 ya era de hoy." : "\(e.reusados) ya eran de hoy.") : nil,
                     e.fallas > 0 ? (e.fallas == 1 ? "1 no se pudo leer." : "\(e.fallas) no se pudieron leer.") : nil].compactMap { $0 }.joined(separator: " ").ifEmpty("Listo.")
            await cargar()
        } catch { aviso = error.localizedDescription }
    }
}

/// Agregar un producto de la despensa o anotar algo que no está en ella.
private struct HojaAgregar: View {
    let agregar: (ItemBody) async -> String?
    @Environment(\.dismiss) private var cerrar
    @State private var productos: [Producto] = []
    @State private var producto: Int?
    @State private var texto = ""
    @State private var cantidad = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("De tu despensa", selection: $producto) {
                    Text("—").tag(Int?.none)
                    ForEach(productos) { Text($0.nombreCompleto).tag(Optional($0.id)) }
                }
                Section("O anota algo que no está en tu despensa") { TextField("Ej. Piñata para el cumpleaños", text: $texto) }
                TextField("Cantidad", text: $cantidad).keyboardType(.numberPad)
                ErrorCampo(texto: error)
            }
            .navigationTitle("Agregar a la lista").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") {
                        let body = producto != nil ? ItemBody(productoId: producto, cantidad: Int(cantidad)) : ItemBody(descripcion: texto.trimmingCharacters(in: .whitespaces), cantidad: Int(cantidad))
                        Task { error = await agregar(body); if error == nil { cerrar() } }
                    }.disabled(producto == nil && texto.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { if let r: ListaProductos = try? await API.shared.get("/productos") { productos = r.data.filter(\.activo) } }
        }
    }
}

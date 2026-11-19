import SwiftUI

/// «Pagar aquí»: lo del carrito en la tienda elegida (total sugerido y editable), los extras (un solo total o cada cosa con su
/// categoría, elegida o nueva) y con qué se paga. Se registra un gasto por categoría; si una pasa su presupuesto se decide
/// (cubrir o pasarme) y se reenvía con la decisión de esa categoría.
struct HojaPagar: View {
    let listaId: Int
    let datos: DatosPago
    let alPagar: (ListaCompra) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var montoLista = ""
    @State private var categoria = ""
    @State private var nuevaCategoria = ""
    @State private var modo = "ninguno"
    @State private var extrasTotal = ""
    @State private var extrasCategoria = ""
    @State private var extrasNueva = ""
    @State private var filas: [Fila] = [Fila()]
    @State private var origen = ""
    @State private var fecha = Date()
    @State private var pagando = false
    @State private var error: String?
    @State private var campos: [String: String] = [:]
    @State private var exceso: ExcesoPresupuesto?
    @State private var sobregiro: String?
    @State private var decisiones: [String: DecisionBody] = [:]
    @State private var iniciado = false

    struct Fila: Identifiable { let id = UUID(); var descripcion = ""; var precio = ""; var categoria = ""; var nueva = "" }

    private var hayItems: Bool { !datos.items.isEmpty }
    private func num(_ t: String) -> Double { Double(t) ?? 0 }
    private var total: Double {
        (hayItems ? num(montoLista) : 0) + (modo == "total" ? num(extrasTotal) : modo == "detalle" ? filas.reduce(0) { $0 + num($1.precio) } : 0)
    }
    /// id de la categoría o "nueva:Nombre" (el aviso de presupuesto devuelve su clave ya en minúsculas).
    private func clave(_ sel: String, _ nueva: String) -> String {
        sel == "__nueva" ? (nueva.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "nueva:" + nueva.trimmingCharacters(in: .whitespaces)) : sel
    }

    var body: some View {
        NavigationStack {
            Form {
                if hayItems {
                    Section {
                        ForEach(datos.items) { i in
                            HStack {
                                Text("\(i.descripcion) × \(i.cantidad)").font(.callout)
                                Spacer()
                                Text(i.subtotal.map { Formato.dinero($0) } ?? "sin precio").font(.callout).foregroundStyle(i.subtotal == nil ? Semantica.aviso : .primary)
                            }
                        }
                        LabeledContent("Suma de lo anotado", value: Formato.dinero(datos.total))
                        if datos.sinPrecio > 0 { Text("\(datos.sinPrecio) sin precio: escribe abajo el total del ticket.").font(.caption).foregroundStyle(Semantica.aviso) }
                        CampoMonto(etiqueta: "Total de lo de la lista", valor: $montoLista, error: campos["monto_lista"])
                        selectorCategoria("Categoría", $categoria, $nuevaCategoria, campos["categoria"])
                    } header: { Text("Lo de la lista") } footer: { Text("Si el ticket dice otra cosa, escribe lo del ticket.") }
                } else {
                    Text("No hay nada del carrito por pagar aquí. Puedes registrar solo los extras.").foregroundStyle(.secondary)
                }
                Section("¿Compraste algo que no estaba en la lista?") {
                    Picker("Extras", selection: $modo) { Text("No").tag("ninguno"); Text("Un solo total").tag("total"); Text("Cada cosa").tag("detalle") }.pickerStyle(.segmented)
                    if modo == "total" {
                        CampoMonto(etiqueta: "Total de lo extra", valor: $extrasTotal, error: campos["extras_total"])
                        selectorCategoria("Categoría de lo extra", $extrasCategoria, $extrasNueva, campos["extras_categoria"])
                    }
                    if modo == "detalle" {
                        ForEach($filas) { $f in
                            VStack(alignment: .leading) {
                                HStack {
                                    TextField("¿Qué fue? Ej. Jalea", text: $f.descripcion)
                                    CampoMonto(etiqueta: "Precio", valor: $f.precio).frame(width: 110)
                                }
                                selectorCategoria("Categoría", $f.categoria, $f.nueva, nil)
                                if filas.count > 1 { Button("Quitar", role: .destructive) { filas.removeAll { $0.id == f.id } }.buttonStyle(.borderless).font(.caption) }
                            }
                        }
                        Button("+ Otra cosa") { filas.append(Fila()) }
                        ErrorCampo(texto: campos.first { $0.key.hasPrefix("extras.") }?.value)
                    }
                }
                Section {
                    LabeledContent("Total a pagar") { Text(Formato.dinero(total)).font(.title3.bold()) }
                    Picker("¿Con qué pagas?", selection: $origen) { ForEach(datos.origenes, id: \.clave) { Text($0.nombre).tag($0.clave) } }
                    ErrorCampo(texto: campos["origen"] ?? campos["monto"])
                    DatePicker("Fecha", selection: $fecha, in: Formato.fechaLocal(datos.ciclo.inicio)...min(Date(), Formato.fechaLocal(datos.ciclo.fin)), displayedComponents: .date)
                    ErrorCampo(texto: campos["fecha"])
                } footer: { Text("Se registra un gasto por cada categoría, con las reglas de siempre (saldo, disponible y presupuesto).") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Pagar en \(datos.tienda.nombre)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button(pagando ? "Pagando…" : "Pagar") { Task { await pagar() } }.disabled(pagando || total <= 0) }
            }
            .onAppear {
                guard !iniciado else { return }
                iniciado = true
                montoLista = hayItems ? datos.total : ""
                categoria = datos.categoriaSugerida.map(String.init) ?? ""
                origen = datos.origenes.first?.clave ?? ""
            }
            .sheet(item: $exceso) { e in
                HojaCubrirPresupuesto(exceso: e) { d in
                    if let c = e.clave { decisiones[c] = DecisionBody(modo: d.modo, traspasos: d.traspasos) }
                    Task { await pagar() }
                }
            }
            .alert("¿Registrar de todas formas?", isPresented: Binding(get: { sobregiro != nil }, set: { if !$0 { sobregiro = nil } })) {
                Button("Sí, registrar") { Task { await pagar(confirmar: true) } }
                Button("Cancelar", role: .cancel) {}
            } message: { Text(sobregiro ?? "") }
        }
    }

    private func selectorCategoria(_ etiqueta: String, _ sel: Binding<String>, _ nueva: Binding<String>, _ error: String?) -> some View {
        VStack(alignment: .leading) {
            Picker(etiqueta, selection: sel) {
                Text("Elige…").tag("")
                ForEach(datos.categorias, id: \.id) { Text($0.nombre).tag(String($0.id)) }
                Text("+ Nueva categoría…").tag("__nueva")
            }
            if sel.wrappedValue == "__nueva" { TextField("Nombre, ej. Ropa", text: nueva) }
            ErrorCampo(texto: error)
        }
    }

    private func pagar(confirmar: Bool = false) async {
        pagando = true; error = nil; campos = [:]
        defer { pagando = false }
        let usadas = filas.filter { !$0.descripcion.isEmpty || !$0.precio.isEmpty }
        let body = PagoBody(origen: origen, fecha: Formato.texto(fecha),
                            categoria: hayItems ? clave(categoria, nuevaCategoria) : nil, montoLista: hayItems ? montoLista : nil, extrasModo: modo,
                            extrasTotal: modo == "total" ? extrasTotal : nil, extrasCategoria: modo == "total" ? clave(extrasCategoria, extrasNueva) : nil,
                            extras: modo == "detalle" ? usadas.map { ExtraBody(descripcion: $0.descripcion.trimmingCharacters(in: .whitespaces), precio: $0.precio, categoria: clave($0.categoria, $0.nueva)) } : nil,
                            presupuestos: decisiones.isEmpty ? nil : decisiones, confirmar: confirmar ? true : nil)
        do {
            let r: Envoltura<ListaCompra> = try await API.shared.post("/compras/\(listaId)/pagar", body)
            alPagar(r.data); cerrar()
        } catch let f as FallaAPI {
            if let p = f.presupuesto { exceso = p }
            else if Set(f.campos.keys) == ["confirmar"] { sobregiro = f.mensaje }
            else { campos = f.campos; error = f.mensaje }
        } catch { self.error = error.localizedDescription }
    }
}

/// Ruta de compra: en qué tiendas comprar lo que falta, según lo que cuesta ir a una tienda más.
struct HojaRuta: View {
    let listaId: Int
    let inicial: RutaCompra
    let tiendas: [Tienda]
    let estoyAqui: (Int) -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var ruta: RutaCompra?
    @State private var costo = ""
    @AppStorage("ruta-costo") private var costoGuardado = ""

    var body: some View {
        let r = ruta ?? inicial
        NavigationStack {
            List {
                Section {
                    HStack {
                        CampoMonto(etiqueta: "Ir a otra tienda me cuesta", valor: $costo)
                        Button("Recalcular") { Task { await recalcular() } }.buttonStyle(.borderless)
                    }
                } footer: { Text("Gasolina, tiempo, parqueo… Solo conviene ir a otra tienda si te ahorras más que esto.") }
                if r.paradas.isEmpty {
                    Text("Aún no hay precios de lo que falta comprar. Consulta los precios en línea o anótalos en la Despensa.").foregroundStyle(.secondary)
                } else {
                    Section {
                        Text(r.paradas.count == 1 ? "Compra todo en \(r.paradas[0].tienda): \(Formato.dinero(r.total))" : "Ve a \(r.paradas.count) tiendas: \(Formato.dinero(r.total))").font(.headline)
                        if r.paradas.count > 1 && r.ahorro == nil { Text("Ninguna tienda tiene precio de todo: así cubres lo más que se puede.") }
                        if let a = r.ahorro, let u = r.unaTienda { Text("Todo en \(u.tienda) saldría en \(Formato.dinero(u.total)): te ahorras \(Formato.dinero(a)).") }
                        if r.paradas.count == 1 { Text("Ir a otra tienda no te ahorra más de lo que cuesta ir.").foregroundStyle(.secondary) }
                        if r.viejos > 0 { Text("\(r.viejos) \(r.viejos == 1 ? "precio tiene" : "precios tienen") más de 7 días: puede haber cambiado.").font(.caption).foregroundStyle(Semantica.aviso) }
                    }
                    ForEach(r.paradas) { p in
                        Section {
                            ForEach(p.items) { i in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(i.descripcion) × \(i.cantidad)")
                                        Text("\(Formato.dinero(i.porUnidad)) c/u · \(i.cuando ?? "")").font(.caption).foregroundStyle(i.viejo == true ? Semantica.aviso : .secondary)
                                    }
                                    Spacer()
                                    Text(Formato.dinero(i.subtotal)).fontWeight(.semibold)
                                }
                            }
                        } header: {
                            HStack {
                                Text("\(p.tienda) · \(Formato.dinero(p.subtotal))")
                                Spacer()
                                if tiendas.contains(where: { $0.id == p.tiendaId }) { Button("Estoy aquí") { estoyAqui(p.tiendaId); cerrar() }.font(.caption) }
                            }
                        }
                    }
                }
                if !r.sinPrecio.isEmpty {
                    Section("Sin precio") { ForEach(r.sinPrecio) { Text("\($0.descripcion) × \($0.cantidad)") } }
                }
            }
            .navigationTitle("Ruta de compra").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } } }
            .task {
                costo = inicial.costoVisita
                if !costoGuardado.isEmpty && costoGuardado != inicial.costoVisita { costo = costoGuardado; await recalcular() }
            }
        }
    }

    private func recalcular() async {
        costoGuardado = costo
        ruta = try? await API.shared.get("/compras/\(listaId)/ruta", ["costo": costo.isEmpty ? nil : costo])
    }
}

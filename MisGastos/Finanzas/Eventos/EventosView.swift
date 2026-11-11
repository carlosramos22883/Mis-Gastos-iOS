import SwiftUI
import QuickLook

private func num(_ t: String?) -> Double { Double(t ?? "") ?? 0 }

/// Eventos: dividir la cuenta de una comida o celebración.
struct EventosView: View {
    @State private var eventos: [Evento] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var nuevo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if cargando && eventos.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if let error, eventos.isEmpty {
                    ErrorConReintento(mensaje: error) { Task { await cargar() } }
                } else if eventos.isEmpty {
                    Text("¿Salieron a comer? Agrega un evento: quiénes fueron, qué pidió cada uno, la propina y los festejados.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 40)
                } else {
                    Seccion("Resumen") {
                        FilaValor(etiqueta: "Te falta cobrar", valor: Formato.dinero(eventos.reduce(0) { $0 + num($1.porCobrar) }), negrita: true)
                    }
                    ForEach(eventos) { e in
                        NavigationLink(value: Ruta.evento(e.id)) { tarjeta(e) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Semantica.fondo)
        .navigationTitle("Eventos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo evento") }
        }
        .task {
            await cargar()
            #if DEBUG
            if ArranqueDebug.hoja == "nuevo" { nuevo = true }
            #endif
        }
        .refreshable { await cargar() }
        .sheet(isPresented: $nuevo) { FormularioEvento(evento: nil) { _ in Task { await cargar() } } }
    }

    private func tarjeta(_ e: Evento) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(e.nombre).font(.headline)
            Text("\(Formato.fechaCorta(e.fecha))\(e.lugar.map { " · \($0)" } ?? "") · \(e.participantes.count) personas").font(.caption).foregroundStyle(.secondary)
            Text(Formato.dinero(e.total)).font(.title2.bold())
            Text(!e.pagoElHogar ? "Pagó \(e.pagador?.nombre ?? "")" : num(e.porCobrar) > 0 ? "Falta cobrar \(Formato.dinero(e.porCobrar))" : "Todo cobrado")
                .font(.caption).foregroundStyle(e.pagoElHogar && num(e.porCobrar) > 0 ? Semantica.egreso : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Semantica.tarjeta, in: RoundedRectangle(cornerRadius: 12))
    }

    private func cargar() async {
        do {
            let r: Envoltura<[Evento]> = try await API.shared.get("/eventos")
            eventos = r.data; error = nil
        } catch { self.error = error.localizedDescription }
        cargando = false
    }
}

/// Detalle: lo que le toca a cada uno, cobrar (pagó el hogar) o marcar quién ya pagó (pagó otra persona) y compartir la imagen.
struct EventoDetalleView: View {
    let id: Int
    @Environment(\.dismiss) private var cerrar
    @State private var evento: Evento?
    @State private var opciones: OpcionesEvento?
    @State private var error: String?
    @State private var aviso: String?
    @State private var cobro: ParticipanteEvento?
    @State private var pagado: ParticipanteEvento?
    @State private var quitar: ParticipanteEvento?
    @State private var editar = false
    @State private var borrar = false
    @State private var imagen: URL?
    @State private var compartiendo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let e = evento {
                    Seccion("Resumen") {
                        Text("\(Formato.fechaLarga(e.fecha))\(e.lugar.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                        FilaValor(etiqueta: "Pagó la cuenta", valor: e.pagador?.nombre ?? "")
                        FilaValor(etiqueta: "Consumo", valor: Formato.dinero(e.subtotal))
                        FilaValor(etiqueta: "Propina", valor: Formato.dinero(e.propina))
                        FilaValor(etiqueta: "Total", valor: Formato.dinero(e.total), negrita: true)
                        if e.pagoElHogar {
                            FilaValor(etiqueta: "Te falta cobrar", valor: Formato.dinero(e.porCobrar), color: num(e.porCobrar) > 0 ? Semantica.egreso : Semantica.ingreso, negrita: true)
                        }
                    }
                    ForEach(e.participantes) { p in TarjetaParticipante(evento: e, p: p, cobrar: { cobro = p }, yaPago: { pagado = p }, quitar: { quitar = p }) }
                    Seccion("Consumos") {
                        ForEach(e.consumos) { c in
                            FilaValor(etiqueta: "\(c.cantidad) × \(c.descripcion) (\(Formato.dinero(c.precio)))", valor: Formato.dinero(c.total))
                        }
                    }
                    if let url = e.fotoUrl {
                        Seccion("Foto de la cuenta") { FotoPrivada(url: url) }
                    }
                } else if let error {
                    ErrorConReintento(mensaje: error) { Task { await cargar() } }
                } else {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(Semantica.fondo)
        .navigationTitle(evento?.nombre ?? "Evento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if evento != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    if compartiendo { ProgressView() } else {
                        Button { Task { await compartir() } } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Compartir imagen")
                    }
                    Menu {
                        Button("Editar") { editar = true }
                        Button("Eliminar", role: .destructive) { borrar = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task {
            await cargar()
            #if DEBUG
            if ArranqueDebug.hoja?.hasPrefix("editar") == true { editar = true }
            #endif
        }
        .refreshable { await cargar() }
        // Vista previa de la imagen con su botón para compartir (WhatsApp, etc.)
        .quickLookPreview($imagen)
        .sheet(item: $cobro) { p in HojaCobroEvento(eventoId: id, participante: p, destinos: opciones?.destinos ?? []) { evento = $0; aviso = "Pago de \(p.nombre) registrado." } }
        .sheet(item: $pagado) { p in HojaPagadoEvento(eventoId: id, participante: p, pagador: evento?.pagador?.nombre ?? "", origenes: opciones?.origenes ?? []) { evento = $0; aviso = "\(p.nombre) ya pagó su parte." } }
        .sheet(isPresented: $editar) { if let e = evento { FormularioEvento(evento: e) { _ in Task { await cargar() } } } }
        .confirmationDialog("¿Eliminar evento?", isPresented: $borrar, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { Task { await eliminar() } }
        } message: { Text("Se eliminan el evento, su pago y lo que te deben de él.") }
        .confirmationDialog("¿Quitar el pago?", isPresented: Binding(get: { quitar != nil }, set: { if !$0 { quitar = nil } }), titleVisibility: .visible) {
            Button("Quitar", role: .destructive) { if let p = quitar { Task { await desmarcar(p) } } }
        } message: { Text("Se quitará el pago de \(quitar?.nombre ?? "") (y su movimiento, si lo tiene).") }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }

    private func cargar() async {
        await Comunes.shared.cargar()
        do {
            let r: Envoltura<Evento> = try await API.shared.get("/eventos/\(id)")
            evento = r.data; error = nil
            if opciones == nil { opciones = (try? await API.shared.get("/eventos/opciones") as Envoltura<OpcionesEvento>)?.data }
        } catch { self.error = error.localizedDescription }
    }

    private func compartir() async {
        compartiendo = true
        defer { compartiendo = false }
        do { imagen = try await API.shared.descargar("/eventos/\(id)/imagen", [:], nombre: "evento-\(id).png") } catch { aviso = error.localizedDescription }
    }

    private func desmarcar(_ p: ParticipanteEvento) async {
        do {
            let r: Envoltura<Evento> = try await API.shared.borrarDevolviendo("/eventos/\(id)/participantes/\(p.id)/pagado")
            evento = r.data; aviso = "Se quitó el pago de \(p.nombre)."
        } catch { aviso = error.localizedDescription }
    }

    private func eliminar() async {
        do { try await API.shared.borrar("/eventos/\(id)"); cerrar() } catch { aviso = error.localizedDescription }
    }
}

private struct TarjetaParticipante: View {
    let evento: Evento
    let p: ParticipanteEvento
    let cobrar: () -> Void
    let yaPago: () -> Void
    let quitar: () -> Void
    @State private var abierto = false

    var body: some View {
        let (texto, color): (String, Color) = switch p.estado {
        case "pagador": ("Pagó la cuenta", Semantica.info)
        case "festejado": ("Festejado", Semantica.aviso)
        case "hogar": ("Del hogar", .secondary)
        case "pagado": ("Pagado", Semantica.ingreso)
        case "parcial": ("Abonó", Semantica.aviso)
        default: ("Pendiente", Semantica.egreso)
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(p.nombre).font(.headline)
                Spacer()
                Text(Formato.dinero(p.total)).font(.headline)
            }
            HStack {
                Insignia(texto: texto, color: color)
                if p.estado == "parcial" { Text("falta \(Formato.dinero(p.pendiente))").font(.caption) }
            }
            if abierto {
                ForEach(p.detalle, id: \.self) { d in
                    FilaValor(etiqueta: "\(d.cantidad > 1 ? "\(d.cantidad)× " : "")\(d.descripcion)", valor: Formato.dinero(d.monto))
                }
                if num(p.propina) > 0 { FilaValor(etiqueta: "Propina", valor: Formato.dinero(p.propina)) }
                if num(p.festejo) > 0 { FilaValor(etiqueta: "Lo del cumpleañero", valor: Formato.dinero(p.festejo)) }
                ForEach(p.cobros) { c in FilaValor(etiqueta: "Cobro del \(Formato.fechaCorta(c.fecha))", valor: Formato.dinero(c.monto), color: Semantica.ingreso) }
                if let f = p.fechaPago { Text("Pagó el \(Formato.fechaCorta(f))").font(.caption).foregroundStyle(Semantica.ingreso) }
                if let c = p.contacto { NavigationLink("Ver contacto (todo lo que debe)", value: Ruta.contacto(c.id)).font(.caption) }
            }
            if evento.pagoElHogar && p.deudaId != nil && num(p.pendiente) > 0 {
                Button("Cobrar", action: cobrar).buttonStyle(.bordered)
            } else if !evento.pagoElHogar && ["pendiente", "parcial"].contains(p.estado) {
                Button("Ya pagó", action: yaPago).buttonStyle(.bordered)
            } else if !evento.pagoElHogar && p.fechaPago != nil {
                Button("Quitar pago", action: quitar).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Semantica.tarjeta, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { abierto.toggle() }
    }
}

/// Cobrar a un contacto su parte (pagó el hogar): el dinero entra solo al efectivo o a una cuenta.
private struct HojaCobroEvento: View {
    let eventoId: Int
    let participante: ParticipanteEvento
    let destinos: [OpcionEvento]
    let listo: (Evento) -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var monto = ""
    @State private var fecha = Date()
    @State private var destino = "efectivo"
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Te debe \(Formato.dinero(participante.pendiente)). El dinero entra solo al efectivo o a la cuenta que elijas.").font(.callout)
                    CampoMonto(etiqueta: "Monto", valor: $monto, error: errores["monto"])
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                    ErrorCampo(texto: errores["fecha"])
                    Picker("¿A dónde entró?", selection: $destino) { ForEach(destinos, id: \.valor) { Text($0.etiqueta).tag($0.valor) } }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Cobrar a \(participante.nombre)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Registrar") { Task { await guardar() } }.disabled(guardando) }
            }
            .onAppear { monto = participante.pendiente }
        }
    }

    private func guardar() async {
        guard Formato.montoValido(monto) else { errores = ["monto": "Monto positivo con máximo dos decimales."]; return }
        guardando = true
        defer { guardando = false }
        do {
            let r: Envoltura<Evento> = try await API.shared.post("/eventos/\(eventoId)/participantes/\(participante.id)/cobro",
                                                              CobroEventoCuerpo(monto: monto, fecha: Formato.textoLocal(fecha), destino: destino))
            listo(r.data); cerrar()
        } catch let f as FallaAPI { errores = f.campos; error = f.mensaje } catch { self.error = error.localizedDescription }
    }
}

/// Pagó otra persona: marcar que alguien ya le pagó. Si es del hogar, se registra su egreso.
private struct HojaPagadoEvento: View {
    let eventoId: Int
    let participante: ParticipanteEvento
    let pagador: String
    let origenes: [OpcionEvento]
    let listo: (Evento) -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var fecha = Date()
    @State private var origen = "efectivo"
    @State private var categoriaId: Int?
    @State private var errores: [String: String] = [:]
    @State private var error: String?
    @State private var guardando = false
    @State private var pregunta: String?
    private let comunes = Comunes.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Su parte es \(Formato.dinero(participante.total)) y se la pagó a \(pagador).").font(.callout)
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                    ErrorCampo(texto: errores["fecha"])
                    if participante.userId != nil {
                        Picker("¿De dónde salió?", selection: $origen) { ForEach(origenes, id: \.valor) { Text($0.etiqueta).tag($0.valor) } }
                        if origen != "ninguno" {
                            Picker("Categoría", selection: $categoriaId) {
                                Text("Elegir…").tag(nil as Int?)
                                ForEach(comunes.categoriasDe("egreso")) { Text($0.nombre).tag($0.id as Int?) }
                            }
                            ErrorCampo(texto: errores["categoria_personal_id"])
                        }
                    }
                }
                if let error, errores.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("\(participante.nombre) ya pagó")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
            .alert("¿Registrar de todas formas?", isPresented: Binding(get: { pregunta != nil }, set: { if !$0 { pregunta = nil } })) {
                Button("Cancelar", role: .cancel) {}
                Button("Sí, registrar") { Task { await guardar(confirmado: true) } }
            } message: { Text(pregunta ?? "") }
        }
    }

    private func guardar(confirmado: Bool = false) async {
        let conMovimiento = participante.userId != nil && origen != "ninguno"
        if conMovimiento && categoriaId == nil { errores = ["categoria_personal_id": "Elige una categoría."]; return }
        guardando = true
        defer { guardando = false }
        do {
            let cuerpo = PagadoEventoCuerpo(fecha: Formato.textoLocal(fecha), origen: participante.userId != nil ? origen : nil,
                                            categoriaPersonalId: conMovimiento ? categoriaId : nil, confirmar: confirmado ? true : nil)
            let r: Envoltura<Evento> = try await API.shared.post("/eventos/\(eventoId)/participantes/\(participante.id)/pagado", cuerpo)
            listo(r.data); cerrar()
        } catch let f as FallaAPI {
            if let p = f.campos["confirmar"] { pregunta = p } else { errores = f.campos; error = f.mensaje }
        } catch { self.error = error.localizedDescription }
    }
}

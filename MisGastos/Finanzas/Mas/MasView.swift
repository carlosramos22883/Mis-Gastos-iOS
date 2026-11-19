import SwiftUI

/// Rutas de navegación dentro de cada pestaña.
enum Ruta: Hashable {
    case compromiso(Int)
    case cuentas
    case cuenta(Int)
    case tarjeta(Int)
    case contactos(soloDeben: Bool)
    case contacto(Int)
    case prestamos
    case prestamo(Int)
    case ingresos
    case ingreso(Int)
    case perfil
    case categorias
    case reportes
    case proyecciones
    case eventos
    case evento(Int)
    case despensa
    case compras
    case productoDespensa(Int)
    case listaCompra(Int)
}

extension View {
    /// Destinos comunes de todas las pestañas.
    func destinosFinanzas() -> some View {
        navigationDestination(for: Ruta.self) { ruta in
            switch ruta {
            case .compromiso(let id): CompromisoDetalleView(id: id)
            case .cuentas: CuentasView()
            case .cuenta(let id): CuentaDetalleView(id: id)
            case .tarjeta(let id): TarjetaDetalleView(id: id)
            case .contactos(let soloDeben): ContactosView(soloDeben: soloDeben)
            case .contacto(let id): ContactoDetalleView(id: id)
            case .prestamos: PrestamosView()
            case .prestamo(let id): PrestamoDetalleView(id: id)
            case .ingresos: IngresosView()
            case .ingreso(let id): IngresoDetalleView(id: id)
            case .perfil: PerfilView()
            case .categorias: CategoriasView()
            case .reportes: ReportesView()
            case .proyecciones: ProyeccionesView()
            case .eventos: EventosView()
            case .evento(let id): EventoDetalleView(id: id)
            case .despensa: DespensaView()
            case .compras: ComprasView()
            case .productoDespensa(let id): ProductoView(id: id, codigoInicial: nil)
            case .listaCompra(let id): ListaCompraView(id: id)
            }
        }
        .destinosDespensa()
    }
}

/// Usuario, hogar y cerrar sesión.
struct MasView: View {
    private let comunes = Comunes.shared

    var body: some View {
        List {
            if let u = comunes.usuario {
                Section {
                    HStack(spacing: 12) {
                        Avatar(url: Formato.urlAvatar(u.avatar), nombre: u.name, tamano: 56)
                        VStack(alignment: .leading) {
                            Text(u.name).font(.headline)
                            Text(u.email).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Finanzas") {
                NavigationLink(value: Ruta.cuentas) { Label("Cuentas", systemImage: "building.columns") }
                NavigationLink(value: Ruta.contactos(soloDeben: false)) { Label("Contactos y lo que nos deben", systemImage: "person.2") }
                NavigationLink(value: Ruta.prestamos) { Label("Préstamos", systemImage: "percent") }
                NavigationLink(value: Ruta.ingresos) { Label("Ingresos", systemImage: "arrow.down.circle") }
                NavigationLink(value: Ruta.eventos) { Label("Eventos (dividir la cuenta)", systemImage: "fork.knife") }
                NavigationLink(value: Ruta.despensa) { Label("Despensa", systemImage: "refrigerator") }
                NavigationLink(value: Ruta.compras) { Label("Lista de compras", systemImage: "cart") }
                NavigationLink(value: Ruta.reportes) { Label("Reportes", systemImage: "chart.bar.doc.horizontal") }
                NavigationLink(value: Ruta.proyecciones) { Label("Proyecciones", systemImage: "chart.line.downtrend.xyaxis") }
            }
            Section("Ajustes") {
                NavigationLink(value: Ruta.perfil) { Label("Mi perfil", systemImage: "person.crop.circle") }
                NavigationLink(value: Ruta.categorias) { Label("Categorías", systemImage: "tag") }
            }
            if let h = comunes.hogar {
                Section(h.nombre) {
                    FilaValor(etiqueta: "Cierre de ciclo", valor: "Día \(h.fechaCorteDia)")
                    ForEach(h.miembros) { m in
                        HStack(spacing: 10) {
                            Avatar(url: Formato.urlAvatar(m.avatar), nombre: m.nombre, tamano: 32)
                            Text(m.nombre)
                            Spacer()
                            Text(m.esAdministrador ? "Administra" : "Miembro").foregroundStyle(.secondary).font(.subheadline)
                        }
                    }
                }
            }
            Section {
                Button("Cerrar sesión", role: .destructive) {
                    Task {
                        Comunes.shared.olvidar()
                        await SessionManager.shared.logout()
                    }
                }
            }
        }
        .navigationTitle("Más")
        .destinosFinanzas()
        .refreshable { await comunes.cargar(refrescar: true) }
    }
}

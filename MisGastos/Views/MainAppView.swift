import SwiftUI

/// Pantalla principal después del login: pestañas con los módulos de finanzas.
struct MainAppView: View {
    @State private var pestana = 0
    @State private var rutaCompromisos: [Ruta] = []
    @State private var rutaMas: [Ruta] = []

    var body: some View {
        TabView(selection: $pestana) {
            NavigationStack { InicioView().destinosFinanzas() }
                .tabItem { Label("Inicio", systemImage: "house.fill") }.tag(0)
            NavigationStack { EfectivoView().destinosFinanzas() }
                .tabItem { Label("Efectivo", systemImage: "banknote.fill") }.tag(1)
            NavigationStack { TarjetasView().destinosFinanzas() }
                .tabItem { Label("Tarjetas", systemImage: "creditcard.fill") }.tag(2)
            NavigationStack(path: $rutaCompromisos) { CompromisosView().destinosFinanzas() }
                .tabItem { Label("Compromisos", systemImage: "calendar") }.tag(3)
            NavigationStack(path: $rutaMas) { MasView() }
                .tabItem { Label("Más", systemImage: "line.3.horizontal") }.tag(4)
        }
        .onAppear {
            #if DEBUG
            if let p = ArranqueDebug.pestana { pestana = p }
            if let a = ArranqueDebug.abrir, a.hasPrefix("compromiso:") || a.hasPrefix("pago:") || a.hasPrefix("serie:"), let id = Int(a.split(separator: ":")[1]) {
                pestana = 3; rutaCompromisos = [.compromiso(id)]
            }
            if let rutas = ArranqueDebug.rutasMas { pestana = 4; rutaMas = rutas }
            #endif
        }
        .task { await Comunes.shared.cargar() }
        // Un 401 (token vencido o revocado) regresa al login
        .onReceive(NotificationCenter.default.publisher(for: API.sesionExpirada)) { _ in
            Comunes.shared.olvidar()
            SessionManager.shared.currentUser = nil
            SessionManager.shared.isLoggedIn = false
        }
    }
}

#Preview {
    MainAppView()
}

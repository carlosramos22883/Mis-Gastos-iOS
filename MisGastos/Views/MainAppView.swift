import SwiftUI

/// Pantalla principal después del login: pestañas con los módulos de finanzas.
struct MainAppView: View {
    @State private var pestana = 0
    /// La pila de navegación de cada pestaña (cada una recuerda dónde se quedó)
    @State private var rutas: [[Ruta]] = Array(repeating: [], count: 5)

    /// Tocar la pestaña en la que ya se está regresa a su pantalla principal
    private var seleccion: Binding<Int> {
        Binding(get: { pestana }, set: { nueva in
            if nueva == pestana { rutas[nueva] = [] }
            pestana = nueva
        })
    }

    var body: some View {
        TabView(selection: seleccion) {
            NavigationStack(path: $rutas[0]) { InicioView().destinosFinanzas() }
                .tabItem { Label("Inicio", systemImage: "house.fill") }.tag(0)
            NavigationStack(path: $rutas[1]) { EfectivoView().destinosFinanzas() }
                .tabItem { Label("Efectivo", systemImage: "banknote.fill") }.tag(1)
            NavigationStack(path: $rutas[2]) { TarjetasView().destinosFinanzas() }
                .tabItem { Label("Tarjetas", systemImage: "creditcard.fill") }.tag(2)
            NavigationStack(path: $rutas[3]) { CompromisosView().destinosFinanzas() }
                .tabItem { Label("Compromisos", systemImage: "calendar") }.tag(3)
            NavigationStack(path: $rutas[4]) { MasView() }
                .tabItem { Label("Más", systemImage: "line.3.horizontal") }.tag(4)
        }
        .onAppear {
            #if DEBUG
            if let p = ArranqueDebug.pestana { pestana = p }
            if let a = ArranqueDebug.abrir, a.hasPrefix("compromiso:") || a.hasPrefix("pago:") || a.hasPrefix("serie:"), let id = Int(a.split(separator: ":")[1]) {
                pestana = 3; rutas[3] = [.compromiso(id)]
            }
            if let r = ArranqueDebug.rutasMas { pestana = 4; rutas[4] = r }
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

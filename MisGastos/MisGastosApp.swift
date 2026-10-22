import SwiftUI

@main
struct MisGastosApp: App {
    init() {
        #if DEBUG
        ArranqueDebug.aplicarToken()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

import SwiftUI

struct RootView: View {
    @StateObject private var session = SessionManager.shared
    
    var body: some View {
        Group {
            if session.isLoggedIn {
                MainAppView()
            } else {
                AuthView()
            }
        }
        .onAppear {
            session.checkSession()
        }
    }
}

#Preview {
    RootView()
}

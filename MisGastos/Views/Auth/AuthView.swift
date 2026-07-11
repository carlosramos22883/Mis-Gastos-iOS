import SwiftUI

struct AuthView: View {
    @State private var showRegister = false
    
    var body: some View {
        NavigationStack {
            LoginView(showRegisterView: $showRegister)
                .navigationDestination(isPresented: $showRegister) {
                    RegisterView()
                }
        }
    }
}

#Preview {
    AuthView()
}

import SwiftUI

struct ProfileView: View {
    @ObservedObject private var session = SessionManager.shared
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView("Cargando perfil...")
            } else if let user = session.currentUser {
                VStack(spacing: 15) {
                    Image(systemName: "person.crop.circle.fill.badge.checkmark")
                        .font(.system(size: 100))
                        .foregroundColor(.blue)
                    
                    Text(user.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(user.email)
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    
                    Divider()
                        .padding(.vertical)
                    
                    Button(action: {
                        Task {
                            await session.logout()
                        }
                    }) {
                        Label("Cerrar Sesión", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                .padding()
            } else {
                Text("No se pudo cargar el usuario")
                    .foregroundColor(.red)
            }
            
            Spacer()
        }
        .navigationTitle("Mi Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadUserIfEmpty()
        }
    }
    
    private func loadUserIfEmpty() {
        if session.currentUser == nil {
            Task {
                do {
                    let user = try await AuthService.shared.getUser()
                    session.currentUser = user
                } catch {
                    print("Error cargando usuario: \(error)")
                }
                isLoading = false
            }
        } else {
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}

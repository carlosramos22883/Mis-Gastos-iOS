import SwiftUI

struct MainAppView: View {
    var body: some View {
        TabView {
            // Pestaña de Gastos (Placeholder para la Fase 5)
            NavigationStack {
                VStack(spacing: 20) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("Mis Gastos")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Próximamente agregaremos la lista de gastos aquí.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .navigationTitle("Inicio")
            }
            .tabItem {
                Label("Gastos", systemImage: "chart.pie.fill")
            }
            
            // Pestaña de Perfil
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Perfil", systemImage: "person.fill")
            }
        }
    }
}

#Preview {
    MainAppView()
}

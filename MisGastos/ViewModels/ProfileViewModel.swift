import Foundation
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadUser() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                user = try await AuthService.shared.getUser()
            } catch let error as APIError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Error al cargar el perfil: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
}

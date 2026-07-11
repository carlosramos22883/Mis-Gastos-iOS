import Foundation
import Combine

@MainActor
class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && isValidEmail(email)
    }
    
    func login() {
        guard isFormValid else {
            errorMessage = "Por favor, completa todos los campos correctamente"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let response = try await AuthService.shared.login(email: email, password: password)
                // ¡Aquí avisamos al SessionManager!
                SessionManager.shared.loginSuccess(user: response.user)
            } catch let error as APIError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Error inesperado: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

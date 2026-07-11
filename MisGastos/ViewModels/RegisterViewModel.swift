import Foundation
import Combine

@MainActor
class RegisterViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var passwordConfirmation = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    var isFormValid: Bool {
        !name.isEmpty &&
        !email.isEmpty &&
        !password.isEmpty &&
        !passwordConfirmation.isEmpty &&
        password == passwordConfirmation &&
        isValidEmail(email) &&
        password.count >= 6
    }
    
    func register() {
        guard isFormValid else {
            if password != passwordConfirmation {
                errorMessage = "Las contraseñas no coinciden"
            } else if password.count < 6 {
                errorMessage = "La contraseña debe tener al menos 6 caracteres"
            } else {
                errorMessage = "Por favor, completa todos los campos correctamente"
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let response = try await AuthService.shared.register(
                    name: name,
                    email: email,
                    password: password,
                    passwordConfirmation: passwordConfirmation
                )
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

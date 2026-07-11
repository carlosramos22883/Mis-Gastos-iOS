import Foundation
import Combine

@MainActor
class ResetPasswordViewModel: ObservableObject {
    @Published var token = ""
    @Published var email = ""
    @Published var password = ""
    @Published var passwordConfirmation = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isResetSuccess = false
    
    var isFormValid: Bool {
        !token.isEmpty &&
        !email.isEmpty &&
        !password.isEmpty &&
        !passwordConfirmation.isEmpty &&
        password == passwordConfirmation &&
        password.count >= 6
    }
    
    func resetPassword() {
        guard isFormValid else {
            if password != passwordConfirmation {
                errorMessage = "Las contraseñas no coinciden"
            } else if password.count < 6 {
                errorMessage = "La contraseña debe tener al menos 6 caracteres"
            } else {
                errorMessage = "Por favor, completa todos los campos"
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await AuthService.shared.resetPassword(
                    token: token,
                    email: email,
                    password: password,
                    passwordConfirmation: passwordConfirmation
                )
                isResetSuccess = true
            } catch let error as APIError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Error inesperado: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
}

import Foundation
import Combine

@MainActor
class ForgotPasswordViewModel: ObservableObject {
    @Published var email = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isEmailSent = false
    
    var isFormValid: Bool {
        !email.isEmpty && isValidEmail(email)
    }
    
    func sendResetLink() {
        guard isFormValid else {
            errorMessage = "Por favor, ingresa un email válido"
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                try await AuthService.shared.forgotPassword(email: email)
                successMessage = "✅ Hemos enviado un enlace de recuperación a tu correo"
                isEmailSent = true
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

import Foundation
import Combine
import GoogleSignIn
import GoogleSignInSwift

@MainActor
class GoogleAuthViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func signIn() {
        isLoading = true
        errorMessage = nil
        
        let clientID = FirebaseConstants.googleClientID
        
        guard !clientID.isEmpty && clientID != "TU_ID_DE_CLIENTE_IOS_AQUI.apps.googleusercontent.com" else {
            errorMessage = "⚠️ ID de cliente de Google no configurado. Revisa FirebaseConstants."
            isLoading = false
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "No se pudo obtener la ventana principal"
            isLoading = false
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
            // ⚠️ IMPORTANTE: Este callback se ejecuta en un hilo de fondo
            // Por eso usamos Task { @MainActor in ... } para actualizar la UI
            
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }
                
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.errorMessage = "No se pudo obtener el token de Google"
                    self.isLoading = false
                    return
                }
                
                // Llamar al backend
                do {
                    let response = try await AuthService.shared.googleLogin(idToken: idToken)
                    SessionManager.shared.loginSuccess(user: response.user)
                } catch let error as APIError {
                    self.errorMessage = error.localizedDescription
                } catch {
                    self.errorMessage = "Error inesperado: \(error.localizedDescription)"
                }
                
                self.isLoading = false
            }
        }
    }
}

enum FirebaseConstants {
    // ⚠️ PEGA AQUÍ TU ID DE CLIENTE DE IOS
    static let googleClientID = "130078023125-t5mtrpo8b9mn7oseckffiaet4fqg7iad.apps.googleusercontent.com"
}

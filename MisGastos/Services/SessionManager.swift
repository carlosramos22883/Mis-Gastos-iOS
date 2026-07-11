import Foundation
import SwiftUI
import Combine

class SessionManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User?
    
    static let shared = SessionManager()
    private init() {
        checkSession()
    }
    
    func checkSession() {
        // Revisa si hay un token guardado en el Keychain
        isLoggedIn = AuthService.shared.isLoggedIn()
    }
    
    func loginSuccess(user: User) {
        self.currentUser = user
        self.isLoggedIn = true
    }
    
    func logout() async {
        do {
            try await AuthService.shared.logout()
        } catch {
            print("Error al hacer logout en el servidor: \(error)")
        }
        
        self.currentUser = nil
        self.isLoggedIn = false
    }
}

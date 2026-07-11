import Foundation

class AuthService {
    static let shared = AuthService()
    private let networkManager = NetworkManager.shared
    private init() {}
    
    // MARK: - Login
    func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password)
        
        let response: AuthResponse = try await networkManager.request(
            endpoint: "/login",
            method: "POST",
            body: body,
            requiresAuth: false,
            responseType: AuthResponse.self
        )
        
        // Guardar token en Keychain
        _ = KeychainManager.shared.saveToken(response.token)
        
        return response
    }
    
    // MARK: - Register
    func register(name: String, email: String, password: String, passwordConfirmation: String) async throws -> AuthResponse {
        let body = RegisterRequest(
            name: name,
            email: email,
            password: password,
            passwordConfirmation: passwordConfirmation
        )
        
        let response: AuthResponse = try await networkManager.request(
            endpoint: "/register",
            method: "POST",
            body: body,
            requiresAuth: false,
            responseType: AuthResponse.self
        )
        
        // Guardar token en Keychain
        _ = KeychainManager.shared.saveToken(response.token)
        
        return response
    }
    
    // MARK: - Get User Profile
    func getUser() async throws -> User {
        return try await networkManager.request(
            endpoint: "/user",
            method: "GET",
            requiresAuth: true,
            responseType: User.self
        )
    }
    
    // MARK: - Logout
    func logout() async throws {
        _ = try await networkManager.request(
            endpoint: "/logout",
            method: "POST",
            requiresAuth: true,
            responseType: [String: String].self
        )
        
        // Eliminar token del Keychain
        _ = KeychainManager.shared.deleteToken()
    }
    
    // MARK: - Check if user is logged in
    func isLoggedIn() -> Bool {
        return KeychainManager.shared.getToken() != nil
    }
    
    // MARK: - Forgot Password
    func forgotPassword(email: String) async throws {
        let body = ["email": email]
        
        _ = try await networkManager.request(
            endpoint: "/forgot-password",
            method: "POST",
            body: body,
            requiresAuth: false,
            responseType: [String: String].self
        )
    }
    
    // MARK: - Reset Password
    func resetPassword(token: String, email: String, password: String, passwordConfirmation: String) async throws {
        let body: [String: String] = [
            "token": token,
            "email": email,
            "password": password,
            "password_confirmation": passwordConfirmation
        ]
        
        _ = try await networkManager.request(
            endpoint: "/reset-password",
            method: "POST",
            body: body,
            requiresAuth: false,
            responseType: [String: String].self
        )
    }
    
    // MARK: - Google Login
    func googleLogin(idToken: String) async throws -> AuthResponse {
        let body: [String: String] = [
            "id_token": idToken
        ]
        
        let response: AuthResponse = try await networkManager.request(
            endpoint: "/auth/google",
            method: "POST",
            body: body,
            requiresAuth: false,
            responseType: AuthResponse.self
        )
        
        // Guardar token en Keychain
        _ = KeychainManager.shared.saveToken(response.token)
        
        return response
    }
}

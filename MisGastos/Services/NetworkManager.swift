import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    private init() {}
    
    private let decoder = JSONDecoder()
    
    // MARK: - Request Genérico
    func request<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Codable? = nil,
        requiresAuth: Bool = false,
        responseType: T.Type
    ) async throws -> T {
        
        guard let url = URL(string: "\(Constants.baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Agregar token si es necesario
        if requiresAuth, let token = KeychainManager.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Agregar body si existe
        if let body = body {
            request.httpBody = try? JSONEncoder().encode(body)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            // Manejar códigos de estado
            switch httpResponse.statusCode {
            case 200...299:
                return try decoder.decode(T.self, from: data)
            case 401:
                throw APIError.unauthorized
            case 400:
                if let errorResponse = try? decoder.decode([String: [String]].self, from: data) {
                    let message = errorResponse.values.first?.first ?? "Error en la solicitud"
                    throw APIError.badRequest(message)
                }
                throw APIError.badRequest("Error en la solicitud")
            case 404:
                throw APIError.serverError("Recurso no encontrado")
            case 500...599:
                throw APIError.serverError("Error interno del servidor")
            default:
                throw APIError.invalidResponse
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

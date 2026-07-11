import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case networkError(Error)
    case serverError(String)
    case unauthorized
    case badRequest(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL inválida"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .invalidData:
            return "Datos inválidos"
        case .networkError(let error):
            return "Error de red: \(error.localizedDescription)"
        case .serverError(let message):
            return "Error del servidor: \(message)"
        case .unauthorized:
            return "No autorizado. Por favor, inicia sesión nuevamente"
        case .badRequest(let message):
            return "Error: \(message)"
        }
    }
}

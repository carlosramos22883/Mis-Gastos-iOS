import Foundation

enum Constants {
    #if DEBUG
    static let baseURL = "http://localhost:8081/api"
    #else
    static let baseURL = "https://tu-dominio.com/api"
    #endif
    
    static let googleClientID = "TU_GOOGLE_CLIENT_ID" // Lo obtendrás de Google Cloud Console
}

import SwiftUI
import GoogleSignInSwift

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @StateObject private var googleViewModel = GoogleAuthViewModel()
    @Binding var showRegisterView: Bool
    @State private var showForgotPassword = false
    
    var body: some View {
        ZStack {
            // Fondo con gradiente
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 25) {
                // Logo y título
                VStack(spacing: 15) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .shadow(color: .blue.opacity(0.3), radius: 10)
                    
                    Text("Mis Gastos")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    
                    Text("Inicia sesión")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
                .padding(.top, 60)
                
                // Campos de formulario
                VStack(spacing: 15) {
                    CustomTextField(
                        icon: "envelope.fill",
                        placeholder: "Email",
                        text: $viewModel.email
                    )
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .shadow(color: .black.opacity(0.05), radius: 5)
                    
                    CustomTextField(
                        icon: "lock.fill",
                        placeholder: "Contraseña",
                        text: $viewModel.password,
                        isSecure: true
                    )
                    .shadow(color: .black.opacity(0.05), radius: 5)
                }
                .padding(.horizontal)
                
                // Olvidaste tu contraseña
                HStack {
                    Spacer()
                    Button(action: {
                        showForgotPassword = true
                    }) {
                        Text("¿Olvidaste tu contraseña?")
                            .foregroundColor(.blue)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal)
                
                // Mensaje de error
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
                
                if let googleError = googleViewModel.errorMessage {
                    Text(googleError)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Botón de login
                PrimaryButton(
                    title: "Iniciar Sesión",
                    action: viewModel.login,
                    isLoading: viewModel.isLoading,
                    isEnabled: viewModel.isFormValid
                )
                .padding(.horizontal)
                
                // Separador
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                    Text("O")
                        .foregroundColor(.gray)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal)
                
                // Botón Google (Placeholder)
                GoogleSignInButton(viewModel: GoogleSignInButtonViewModel(scheme: .dark, style: .wide, state: viewModel.isLoading ? .disabled : .normal)) {
                                    googleViewModel.signIn()
                                }
                                .padding(.horizontal)
                                .frame(height: 50)
                
                Spacer()
                
                // Link a registro
                HStack {
                    Text("¿No tienes una cuenta?")
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        showRegisterView = true
                    }) {
                        Text("Regístrate")
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        
        
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }
}

#Preview {
    NavigationStack {
        LoginView(showRegisterView: .constant(false))
    }
}

import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Título
            Text("Crear Cuenta")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 40)
            
            // Campos de formulario
            VStack(spacing: 15) {
                CustomTextField(
                    icon: "person",
                    placeholder: "Nombre completo",
                    text: $viewModel.name
                )
                
                CustomTextField(
                    icon: "envelope",
                    placeholder: "Email",
                    text: $viewModel.email
                )
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                
                CustomTextField(
                    icon: "lock",
                    placeholder: "Contraseña",
                    text: $viewModel.password,
                    isSecure: true
                )
                
                CustomTextField(
                    icon: "lock.shield",
                    placeholder: "Confirmar contraseña",
                    text: $viewModel.passwordConfirmation,
                    isSecure: true
                )
            }
            .padding(.horizontal)
            
            // Mensaje de error
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Botón de registro
            PrimaryButton(
                title: "Registrarse",
                action: viewModel.register,
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.isFormValid
            )
            .padding(.horizontal)
            
            Spacer()
            
            // Link a login
            HStack {
                Text("¿Ya tienes una cuenta?")
                    .foregroundColor(.gray)
                
                Button(action: {
                    dismiss()
                }) {
                    Text("Inicia sesión")
                        .fontWeight(.semibold)
                }
            }
            .padding(.bottom, 40)
        }
        // ❌ ELIMINAMOS ESTA LÍNEA QUE CAUSABA EL ERROR:
        // .navigationDestination(isPresented: $viewModel.isLoggedIn) { ProfileView() }
    }
}

#Preview {
    NavigationStack {
        RegisterView()
    }
}

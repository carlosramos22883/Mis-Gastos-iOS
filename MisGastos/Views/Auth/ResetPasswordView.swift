import SwiftUI

struct ResetPasswordView: View {
    @StateObject private var viewModel = ResetPasswordViewModel()
    @Environment(\.dismiss) private var dismiss
    
    // Estos valores vienen del email que el usuario recibió
    let email: String
    let token: String
    
    var body: some View {
        VStack(spacing: 20) {
            // Icono
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.top, 40)
            
            // Título
            Text("Nueva Contraseña")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Ingresa tu nueva contraseña")
                .foregroundColor(.gray)
            
            // Campos
            VStack(spacing: 15) {
                CustomTextField(
                    icon: "lock",
                    placeholder: "Nueva contraseña",
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
            
            // Botón
            PrimaryButton(
                title: "Restablecer contraseña",
                action: viewModel.resetPassword,
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.isFormValid
            )
            .padding(.horizontal)
            
            Spacer()
        }
        .onAppear {
            viewModel.email = email
            viewModel.token = token
        }
        .alert("Contraseña actualizada", isPresented: $viewModel.isResetSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Tu contraseña ha sido restablecida correctamente. Ya puedes iniciar sesión.")
        }
    }
}

#Preview {
    NavigationStack {
        ResetPasswordView(
            email: "test@example.com",
            token: "token-de-prueba"
        )
    }
}

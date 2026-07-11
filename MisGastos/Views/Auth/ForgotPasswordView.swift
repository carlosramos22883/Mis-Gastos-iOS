import SwiftUI

struct ForgotPasswordView: View {
    @StateObject private var viewModel = ForgotPasswordViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Icono
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.top, 40)
            
            // Título
            Text("Recuperar Contraseña")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Ingresa tu correo electrónico y te enviaremos un enlace para restablecer tu contraseña")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Campo email
            CustomTextField(
                icon: "envelope",
                placeholder: "Email",
                text: $viewModel.email
            )
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            .padding(.horizontal)
            
            // Mensaje de éxito
            if let successMessage = viewModel.successMessage {
                Text(successMessage)
                    .foregroundColor(.green)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            
            // Mensaje de error
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Botón enviar
            PrimaryButton(
                title: viewModel.isEmailSent ? "Reenviar enlace" : "Enviar enlace de recuperación",
                action: viewModel.sendResetLink,
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.isFormValid
            )
            .padding(.horizontal)
            
            Spacer()
            
            // Volver al login
            Button(action: {
                dismiss()
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Volver al inicio de sesión")
                }
                .foregroundColor(.blue)
            }
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
    }
}

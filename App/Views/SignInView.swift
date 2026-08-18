import SwiftUI

struct SignInView: View {
  @Environment(MeuralSession.self) private var session
  @State private var email = ""
  @State private var password = ""
  @State private var isSigningIn = false
  @State private var errorMessage: String?

  private var canSignIn: Bool {
    !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSigningIn
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: 12) {
            Image(systemName: "photo.artframe")
              .font(.system(size: 56))
              .foregroundStyle(.tint)
            Text("Gallerist")
              .font(.title2.bold())
            Text("Sign in with your Meural account to manage your photos, playlists, and frames.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .listRowBackground(Color.clear)
        }

        Section {
          TextField("Email", text: $email)
            .keyboardType(.emailAddress)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          SecureField("Password", text: $password)
            .textContentType(.password)
            .onSubmit(signIn)
        }

        Section {
          Button(action: signIn) {
            HStack {
              Text("Sign In")
                .frame(maxWidth: .infinity)
              if isSigningIn {
                ProgressView()
              }
            }
          }
          .disabled(!canSignIn)
        } footer: {
          Text("Your password is stored securely in the Keychain on this device and sent only to Meural's sign-in service.")
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
        }
      }
    }
  }

  private func signIn() {
    guard canSignIn else { return }
    isSigningIn = true
    errorMessage = nil
    Task {
      defer { isSigningIn = false }
      do {
        try await session.signIn(
          email: email.trimmingCharacters(in: .whitespaces),
          password: password
        )
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

import SwiftUI

struct AccountView: View {
  @Environment(MeuralSession.self) private var session
  @Environment(LibraryStore.self) private var library
  @State private var confirmingSignOut = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Account") {
          LabeledContent("Email", value: session.email ?? "—")
          Button("Sign Out", role: .destructive) {
            confirmingSignOut = true
          }
        }

        Section("About") {
          LabeledContent("App", value: "Gallerist")
          Text("Manage your Meural library, playlists, and frames — no server required. The app talks directly to your Meural account.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Account")
      .confirmationDialog(
        "Sign out of Meural?",
        isPresented: $confirmingSignOut,
        titleVisibility: .visible
      ) {
        Button("Sign Out", role: .destructive) {
          library.reset()
          session.signOut()
        }
      }
    }
  }
}

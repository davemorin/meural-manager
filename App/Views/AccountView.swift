import SwiftUI

struct AccountView: View {
  @Environment(MeuralSession.self) private var session
  @Environment(LibraryStore.self) private var library
  @Environment(PhotoBackupManager.self) private var backup
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

        Section("Storage") {
          if let user = library.user, let fraction = user.usedFraction,
             let used = user.usedGigabytes, let total = user.totalGigabytes {
            VStack(alignment: .leading, spacing: 8) {
              ProgressView(value: fraction)
                .tint(fraction > 0.9 ? .red : fraction > 0.8 ? .orange : .accentColor)
              HStack {
                Text(String(format: "%.2f GB of %.0f GB used", used, total))
                Spacer()
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                  .foregroundStyle(.secondary)
              }
              .font(.subheadline)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
          } else {
            HStack {
              Text("Checking storage…")
                .foregroundStyle(.secondary)
              Spacer()
              ProgressView()
            }
          }
        }

        Section {
          if backup.isBackingUp {
            VStack(alignment: .leading, spacing: 8) {
              Text("Backing up \(min(backup.completed + 1, backup.total)) of \(backup.total)…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
              ProgressView(value: Double(backup.completed), total: Double(max(backup.total, 1)))
            }
            .padding(.vertical, 4)
            Button("Pause Backup") {
              backup.cancel()
            }
          } else {
            Button("Back Up Library to Photos", systemImage: "square.and.arrow.down.on.square") {
              Task {
                await library.loadAllPhotos()
                await backup.backUp(library.photos)
              }
            }
          }
          if let status = backup.statusMessage {
            Text(status)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Backup")
        } footer: {
          Text("Saves every photo in your Meural library to an album named \"Artwall\" in your Photos library. Photos already backed up are skipped, so you can run it again anytime to pick up new uploads.")
        }

        Section("About") {
          LabeledContent("App", value: "Artwall")
          Text("Manage your Meural library, playlists, and frames — no server required. The app talks directly to your Meural account.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Account")
      .refreshable {
        await library.loadUser(force: true)
      }
      .task {
        await library.loadUser()
      }
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

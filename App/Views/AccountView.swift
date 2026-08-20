import SwiftUI

struct AccountView: View {
  @Environment(MeuralSession.self) private var session
  @Environment(LibraryStore.self) private var library
  @Environment(PhotoAlbumBuilder.self) private var albumBuilder
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
          if albumBuilder.isMatching {
            VStack(alignment: .leading, spacing: 8) {
              Text("Matching \(min(albumBuilder.completed + 1, albumBuilder.total)) of \(albumBuilder.total)…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
              ProgressView(value: Double(albumBuilder.completed), total: Double(max(albumBuilder.total, 1)))
            }
            .padding(.vertical, 4)
            Button("Pause") {
              albumBuilder.cancel()
            }
          } else {
            Button("Collect Originals into Album", systemImage: "photo.badge.checkmark") {
              Task {
                await library.loadAllPhotos()
                await albumBuilder.buildAlbum(from: library.photos)
              }
            }
          }
          if let status = albumBuilder.statusMessage {
            Text(status)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Photos Album")
        } footer: {
          Text("Finds the original of each Meural photo in your photo library — matched by capture time and dimensions — and collects the originals into an album named \"Artwall\". Nothing is duplicated. Photos whose originals can't be found are skipped, and re-running only processes new photos.")
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

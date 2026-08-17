import SwiftUI

struct FramesView: View {
  @Environment(LibraryStore.self) private var library

  var body: some View {
    NavigationStack {
      List(library.frames) { frame in
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            Image(systemName: "photo.artframe")
              .font(.title2)
              .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
              Text(frame.displayName)
                .font(.headline)
              HStack(spacing: 6) {
                Circle()
                  .fill(frame.isOnline ? Color.green : Color.secondary)
                  .frame(width: 8, height: 8)
                Text(frame.isOnline ? "Online" : "Offline")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .accessibilityElement(children: .combine)
            }
          }
          Picker("Playlist", selection: playlistSelection(for: frame)) {
            Text("Not Set").tag(0)
            ForEach(library.playlists) { playlist in
              Text(playlist.displayName).tag(playlist.id)
            }
          }
          .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
      }
      .navigationTitle("Frames")
      .refreshable {
        await library.loadFrames(force: true)
        await library.loadPlaylists(force: true)
      }
      .overlay {
        if library.frames.isEmpty {
          ContentUnavailableView(
            "No Frames",
            systemImage: "photo.artframe",
            description: Text("Frames linked to your Meural account will appear here.")
          )
        }
      }
      .task(id: library.serverURLString) {
        await library.loadFrames()
        await library.loadPlaylists()
      }
    }
  }

  private func playlistSelection(for frame: MeuralFrame) -> Binding<Int> {
    Binding {
      guard let id = frame.currentPlaylistID,
            library.playlists.contains(where: { $0.id == id }) else { return 0 }
      return id
    } set: { newID in
      guard newID != 0, newID != frame.currentPlaylistID else { return }
      Task {
        await library.assignPlaylist(newID, toFrame: frame.id)
      }
    }
  }
}

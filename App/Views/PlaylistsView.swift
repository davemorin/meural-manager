import SwiftUI

struct PlaylistsView: View {
  @Environment(LibraryStore.self) private var library
  @State private var showingNewPlaylist = false
  @State private var newPlaylistName = ""

  var body: some View {
    NavigationStack {
      List {
        ForEach(library.playlists) { playlist in
          NavigationLink(value: playlist) {
            HStack(spacing: 12) {
              Image(systemName: "rectangle.stack")
                .font(.title3)
                .foregroundStyle(.tint)
              VStack(alignment: .leading, spacing: 2) {
                Text(playlist.displayName)
                Text("^[\(playlist.itemCount ?? 0) item](inflect: true)")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 2)
          }
        }
        .onDelete { offsets in
          Task {
            await library.deletePlaylists(at: offsets)
          }
        }
      }
      .navigationTitle("Playlists")
      .navigationDestination(for: MeuralPlaylist.self) { playlist in
        PlaylistDetailView(playlist: playlist)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("New Playlist", systemImage: "plus") {
            showingNewPlaylist = true
          }
        }
      }
      .alert("New Playlist", isPresented: $showingNewPlaylist) {
        TextField("Name", text: $newPlaylistName)
        Button("Create") {
          let name = newPlaylistName
          newPlaylistName = ""
          Task {
            await library.createPlaylist(named: name)
          }
        }
        Button("Cancel", role: .cancel) {
          newPlaylistName = ""
        }
      } message: {
        Text("Give your new playlist a name.")
      }
      .refreshable {
        await library.loadPlaylists(force: true)
      }
      .overlay {
        if library.playlists.isEmpty {
          ContentUnavailableView(
            "No Playlists",
            systemImage: "rectangle.stack",
            description: Text("Create a playlist to organize photos for your frames.")
          )
        }
      }
      .task(id: library.serverURLString) {
        await library.loadPlaylists()
      }
    }
  }
}

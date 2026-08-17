import SwiftUI

struct PlaylistDetailView: View {
  @Environment(LibraryStore.self) private var library
  var playlist: MeuralPlaylist

  @State private var items: [MeuralPhoto] = []
  @State private var isLoading = true

  private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 2) {
        ForEach(items) { photo in
          PhotoGridCell(photo: photo)
            .contextMenu {
              Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive) {
                Task {
                  if await library.removePhoto(photo.id, fromPlaylist: playlist.id) {
                    items.removeAll { $0.id == photo.id }
                  }
                }
              }
            }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .navigationTitle(playlist.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Display on Frame", systemImage: "photo.artframe") {
          ForEach(library.frames) { frame in
            Button(frame.displayName) {
              Task {
                await library.assignPlaylist(playlist.id, toFrame: frame.id)
              }
            }
          }
        }
        .disabled(library.frames.isEmpty)
      }
    }
    .overlay {
      if items.isEmpty {
        if isLoading {
          ProgressView("Loading…")
        } else {
          ContentUnavailableView(
            "Empty Playlist",
            systemImage: "rectangle.stack",
            description: Text("Add photos from the Photos tab using the Add to Playlist menu.")
          )
        }
      }
    }
    .task {
      items = await library.playlistItems(id: playlist.id)
      isLoading = false
      await library.loadFrames()
    }
  }
}

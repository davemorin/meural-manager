import SwiftUI

struct PhotoDetailView: View {
  @Environment(LibraryStore.self) private var library
  @Environment(\.dismiss) private var dismiss
  var photo: MeuralPhoto

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        AsyncImage(url: photo.imageURL) { image in
          image
            .resizable()
            .scaledToFit()
        } placeholder: {
          Color(.secondarySystemBackground)
            .frame(height: 320)
            .overlay {
              ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(photo.displayName)

        VStack(alignment: .leading, spacing: 8) {
          Text(photo.displayName)
            .font(.title2.bold())
          if let description = photo.description, !description.isEmpty, description != photo.name {
            Text(description)
              .foregroundStyle(.secondary)
          }
          if let author = photo.author, !author.isEmpty {
            Label(author, systemImage: "person")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("More", systemImage: "ellipsis") {
          Menu("Add to Playlist", systemImage: "rectangle.stack.badge.plus") {
            ForEach(library.playlists) { playlist in
              Button(playlist.displayName) {
                Task {
                  await library.addPhoto(photo.id, toPlaylist: playlist.id)
                }
              }
            }
          }
          Button("Delete", systemImage: "trash", role: .destructive) {
            Task {
              await library.deletePhotos(ids: [photo.id])
              dismiss()
            }
          }
        }
      }
    }
    .task {
      await library.loadPlaylists()
    }
  }
}

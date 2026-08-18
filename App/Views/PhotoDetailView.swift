import ImageIO
import SwiftUI

struct PhotoDetailView: View {
  @Environment(LibraryStore.self) private var library
  @Environment(\.dismiss) private var dismiss
  var photo: MeuralPhoto

  @State private var fileSize: Int64?
  @State private var pixelWidth: Int?
  @State private var pixelHeight: Int?

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

        VStack(spacing: 0) {
          if let fileSize {
            metadataRow("File Size", fileSize.formatted(.byteCount(style: .file)))
            Divider()
          }
          if let pixelWidth, let pixelHeight {
            metadataRow("Dimensions", "\(pixelWidth) × \(pixelHeight)")
            Divider()
          }
          if let orientation = photo.orientation, !orientation.isEmpty {
            metadataRow("Orientation", orientation.capitalized)
          }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
      fileSize = await library.fetchSize(for: photo)
      await loadDimensions()
    }
  }

  private func metadataRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
    }
    .font(.subheadline)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private func loadDimensions() async {
    guard let url = photo.imageURL,
          let (data, _) = try? await URLSession.shared.data(from: url),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return }
    pixelWidth = width
    pixelHeight = height
  }
}

import PhotosUI
import SwiftUI

struct PhotosView: View {
  @Environment(LibraryStore.self) private var library
  @State private var isSelecting = false
  @State private var selection: Set<Int> = []
  @State private var confirmingDelete = false
  @State private var detailPhoto: MeuralPhoto?
  @State private var pickerItems: [PhotosPickerItem] = []

  private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 2) {
          ForEach(library.photos) { photo in
            Button {
              if isSelecting {
                toggleSelection(photo.id)
              } else {
                detailPhoto = photo
              }
            } label: {
              PhotoGridCell(
                photo: photo,
                showsSelection: isSelecting,
                isSelected: selection.contains(photo.id)
              )
            }
            .buttonStyle(.plain)
            .contextMenu {
              photoActions(photo)
            }
            .task {
              await library.loadMorePhotos(after: photo)
            }
          }
        }
        if library.isLoadingPhotos && !library.photos.isEmpty {
          ProgressView()
            .padding()
        }
      }
      .frame(maxWidth: .infinity)
      .navigationTitle(isSelecting ? "\(selection.count) Selected" : "Photos")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(item: $detailPhoto) { photo in
        PhotoDetailView(photo: photo)
      }
      .toolbar {
        if isSelecting {
          ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
              isSelecting = false
              selection = []
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              confirmingDelete = true
            }
            .disabled(selection.isEmpty)
          }
        } else {
          ToolbarItem(placement: .topBarLeading) {
            PhotosPicker(selection: $pickerItems, matching: .images) {
              Label("Add Photos", systemImage: "plus")
            }
            .disabled(library.isUploading)
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("Select") {
              isSelecting = true
            }
          }
        }
      }
      .onChange(of: pickerItems) { _, items in
        guard !items.isEmpty else { return }
        Task {
          var photoData: [Data] = []
          for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
              photoData.append(data)
            }
          }
          pickerItems = []
          await library.uploadPhotos(photoData)
        }
      }
      .safeAreaInset(edge: .bottom) {
        if library.isUploading {
          VStack(alignment: .leading, spacing: 6) {
            Text("Uploading \(min(library.uploadCompleted + 1, library.uploadTotal)) of \(library.uploadTotal)…")
              .font(.footnote)
              .foregroundStyle(.secondary)
            ProgressView(value: Double(library.uploadCompleted), total: Double(max(library.uploadTotal, 1)))
          }
          .padding(.horizontal)
          .padding(.vertical, 10)
          .frame(maxWidth: .infinity)
          .background(.bar)
        }
      }
      .refreshable {
        await library.refreshPhotos()
      }
      .overlay {
        if library.photos.isEmpty {
          if library.isLoadingPhotos {
            ProgressView("Loading Photos…")
          } else {
            ContentUnavailableView(
              "No Photos",
              systemImage: "photo.on.rectangle.angled",
              description: Text("Photos from your Meural library will appear here.")
            )
          }
        }
      }
      .confirmationDialog(
        "Delete ^[\(selection.count) photo](inflect: true) from your Meural library?",
        isPresented: $confirmingDelete,
        titleVisibility: .visible
      ) {
        Button("Delete ^[\(selection.count) Photo](inflect: true)", role: .destructive) {
          let ids = Array(selection)
          selection = []
          isSelecting = false
          Task {
            await library.deletePhotos(ids: ids)
          }
        }
      }
      .task {
        await library.loadInitialPhotos()
        await library.loadPlaylists()
      }
    }
  }

  @ViewBuilder
  private func photoActions(_ photo: MeuralPhoto) -> some View {
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
      }
    }
  }

  private func toggleSelection(_ id: Int) {
    if selection.contains(id) {
      selection.remove(id)
    } else {
      selection.insert(id)
    }
  }
}

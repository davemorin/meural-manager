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
          ForEach(library.displayedPhotos) { photo in
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
                isSelected: selection.contains(photo.id),
                sizeLabel: sizeLabel(for: photo)
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
          ToolbarItemGroup(placement: .topBarLeading) {
            PhotosPicker(selection: $pickerItems, matching: .images) {
              Label("Add Photos", systemImage: "plus")
            }
            .disabled(library.isUploading)
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
              Picker("Sort", selection: sortBinding) {
                ForEach(PhotoSort.allCases, id: \.self) { sort in
                  Text(sort.label).tag(sort)
                }
              }
            }
            .disabled(library.isSizingPhotos)
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
          progressBar(
            label: "Uploading \(min(library.uploadCompleted + 1, library.uploadTotal)) of \(library.uploadTotal)…",
            completed: library.uploadCompleted,
            total: library.uploadTotal
          )
        } else if library.isSizingPhotos {
          progressBar(
            label: "Checking sizes — \(library.sizingCompleted) of \(library.sizingTotal)…",
            completed: library.sizingCompleted,
            total: library.sizingTotal
          )
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

  private var sortBinding: Binding<PhotoSort> {
    Binding {
      library.sortOrder
    } set: { newValue in
      Task {
        await library.setSort(newValue)
      }
    }
  }

  private func sizeLabel(for photo: MeuralPhoto) -> String? {
    guard library.sortOrder != .newest, let size = library.photoSizes[photo.id], size > 0 else { return nil }
    return size.formatted(.byteCount(style: .file))
  }

  private func progressBar(label: String, completed: Int, total: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.footnote)
        .foregroundStyle(.secondary)
      ProgressView(value: Double(completed), total: Double(max(total, 1)))
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(.bar)
  }

  private func toggleSelection(_ id: Int) {
    if selection.contains(id) {
      selection.remove(id)
    } else {
      selection.insert(id)
    }
  }
}

import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
  var photos: [MeuralPhoto] = []
  var playlists: [MeuralPlaylist] = []
  var frames: [MeuralFrame] = []

  var isLoadingPhotos = false
  var errorMessage: String?

  var serverURLString: String {
    didSet {
      guard oldValue != serverURLString else { return }
      UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
      photos = []
      playlists = []
      frames = []
      nextPage = 1
      hasMorePhotos = true
    }
  }

  static let serverURLKey = "serverURL"
  static let defaultServerURL = "http://localhost:3333"

  private var nextPage = 1
  private var hasMorePhotos = true

  init() {
    serverURLString = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? Self.defaultServerURL
  }

  // MARK: - Photos

  func loadInitialPhotos() async {
    guard photos.isEmpty else { return }
    await refreshPhotos()
  }

  func refreshPhotos() async {
    nextPage = 1
    hasMorePhotos = true
    await loadNextPhotoPage(replacing: true)
  }

  func loadMorePhotos(after photo: MeuralPhoto) async {
    guard photo.id == photos.last?.id, hasMorePhotos else { return }
    await loadNextPhotoPage(replacing: false)
  }

  private func loadNextPhotoPage(replacing: Bool) async {
    guard !isLoadingPhotos, let client = requireClient() else { return }
    isLoadingPhotos = true
    defer { isLoadingPhotos = false }
    do {
      let result = try await client.fetchPhotos(page: nextPage)
      if replacing {
        photos = result.photos
      } else {
        photos.append(contentsOf: result.photos)
      }
      hasMorePhotos = !result.isLast
      nextPage += 1
    } catch {
      report(error)
    }
  }

  func deletePhotos(ids: [Int]) async {
    guard !ids.isEmpty, let client = requireClient() else { return }
    do {
      try await client.bulkDeletePhotos(ids: ids)
      photos.removeAll { ids.contains($0.id) }
    } catch {
      report(error)
    }
  }

  // MARK: - Playlists

  func loadPlaylists(force: Bool = false) async {
    guard force || playlists.isEmpty else { return }
    guard let client = requireClient() else { return }
    do {
      playlists = try await client.fetchPlaylists()
    } catch {
      report(error)
    }
  }

  func playlistItems(id: Int) async -> [MeuralPhoto] {
    guard let client = requireClient() else { return [] }
    do {
      return try await client.fetchPlaylistItems(id: id)
    } catch {
      report(error)
      return []
    }
  }

  func createPlaylist(named name: String) async {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let client = requireClient() else { return }
    do {
      try await client.createPlaylist(name: trimmed)
      await loadPlaylists(force: true)
    } catch {
      report(error)
    }
  }

  func deletePlaylists(at offsets: IndexSet) async {
    guard let client = requireClient() else { return }
    let toDelete = offsets.compactMap { playlists.indices.contains($0) ? playlists[$0] : nil }
    for playlist in toDelete {
      do {
        try await client.deletePlaylist(id: playlist.id)
        playlists.removeAll { $0.id == playlist.id }
      } catch {
        report(error)
      }
    }
  }

  func addPhoto(_ photoID: Int, toPlaylist playlistID: Int) async {
    guard let client = requireClient() else { return }
    do {
      try await client.addPhoto(photoID, toPlaylist: playlistID)
      await loadPlaylists(force: true)
    } catch {
      report(error)
    }
  }

  @discardableResult
  func removePhoto(_ photoID: Int, fromPlaylist playlistID: Int) async -> Bool {
    guard let client = requireClient() else { return false }
    do {
      try await client.removePhoto(photoID, fromPlaylist: playlistID)
      await loadPlaylists(force: true)
      return true
    } catch {
      report(error)
      return false
    }
  }

  // MARK: - Frames

  func loadFrames(force: Bool = false) async {
    guard force || frames.isEmpty else { return }
    guard let client = requireClient() else { return }
    do {
      frames = try await client.fetchFrames()
    } catch {
      report(error)
    }
  }

  func assignPlaylist(_ playlistID: Int, toFrame frameID: Int) async {
    guard let client = requireClient() else { return }
    do {
      try await client.assignPlaylist(playlistID, toFrame: frameID)
      await loadFrames(force: true)
    } catch {
      report(error)
    }
  }

  // MARK: - Helpers

  private var client: MeuralClient? {
    URL(string: serverURLString).map(MeuralClient.init)
  }

  private func requireClient() -> MeuralClient? {
    guard let client else {
      errorMessage = "The server address is invalid. Update it in Settings."
      return nil
    }
    return client
  }

  private func report(_ error: Error) {
    errorMessage = error.localizedDescription
  }
}

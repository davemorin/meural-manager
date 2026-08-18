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

  private let session: MeuralSession
  private var nextPage = 1
  private var hasMorePhotos = true

  init(session: MeuralSession) {
    self.session = session
  }

  func reset() {
    photos = []
    playlists = []
    frames = []
    nextPage = 1
    hasMorePhotos = true
    errorMessage = nil
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
    guard !isLoadingPhotos else { return }
    isLoadingPhotos = true
    defer { isLoadingPhotos = false }
    do {
      let result = try await withClient { try await $0.fetchPhotos(page: nextPage) }
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
    guard !ids.isEmpty else { return }
    do {
      let deleted = try await withClient { try await $0.deletePhotos(ids: ids) }
      photos.removeAll { deleted.contains($0.id) }
      if deleted.count < ids.count {
        errorMessage = "Deleted \(deleted.count) of \(ids.count) photos. Try the rest again."
      }
    } catch {
      report(error)
    }
  }

  // MARK: - Playlists

  func loadPlaylists(force: Bool = false) async {
    guard force || playlists.isEmpty else { return }
    do {
      playlists = try await withClient { try await $0.fetchPlaylists() }
    } catch {
      report(error)
    }
  }

  func playlistItems(id: Int) async -> [MeuralPhoto] {
    do {
      return try await withClient { try await $0.fetchPlaylistItems(id: id) }
    } catch {
      report(error)
      return []
    }
  }

  func createPlaylist(named name: String) async {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    do {
      try await withClient { try await $0.createPlaylist(name: trimmed) }
      await loadPlaylists(force: true)
    } catch {
      report(error)
    }
  }

  func deletePlaylists(at offsets: IndexSet) async {
    let toDelete = offsets.compactMap { playlists.indices.contains($0) ? playlists[$0] : nil }
    for playlist in toDelete {
      do {
        try await withClient { try await $0.deletePlaylist(id: playlist.id) }
        playlists.removeAll { $0.id == playlist.id }
      } catch {
        report(error)
      }
    }
  }

  func addPhoto(_ photoID: Int, toPlaylist playlistID: Int) async {
    do {
      try await withClient { try await $0.addPhoto(photoID, toPlaylist: playlistID) }
      await loadPlaylists(force: true)
    } catch {
      report(error)
    }
  }

  @discardableResult
  func removePhoto(_ photoID: Int, fromPlaylist playlistID: Int) async -> Bool {
    do {
      try await withClient { try await $0.removePhoto(photoID, fromPlaylist: playlistID) }
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
    do {
      frames = try await withClient { try await $0.fetchFrames() }
    } catch {
      report(error)
    }
  }

  func assignPlaylist(_ playlistID: Int, toFrame frameID: Int) async {
    do {
      try await withClient { try await $0.assignPlaylist(playlistID, toFrame: frameID) }
      await loadFrames(force: true)
    } catch {
      report(error)
    }
  }

  // MARK: - Helpers

  /// Runs a request with a valid token, re-authenticating and retrying once
  /// if Meural rejects the token early.
  private func withClient<T>(_ body: (MeuralClient) async throws -> T) async throws -> T {
    let token = try await session.validToken()
    do {
      return try await body(MeuralClient(token: token))
    } catch let error as MeuralClientError where error.isUnauthorized {
      session.invalidateToken()
      let freshToken = try await session.validToken()
      return try await body(MeuralClient(token: freshToken))
    }
  }

  private func report(_ error: Error) {
    errorMessage = error.localizedDescription
  }
}

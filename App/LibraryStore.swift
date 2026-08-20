import Foundation
import Observation

enum PhotoSort: String, CaseIterable {
  case newest
  case largestFirst
  case smallestFirst

  var label: String {
    switch self {
    case .newest: "Recently Added"
    case .largestFirst: "Largest First"
    case .smallestFirst: "Smallest First"
    }
  }
}

@MainActor
@Observable
final class LibraryStore {
  var photos: [MeuralPhoto] = []
  var playlists: [MeuralPlaylist] = []
  var frames: [MeuralFrame] = []
  var user: MeuralUser?

  var isLoadingPhotos = false
  var isUploading = false
  var uploadCompleted = 0
  var uploadTotal = 0
  var errorMessage: String?

  var sortOrder: PhotoSort = .newest
  // Original-file sizes in bytes, probed from the CDN; 0 marks a failed probe.
  var photoSizes: [Int: Int64] = [:]
  var isSizingPhotos = false
  var sizingCompleted = 0
  var sizingTotal = 0

  var displayedPhotos: [MeuralPhoto] {
    switch sortOrder {
    case .newest:
      photos
    case .largestFirst:
      photos.sorted { (photoSizes[$0.id] ?? 0) > (photoSizes[$1.id] ?? 0) }
    case .smallestFirst:
      photos.sorted { (photoSizes[$0.id] ?? 0) < (photoSizes[$1.id] ?? 0) }
    }
  }

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
    user = nil
    sortOrder = .newest
    photoSizes = [:]
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
      report(error, "Couldn't load photos")
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
      await loadUser(force: true)
    } catch {
      report(error, "Couldn't delete photos")
    }
  }

  func setSort(_ sort: PhotoSort) async {
    sortOrder = sort
    guard sort != .newest else { return }
    await loadAllPhotos()
    await fetchMissingSizes()
  }

  /// Loads every remaining page so size sorting and backup cover the whole library.
  func loadAllPhotos() async {
    while hasMorePhotos {
      let before = photos.count
      await loadNextPhotoPage(replacing: false)
      if photos.count == before { break }
    }
  }

  private func fetchMissingSizes() async {
    guard !isSizingPhotos else { return }
    let missing = photos.filter { photoSizes[$0.id] == nil && $0.sizeProbeURL != nil }
    guard !missing.isEmpty else { return }
    isSizingPhotos = true
    sizingCompleted = 0
    sizingTotal = missing.count
    defer { isSizingPhotos = false }

    for chunk in missing.chunked(into: 6) {
      await withTaskGroup(of: (Int, Int64?).self) { group in
        for photo in chunk {
          guard let url = photo.sizeProbeURL else { continue }
          let id = photo.id
          group.addTask {
            (id, await Self.contentLength(of: url))
          }
        }
        for await (id, size) in group {
          photoSizes[id] = size ?? 0
          sizingCompleted += 1
        }
      }
    }
  }

  func fetchSize(for photo: MeuralPhoto) async -> Int64? {
    if let cached = photoSizes[photo.id] {
      return cached > 0 ? cached : nil
    }
    guard let url = photo.sizeProbeURL else { return nil }
    let size = await Self.contentLength(of: url)
    photoSizes[photo.id] = size ?? 0
    return size
  }

  private nonisolated static func contentLength(of url: URL) async -> Int64? {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 15
    if let (_, response) = try? await URLSession.shared.data(for: request),
       response.expectedContentLength > 0 {
      return response.expectedContentLength
    }
    // Some CDNs reject HEAD; ask for a single byte and read the full size
    // from the Content-Range header instead.
    var rangeRequest = URLRequest(url: url)
    rangeRequest.timeoutInterval = 15
    rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    guard let (_, response) = try? await URLSession.shared.data(for: rangeRequest),
          let http = response as? HTTPURLResponse,
          let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
          let totalPart = contentRange.split(separator: "/").last,
          let total = Int64(totalPart), total > 0 else { return nil }
    return total
  }

  func uploadPhotos(_ photoData: [Data]) async {
    guard !photoData.isEmpty, !isUploading else { return }
    isUploading = true
    uploadCompleted = 0
    uploadTotal = photoData.count
    defer { isUploading = false }

    var failures = 0
    for data in photoData {
      if let upload = await UploadPreparer.prepare(data) {
        do {
          try await withClient { try await $0.uploadPhoto(upload) }
        } catch {
          failures += 1
        }
      } else {
        failures += 1
      }
      uploadCompleted += 1
    }

    await refreshPhotos()
    await loadUser(force: true)
    if failures == photoData.count {
      errorMessage = "Couldn't upload the selected photos."
    } else if failures > 0 {
      errorMessage = "Uploaded \(photoData.count - failures) of \(photoData.count) photos. \(failures) failed."
    }
  }

  // MARK: - Playlists

  func loadPlaylists(force: Bool = false) async {
    guard force || playlists.isEmpty else { return }
    do {
      playlists = try await withClient { try await $0.fetchPlaylists() }
    } catch {
      report(error, "Couldn't load playlists")
    }
  }

  func playlistItems(id: Int) async -> [MeuralPhoto] {
    do {
      return try await withClient { try await $0.fetchPlaylistItems(id: id) }
    } catch {
      report(error, "Couldn't load the playlist")
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
      report(error, "Couldn't create the playlist")
    }
  }

  func deletePlaylists(at offsets: IndexSet) async {
    let toDelete = offsets.compactMap { playlists.indices.contains($0) ? playlists[$0] : nil }
    for playlist in toDelete {
      do {
        try await withClient { try await $0.deletePlaylist(id: playlist.id) }
        playlists.removeAll { $0.id == playlist.id }
      } catch {
        report(error, "Couldn't delete the playlist")
      }
    }
  }

  func addPhoto(_ photoID: Int, toPlaylist playlistID: Int) async {
    do {
      try await withClient { try await $0.addPhoto(photoID, toPlaylist: playlistID) }
      await loadPlaylists(force: true)
    } catch {
      report(error, "Couldn't add to the playlist")
    }
  }

  @discardableResult
  func removePhoto(_ photoID: Int, fromPlaylist playlistID: Int) async -> Bool {
    do {
      try await withClient { try await $0.removePhoto(photoID, fromPlaylist: playlistID) }
      await loadPlaylists(force: true)
      return true
    } catch {
      report(error, "Couldn't remove from the playlist")
      return false
    }
  }

  // MARK: - Account

  func loadUser(force: Bool = false) async {
    guard force || user == nil else { return }
    do {
      user = try await withClient { try await $0.fetchUser() }
    } catch {
      report(error, "Couldn't load account info")
    }
  }

  // MARK: - Frames

  func loadFrames(force: Bool = false) async {
    guard force || frames.isEmpty else { return }
    do {
      frames = try await withClient { try await $0.fetchFrames() }
    } catch {
      report(error, "Couldn't load frames")
    }
  }

  func assignPlaylist(_ playlistID: Int, toFrame frameID: Int) async {
    do {
      try await withClient { try await $0.assignPlaylist(playlistID, toFrame: frameID) }
      await loadFrames(force: true)
    } catch {
      report(error, "Couldn't update the frame")
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

  private func report(_ error: Error, _ context: String) {
    errorMessage = "\(context). \(Self.describe(error))"
  }

  private static func describe(_ error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
      return error.localizedDescription
    }
    switch decodingError {
    case .keyNotFound(let key, _):
      return "Meural sent unexpected data (missing \"\(key.stringValue)\")."
    case .typeMismatch(_, let context):
      return "Meural sent unexpected data (wrong type at \(Self.path(context)))."
    case .valueNotFound(_, let context):
      return "Meural sent unexpected data (missing value at \(Self.path(context)))."
    case .dataCorrupted(let context):
      return "Meural sent unexpected data (\(context.debugDescription))"
    @unknown default:
      return "Meural sent unexpected data."
    }
  }

  private static func path(_ context: DecodingError.Context) -> String {
    let path = context.codingPath.map(\.stringValue).joined(separator: ".")
    return path.isEmpty ? "top level" : "\"\(path)\""
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}

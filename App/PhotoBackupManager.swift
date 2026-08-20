import Foundation
import Observation
import Photos

/// Backs up the Meural library into an album in the user's Photos library,
/// keeping a ledger of already-saved photo IDs so re-runs only fetch new ones.
@MainActor
@Observable
final class PhotoBackupManager {
  var isBackingUp = false
  var completed = 0
  var total = 0
  var statusMessage: String?

  private var cancelRequested = false

  private static let recordsKey = "backedUpPhotoIDs"
  private static let albumName = "Artwall"

  private var records: Set<Int> {
    get { Set(UserDefaults.standard.array(forKey: Self.recordsKey) as? [Int] ?? []) }
    set { UserDefaults.standard.set(Array(newValue), forKey: Self.recordsKey) }
  }

  var backedUpCount: Int { records.count }

  func cancel() {
    cancelRequested = true
  }

  func backUp(_ photos: [MeuralPhoto]) async {
    guard !isBackingUp else { return }
    isBackingUp = true
    cancelRequested = false
    statusMessage = nil
    defer { isBackingUp = false }

    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized || status == .limited else {
      statusMessage = "Photos access is turned off. Allow it in Settings → Privacy → Photos."
      return
    }

    let albumID: String
    do {
      albumID = try await fetchOrCreateAlbumID()
    } catch {
      statusMessage = "Couldn't create the \"\(Self.albumName)\" album. \(error.localizedDescription)"
      return
    }

    var saved = records
    let pending = photos.filter { !saved.contains($0.id) && $0.sizeProbeURL != nil }
    total = pending.count
    completed = 0
    guard !pending.isEmpty else {
      statusMessage = "Everything is already backed up (\(saved.count) photos)."
      return
    }

    var failures = 0
    for photo in pending {
      if cancelRequested { break }
      do {
        try await save(photo, toAlbum: albumID)
        saved.insert(photo.id)
        records = saved
      } catch {
        failures += 1
      }
      completed += 1
    }

    if cancelRequested {
      statusMessage = "Backup paused at \(completed) of \(total) — run it again to continue."
    } else if failures > 0 {
      statusMessage = "Backed up \(total - failures) of \(total) photos. \(failures) failed — run it again to retry."
    } else {
      statusMessage = "Backed up \(total) new photos to the \"\(Self.albumName)\" album."
    }
  }

  private func save(_ photo: MeuralPhoto, toAlbum albumID: String) async throws {
    guard let url = photo.sizeProbeURL else {
      throw MeuralClientError(message: "No image available.")
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw MeuralClientError(message: "Download failed (HTTP \(http.statusCode)).")
    }
    try await PHPhotoLibrary.shared().performChanges {
      let creation = PHAssetCreationRequest.forAsset()
      creation.addResource(with: .photo, data: data, options: nil)
      if let placeholder = creation.placeholderForCreatedAsset,
         let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
         let change = PHAssetCollectionChangeRequest(for: album) {
        change.addAssets([placeholder] as NSArray)
      }
    }
  }

  private func fetchOrCreateAlbumID() async throws -> String {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title = %@", Self.albumName)
    if let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject {
      return existing.localIdentifier
    }
    try await PHPhotoLibrary.shared().performChanges {
      PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Self.albumName)
    }
    guard let created = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject else {
      throw MeuralClientError(message: "The album could not be found after creating it.")
    }
    return created.localIdentifier
  }
}

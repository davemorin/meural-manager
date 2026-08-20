import Foundation
import ImageIO
import Observation
import Photos
import UIKit

/// Rebuilds the Meural library as an album of originals in the user's
/// Photos library. Each Meural photo is downloaded only to read its
/// signature — EXIF capture time and pixel dimensions — which is used to
/// find the matching original asset; the original, not a copy, is added
/// to the album. Ledgers of matched and unmatched IDs keep re-runs
/// incremental.
@MainActor
@Observable
final class PhotoAlbumBuilder {
  var isMatching = false
  var completed = 0
  var total = 0
  var activity = "Matching"
  var statusMessage: String?

  var unmatchedCount: Int { unmatched.count }

  private var cancelRequested = false

  private static let matchedKey = "matchedPhotoIDs"
  private static let unmatchedKey = "unmatchedPhotoIDs"
  private static let albumName = "Artwall"

  private var matched: Set<Int> {
    get { Set(UserDefaults.standard.array(forKey: Self.matchedKey) as? [Int] ?? []) }
    set { UserDefaults.standard.set(Array(newValue), forKey: Self.matchedKey) }
  }

  private var unmatched: Set<Int> {
    get { Set(UserDefaults.standard.array(forKey: Self.unmatchedKey) as? [Int] ?? []) }
    set { UserDefaults.standard.set(Array(newValue), forKey: Self.unmatchedKey) }
  }

  func cancel() {
    cancelRequested = true
  }

  func buildAlbum(from photos: [MeuralPhoto]) async {
    guard !isMatching else { return }
    isMatching = true
    cancelRequested = false
    statusMessage = nil
    defer { isMatching = false }

    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized else {
      statusMessage = "Artwall needs full Photos access to find your originals. Allow it in Settings → Privacy → Photos."
      return
    }

    let albumID: String
    do {
      albumID = try await fetchOrCreateAlbumID()
    } catch {
      statusMessage = "Couldn't create the \"\(Self.albumName)\" album. \(error.localizedDescription)"
      return
    }

    activity = "Matching"
    var matchedIDs = matched
    var unmatchedIDs = unmatched
    let pending = photos.filter {
      !matchedIDs.contains($0.id) && !unmatchedIDs.contains($0.id) && $0.sizeProbeURL != nil
    }
    total = pending.count
    completed = 0
    guard !pending.isEmpty else {
      statusMessage = summary(newMatches: 0, newMisses: 0)
      return
    }

    var newMatches = 0
    var newMisses = 0
    for photo in pending {
      if cancelRequested { break }
      if let assetID = await matchAsset(for: photo) {
        do {
          try await add(assetID: assetID, toAlbum: albumID)
          matchedIDs.insert(photo.id)
          matched = matchedIDs
          newMatches += 1
        } catch {
          newMisses += 1
        }
      } else {
        unmatchedIDs.insert(photo.id)
        unmatched = unmatchedIDs
        newMisses += 1
      }
      completed += 1
    }

    if cancelRequested {
      statusMessage = "Paused at \(completed) of \(total) — run it again to continue."
    } else {
      statusMessage = summary(newMatches: newMatches, newMisses: newMisses)
    }
  }

  private func summary(newMatches: Int, newMisses: Int) -> String {
    var parts: [String] = []
    if newMatches > 0 || newMisses > 0 {
      parts.append("Added \(newMatches) originals to the \"\(Self.albumName)\" album.")
    }
    parts.append("\(matched.count) photos matched in total.")
    if !unmatched.isEmpty {
      parts.append("\(unmatched.count) had no matching original in your library.")
    }
    return parts.joined(separator: " ")
  }

  // MARK: - Visual matching

  /// Second pass for photos whose EXIF signature found no original:
  /// fingerprints the whole photo library once (cached on disk), then
  /// pairs each unmatched Meural photo with the visually identical asset.
  func visualMatch(photos: [MeuralPhoto]) async {
    guard !isMatching else { return }
    isMatching = true
    cancelRequested = false
    statusMessage = nil
    defer { isMatching = false }

    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized else {
      statusMessage = "Artwall needs full Photos access to find your originals. Allow it in Settings → Privacy → Photos."
      return
    }

    let albumID: String
    do {
      albumID = try await fetchOrCreateAlbumID()
    } catch {
      statusMessage = "Couldn't create the \"\(Self.albumName)\" album. \(error.localizedDescription)"
      return
    }

    let targets = photos.filter { unmatched.contains($0.id) && $0.sizeProbeURL != nil }
    guard !targets.isEmpty else {
      statusMessage = "No unmatched photos to retry."
      return
    }

    var index = loadHashIndex()
    let allIDs = await Self.allImageAssetIDs()
    let missing = allIDs.filter { index[$0] == nil }
    if !missing.isEmpty {
      activity = "Fingerprinting library"
      total = missing.count
      completed = 0
      for chunk in missing.chunked(into: 200) {
        if cancelRequested { break }
        let hashes = await Self.hashAssets(ids: chunk)
        index.merge(hashes) { _, new in new }
        completed += chunk.count
      }
      saveHashIndex(index)
    }
    if cancelRequested {
      statusMessage = "Paused — run Visual Match again to continue."
      return
    }

    activity = "Visual matching"
    total = targets.count
    completed = 0
    var matchedIDs = matched
    var unmatchedIDs = unmatched
    var newMatches = 0
    for photo in targets {
      if cancelRequested { break }
      if let url = photo.sizeProbeURL,
         let data = await Self.download(url, rangeBytes: nil),
         let hash = PerceptualHash.dHash(fromImageData: data),
         let assetID = Self.bestVisualMatch(for: hash, in: index) {
        do {
          try await add(assetID: assetID, toAlbum: albumID)
          matchedIDs.insert(photo.id)
          unmatchedIDs.remove(photo.id)
          matched = matchedIDs
          unmatched = unmatchedIDs
          newMatches += 1
        } catch {
          // Leave it unmatched so the next run retries.
        }
      }
      completed += 1
    }

    if cancelRequested {
      statusMessage = "Paused at \(completed) of \(total) — run Visual Match again to continue."
    } else {
      statusMessage = "Visually matched \(newMatches) more photos. \(unmatchedIDs.count) still have no match."
    }
  }

  private nonisolated static func allImageAssetIDs() async -> [String] {
    let fetch = PHAsset.fetchAssets(with: .image, options: nil)
    var ids: [String] = []
    fetch.enumerateObjects { asset, _, _ in
      ids.append(asset.localIdentifier)
    }
    return ids
  }

  private nonisolated static func hashAssets(ids: [String]) async -> [String: UInt64] {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    let manager = PHImageManager.default()
    let options = PHImageRequestOptions()
    options.isSynchronous = true
    options.deliveryMode = .fastFormat
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = false
    var hashes: [String: UInt64] = [:]
    assets.enumerateObjects { asset, _, _ in
      manager.requestImage(
        for: asset,
        targetSize: CGSize(width: 64, height: 64),
        contentMode: .aspectFit,
        options: options
      ) { image, _ in
        if let cgImage = image?.cgImage, let hash = PerceptualHash.dHash(from: cgImage) {
          hashes[asset.localIdentifier] = hash
        }
      }
    }
    return hashes
  }

  /// Accepts the closest fingerprint only when it is near-identical, or
  /// clearly better than the runner-up.
  private nonisolated static func bestVisualMatch(for hash: UInt64, in index: [String: UInt64]) -> String? {
    var best: (id: String, distance: Int)?
    var runnerUp = Int.max
    for (id, candidate) in index {
      let distance = PerceptualHash.distance(hash, candidate)
      if let current = best {
        if distance < current.distance {
          runnerUp = current.distance
          best = (id, distance)
        } else if distance < runnerUp {
          runnerUp = distance
        }
      } else {
        best = (id, distance)
      }
    }
    guard let best else { return nil }
    if best.distance <= 6 { return best.id }
    if best.distance <= 10, runnerUp - best.distance >= 4 { return best.id }
    return nil
  }

  private var hashIndexFileURL: URL {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "photo-hash-index.json")
  }

  private func loadHashIndex() -> [String: UInt64] {
    guard let data = try? Data(contentsOf: hashIndexFileURL),
          let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return raw.compactMapValues { UInt64($0, radix: 16) }
  }

  private func saveHashIndex(_ index: [String: UInt64]) {
    let raw = index.mapValues { String($0, radix: 16) }
    if let data = try? JSONEncoder().encode(raw) {
      try? data.write(to: hashIndexFileURL)
    }
  }

  // MARK: - Matching

  private func matchAsset(for photo: MeuralPhoto) async -> String? {
    guard let url = photo.sizeProbeURL else { return nil }

    // The signature lives in the file header, so try a small ranged
    // download first and fall back to the full file.
    var signature: RemoteSignature?
    if let partial = await Self.download(url, rangeBytes: 512 * 1024) {
      signature = Self.signature(from: partial)
    }
    if signature?.captureDate == nil, let full = await Self.download(url, rangeBytes: nil) {
      signature = Self.signature(from: full)
    }
    guard let signature, signature.captureDate != nil else { return nil }
    return await Self.findAsset(matching: signature)
  }

  private struct RemoteSignature {
    var captureDate: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?
  }

  private nonisolated static func download(_ url: URL, rangeBytes: Int?) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    if let rangeBytes {
      request.setValue("bytes=0-\(rangeBytes - 1)", forHTTPHeaderField: "Range")
    }
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode) else { return nil }
    return data
  }

  private nonisolated static func signature(from data: Data) -> RemoteSignature? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
      return nil
    }
    var captureDate: Date?
    if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
       let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = .current
      formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
      captureDate = formatter.date(from: dateString)
    }
    return RemoteSignature(
      captureDate: captureDate,
      pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int,
      pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int
    )
  }

  /// Finds the library asset whose capture time matches the signature.
  /// EXIF times carry no timezone, so candidates are gathered across a
  /// ±14 hour window and accepted when their offset is a whole number of
  /// half hours (a timezone difference), ranked by closeness and size.
  private nonisolated static func findAsset(matching signature: RemoteSignature) async -> String? {
    guard let date = signature.captureDate else { return nil }
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
      format: "creationDate >= %@ AND creationDate <= %@ AND mediaType = %d",
      date.addingTimeInterval(-14 * 3600) as NSDate,
      date.addingTimeInterval(14 * 3600) as NSDate,
      PHAssetMediaType.image.rawValue
    )
    let fetch = PHAsset.fetchAssets(with: options)

    var best: (id: String, score: Int, distance: TimeInterval)?
    fetch.enumerateObjects { asset, _, _ in
      guard let created = asset.creationDate else { return }
      let delta = created.timeIntervalSince(date)
      let halfHours = (delta / 1800).rounded()
      guard abs(delta - halfHours * 1800) <= 5 else { return }

      var score = 0
      if abs(delta) <= 5 { score += 4 }
      if let width = signature.pixelWidth, let height = signature.pixelHeight, width > 0, height > 0 {
        if asset.pixelWidth == width && asset.pixelHeight == height {
          score += 4
        } else {
          let assetRatio = Double(asset.pixelWidth) / Double(max(asset.pixelHeight, 1))
          let remoteRatio = Double(width) / Double(height)
          if abs(assetRatio - remoteRatio) < 0.02 { score += 1 }
        }
      }
      let distance = abs(delta)
      if let current = best {
        if score > current.score || (score == current.score && distance < current.distance) {
          best = (asset.localIdentifier, score, distance)
        }
      } else {
        best = (asset.localIdentifier, score, distance)
      }
    }
    return best?.id
  }

  // MARK: - Album

  private func add(assetID: String, toAlbum albumID: String) async throws {
    try await PHPhotoLibrary.shared().performChanges {
      guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject,
            let change = PHAssetCollectionChangeRequest(for: album) else { return }
      change.addAssets([asset] as NSArray)
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

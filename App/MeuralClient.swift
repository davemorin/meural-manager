import Foundation

/// Thin client for the Meural REST API.
struct MeuralClient {
  var token: String

  private static let baseURL = URL(string: "https://api.meural.com/v0")!

  // MARK: - Photos

  func fetchPhotos(page: Int, count: Int = 100) async throws -> (photos: [MeuralPhoto], isLast: Bool) {
    let query = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "count", value: String(count))
    ]
    let data = try await data(for: "GET", path: "user/items", query: query)
    let envelope = try JSONDecoder().decode(APIEnvelope<[MeuralPhoto]>.self, from: data)
    let photos = envelope.data ?? []
    return (photos, envelope.isLast ?? (photos.count < count))
  }

  /// Deletes photos one at a time (the API has no bulk endpoint) and
  /// returns the IDs that were actually deleted.
  func deletePhotos(ids: [Int]) async throws -> [Int] {
    var deleted: [Int] = []
    var firstError: Error?
    for id in ids {
      do {
        _ = try await data(for: "DELETE", path: "items/\(id)")
        deleted.append(id)
      } catch {
        if firstError == nil { firstError = error }
      }
    }
    if deleted.isEmpty, let firstError {
      throw firstError
    }
    return deleted
  }

  func uploadPhoto(_ upload: PhotoUpload) async throws {
    let boundary = "artwall-\(UUID().uuidString)"
    var request = URLRequest(url: Self.baseURL.appending(path: "items"))
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"\(upload.filename)\"\r\n".utf8))
    body.append(Data("Content-Type: \(upload.mimeType)\r\n\r\n".utf8))
    body.append(upload.data)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))

    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    try Self.validate(response, data: data)
  }

  // MARK: - Playlists

  func fetchPlaylists() async throws -> [MeuralPlaylist] {
    try await decodeEnvelope([MeuralPlaylist].self, from: data(for: "GET", path: "user/galleries"))
  }

  func fetchPlaylistItems(id: Int) async throws -> [MeuralPhoto] {
    var allItems: [MeuralPhoto] = []
    var page = 1
    let perPage = 100
    while true {
      let query = [
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "count", value: String(perPage))
      ]
      let data = try await data(for: "GET", path: "galleries/\(id)/items", query: query)
      let envelope = try JSONDecoder().decode(APIEnvelope<[MeuralPhoto]>.self, from: data)
      let items = envelope.data ?? []
      allItems.append(contentsOf: items)
      if items.count < perPage || envelope.isLast == true { break }
      page += 1
    }
    return allItems
  }

  func createPlaylist(name: String) async throws {
    _ = try await data(for: "POST", path: "galleries", body: ["name": name])
  }

  func deletePlaylist(id: Int) async throws {
    _ = try await data(for: "DELETE", path: "galleries/\(id)")
  }

  func addPhoto(_ photoID: Int, toPlaylist playlistID: Int) async throws {
    _ = try await data(for: "POST", path: "galleries/\(playlistID)/items/\(photoID)")
  }

  func removePhoto(_ photoID: Int, fromPlaylist playlistID: Int) async throws {
    _ = try await data(for: "DELETE", path: "galleries/\(playlistID)/items/\(photoID)")
  }

  // MARK: - Frames

  func fetchFrames() async throws -> [MeuralFrame] {
    try await decodeEnvelope([MeuralFrame].self, from: data(for: "GET", path: "user/devices"))
  }

  func assignPlaylist(_ playlistID: Int, toFrame frameID: Int) async throws {
    _ = try await data(for: "POST", path: "devices/\(frameID)/galleries/\(playlistID)")
  }

  // MARK: - Transport

  private struct APIEnvelope<T: Decodable>: Decodable {
    var data: T?
    var isLast: Bool?
    var error: String?
  }

  private struct ServerErrorPayload: Decodable {
    var error: String?
  }

  private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
    if let value = envelope.data { return value }
    throw MeuralClientError(message: envelope.error ?? "Unexpected response from Meural.")
  }

  private func data(
    for method: String,
    path: String,
    query: [URLQueryItem] = [],
    body: [String: any Sendable]? = nil
  ) async throws -> Data {
    guard var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
      throw MeuralClientError(message: "Invalid request.")
    }
    if !query.isEmpty {
      components.queryItems = query
    }
    guard let url = components.url else {
      throw MeuralClientError(message: "Invalid request.")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    try Self.validate(response, data: data)
    return data
  }

  private static func validate(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
    if http.statusCode == 401 {
      throw MeuralClientError(message: "Your Meural session expired.", isUnauthorized: true)
    }
    let message = (try? JSONDecoder().decode(ServerErrorPayload.self, from: data))?.error
    throw MeuralClientError(message: message ?? "Meural returned an error (HTTP \(http.statusCode)).")
  }
}

struct MeuralClientError: LocalizedError {
  var message: String
  var isUnauthorized = false

  var errorDescription: String? { message }
}

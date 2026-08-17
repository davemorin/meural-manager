import Foundation

/// Thin client for the Meural Manager server's REST API.
struct MeuralClient {
  var baseURL: URL

  // MARK: - Photos

  func fetchPhotos(page: Int, count: Int = 100) async throws -> (photos: [MeuralPhoto], isLast: Bool) {
    let query = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "count", value: String(count))
    ]
    let data = try await data(for: "GET", path: "api/items", query: query)
    let envelope = try JSONDecoder().decode(APIEnvelope<[MeuralPhoto]>.self, from: data)
    let photos = envelope.data ?? []
    return (photos, envelope.isLast ?? (photos.count < count))
  }

  func bulkDeletePhotos(ids: [Int]) async throws {
    _ = try await data(for: "POST", path: "api/items/bulk-delete", body: ["ids": ids])
  }

  // MARK: - Playlists

  func fetchPlaylists() async throws -> [MeuralPlaylist] {
    try await decodeEnvelope([MeuralPlaylist].self, from: data(for: "GET", path: "api/galleries"))
  }

  func fetchPlaylistItems(id: Int) async throws -> [MeuralPhoto] {
    let query = [URLQueryItem(name: "all", value: "true")]
    return try await decodeEnvelope([MeuralPhoto].self, from: data(for: "GET", path: "api/galleries/\(id)/items", query: query))
  }

  func createPlaylist(name: String) async throws {
    _ = try await data(for: "POST", path: "api/galleries", body: ["name": name])
  }

  func deletePlaylist(id: Int) async throws {
    _ = try await data(for: "DELETE", path: "api/galleries/\(id)")
  }

  func addPhoto(_ photoID: Int, toPlaylist playlistID: Int) async throws {
    _ = try await data(for: "POST", path: "api/galleries/\(playlistID)/items/\(photoID)")
  }

  func removePhoto(_ photoID: Int, fromPlaylist playlistID: Int) async throws {
    _ = try await data(for: "DELETE", path: "api/galleries/\(playlistID)/items/\(photoID)")
  }

  // MARK: - Frames

  func fetchFrames() async throws -> [MeuralFrame] {
    try await decodeEnvelope([MeuralFrame].self, from: data(for: "GET", path: "api/devices"))
  }

  func assignPlaylist(_ playlistID: Int, toFrame frameID: Int) async throws {
    _ = try await data(for: "POST", path: "api/devices/\(frameID)/galleries/\(playlistID)")
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
    throw MeuralClientError(message: envelope.error ?? "Unexpected response from server.")
  }

  private func data(
    for method: String,
    path: String,
    query: [URLQueryItem] = [],
    body: [String: any Sendable]? = nil
  ) async throws -> Data {
    guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
      throw MeuralClientError(message: "Invalid server address.")
    }
    if !query.isEmpty {
      components.queryItems = query
    }
    guard let url = components.url else {
      throw MeuralClientError(message: "Invalid server address.")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      let message = (try? JSONDecoder().decode(ServerErrorPayload.self, from: data))?.error
      throw MeuralClientError(message: message ?? "The server returned an error (HTTP \(http.statusCode)).")
    }
    return data
  }
}

struct MeuralClientError: LocalizedError {
  var message: String

  var errorDescription: String? { message }
}

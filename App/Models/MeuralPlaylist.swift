import Foundation

struct MeuralPlaylist: Identifiable, Decodable, Hashable {
  var id: Int
  var name: String?
  var itemCount: Int?

  var displayName: String {
    if let name, !name.isEmpty { return name }
    return "Playlist"
  }
}

import Foundation

struct MeuralPlaylist: Identifiable, Decodable, Hashable {
  var id: Int
  var name: String?
  var itemCount: Int?

  var displayName: String {
    if let name, !name.isEmpty { return name }
    return "Playlist"
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, itemCount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let id = container.lenientInt(.id) else {
      throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Playlist is missing an ID")
    }
    self.id = id
    name = container.lenientString(.name)
    itemCount = container.lenientInt(.itemCount)
  }
}

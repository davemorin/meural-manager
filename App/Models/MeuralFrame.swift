import Foundation

struct MeuralFrame: Identifiable, Decodable, Hashable {
  var id: Int
  var alias: String?
  var name: String?
  var status: String?
  var currentPlaylistID: Int?

  var displayName: String {
    if let alias, !alias.isEmpty { return alias }
    if let name, !name.isEmpty { return name }
    return "Frame"
  }

  var isOnline: Bool {
    status?.lowercased() == "online"
  }

  private enum CodingKeys: String, CodingKey {
    case id, alias, name, status, frameStatus
  }

  private struct FrameStatus: Decodable {
    var currentGallery: Int?
    var currentlyPlaying: Playing?

    struct Playing: Decodable {
      var id: Int?
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    alias = (try? container.decodeIfPresent(String.self, forKey: .alias)) ?? nil
    name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
    status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
    let frameStatus = (try? container.decodeIfPresent(FrameStatus.self, forKey: .frameStatus)) ?? nil
    currentPlaylistID = frameStatus?.currentGallery ?? frameStatus?.currentlyPlaying?.id
  }
}

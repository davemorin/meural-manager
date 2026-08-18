import Foundation

struct MeuralPhoto: Identifiable, Decodable, Hashable {
  var id: Int
  var name: String?
  var description: String?
  var image: String?
  var originalImage: String?
  var thumbnail: String?
  var author: String?
  var orientation: String?

  var thumbnailURL: URL? {
    URL(string: thumbnail ?? image ?? "")
  }

  var imageURL: URL? {
    URL(string: image ?? thumbnail ?? "")
  }

  /// The original uploaded file, used to measure true storage size.
  var sizeProbeURL: URL? {
    URL(string: originalImage ?? image ?? thumbnail ?? "")
  }

  var displayName: String {
    if let name, !name.isEmpty { return name }
    return "Photo"
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, image, originalImage, thumbnail, author, orientation
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let id = container.lenientInt(.id) else {
      throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Photo is missing an ID")
    }
    self.id = id
    name = container.lenientString(.name)
    description = container.lenientString(.description)
    image = container.lenientString(.image)
    originalImage = container.lenientString(.originalImage)
    thumbnail = container.lenientString(.thumbnail)
    author = container.lenientString(.author)
    orientation = container.lenientString(.orientation)
  }
}

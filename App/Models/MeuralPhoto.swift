import Foundation

struct MeuralPhoto: Identifiable, Decodable, Hashable {
  var id: Int
  var name: String?
  var description: String?
  var image: String?
  var thumbnail: String?
  var author: String?
  var orientation: String?

  var thumbnailURL: URL? {
    URL(string: thumbnail ?? image ?? "")
  }

  var imageURL: URL? {
    URL(string: image ?? thumbnail ?? "")
  }

  var displayName: String {
    if let name, !name.isEmpty { return name }
    return "Photo"
  }
}

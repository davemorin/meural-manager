import Foundation

struct MeuralUser: Decodable, Hashable {
  var id: Int?
  var email: String?
  // Storage values are reported by the API in megabytes.
  var usedStorage: Double?
  var totalStorage: Double?

  var usedFraction: Double? {
    guard let usedStorage, let totalStorage, totalStorage > 0 else { return nil }
    return min(usedStorage / totalStorage, 1)
  }

  var usedGigabytes: Double? {
    usedStorage.map { $0 / 1024 }
  }

  var totalGigabytes: Double? {
    totalStorage.map { $0 / 1024 }
  }
}

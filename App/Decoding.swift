import Foundation

/// Lenient field readers for Meural's loosely specified API: values that
/// arrive as the wrong-but-convertible type decode instead of failing.
extension KeyedDecodingContainer {
  func lenientString(_ key: Key) -> String? {
    if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
    if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
    if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
    return nil
  }

  func lenientInt(_ key: Key) -> Int? {
    if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
    if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
    if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
    return nil
  }

  func lenientDouble(_ key: Key) -> Double? {
    if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
    if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
    if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
    return nil
  }
}

/// Decodes an array element by element, skipping entries that fail to
/// decode instead of failing the whole array.
struct LossyArray<Element: Decodable>: Decodable {
  var elements: [Element] = []

  private struct AnyElement: Decodable {}

  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    while !container.isAtEnd {
      if let element = try? container.decode(Element.self) {
        elements.append(element)
        continue
      }
      // Skip the bad element, consuming it whatever its JSON type;
      // bail out entirely rather than risk never advancing.
      if (try? container.decode(AnyElement.self)) != nil { continue }
      if (try? container.decodeNil()) == true { continue }
      if (try? container.decode(String.self)) != nil { continue }
      if (try? container.decode(Double.self)) != nil { continue }
      if (try? container.decode(Bool.self)) != nil { continue }
      if (try? container.decode([AnyElement].self)) != nil { continue }
      break
    }
  }
}

import Foundation

/// Carries a value the compiler can't prove Sendable across a concurrency
/// boundary that is known to be safe (e.g. PhotoKit objects into a
/// performChanges block).
struct UncheckedSendable<T>: @unchecked Sendable {
  let value: T

  init(_ value: T) {
    self.value = value
  }
}

extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}

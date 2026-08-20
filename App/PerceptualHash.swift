import CoreGraphics
import Foundation
import ImageIO

/// 64-bit difference hash: the image is reduced to a 9×8 grayscale grid and
/// each bit records whether a pixel is brighter than its right neighbor.
/// Robust to resizing, re-encoding, and stripped metadata.
enum PerceptualHash {
  static func dHash(from image: CGImage) -> UInt64? {
    let width = 9
    let height = 8
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    guard let data = context.data else { return nil }

    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
    var hash: UInt64 = 0
    var bit: UInt64 = 0
    for y in 0..<height {
      for x in 0..<(width - 1) {
        if pixels[y * width + x] < pixels[y * width + x + 1] {
          hash |= 1 << bit
        }
        bit += 1
      }
    }
    return hash
  }

  static func dHash(fromImageData data: Data) -> UInt64? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 64
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return dHash(from: thumbnail)
  }

  static func distance(_ a: UInt64, _ b: UInt64) -> Int {
    (a ^ b).nonzeroBitCount
  }
}

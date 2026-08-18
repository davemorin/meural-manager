import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PhotoUpload {
  var data: Data
  var filename: String
  var mimeType: String
}

/// Converts picked photo data into something Meural accepts: JPEG/PNG
/// under the 20MB API limit, re-encoding HEIC and oversized images.
enum UploadPreparer {
  private static let maxUploadBytes = 20 * 1024 * 1024
  private static let maxPixelSize = 3000

  static func prepare(_ data: Data) async -> PhotoUpload? {
    let base = "artwall-\(UUID().uuidString.prefix(8).lowercased())"
    if data.count <= maxUploadBytes {
      if isJPEG(data) {
        return PhotoUpload(data: data, filename: "\(base).jpg", mimeType: "image/jpeg")
      }
      if isPNG(data) {
        return PhotoUpload(data: data, filename: "\(base).png", mimeType: "image/png")
      }
    }
    guard let jpeg = reencodedJPEG(from: data) else { return nil }
    return PhotoUpload(data: jpeg, filename: "\(base).jpg", mimeType: "image/jpeg")
  }

  private static func isJPEG(_ data: Data) -> Bool {
    data.starts(with: [0xFF, 0xD8, 0xFF])
  }

  private static func isPNG(_ data: Data) -> Bool {
    data.starts(with: [0x89, 0x50, 0x4E, 0x47])
  }

  private static func reencodedJPEG(from data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
      return nil
    }
    let encodeOptions = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
    CGImageDestinationAddImage(destination, image, encodeOptions)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}

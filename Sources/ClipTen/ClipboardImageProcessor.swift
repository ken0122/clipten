import CryptoKit
import Foundation
import ImageIO

struct PreparedClipboardImage: Sendable {
    let metadata: ClipboardImage
    let original: Data
    let thumbnail: Data
}

enum ClipboardImageProcessor {
    static let maximumBytes = 20_000_000
    static let maximumPixels = 40_000_000
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // Called on the serial history queue. No full-resolution NSImage is cached.
    static func prepare(_ data: Data, format: ClipboardImageFormat) throws -> PreparedClipboardImage {
        guard data.count <= maximumBytes else { throw HistoryIssue.imageTooLarge }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary),
              CGImageSourceGetType(source) as String? == format.pasteboardType,
              CGImageSourceGetStatus(source) == .statusComplete else {
            throw HistoryIssue.invalidImage
        }
        guard CGImageSourceGetCount(source) == 1 else { throw HistoryIssue.unsupportedImage }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw HistoryIssue.invalidImage }
        guard width <= maximumPixels / height else { throw HistoryIssue.imageTooLarge }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 48,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary) else { throw HistoryIssue.invalidImage }
        let preview = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(preview, "public.png" as CFString, 1, nil) else {
            throw HistoryIssue.invalidImage
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw HistoryIssue.invalidImage }
        return PreparedClipboardImage(
            metadata: ClipboardImage(format: format, digest: digest(data), width: width,
                                     height: height, byteCount: data.count),
            original: data, thumbnail: preview as Data
        )
    }
}

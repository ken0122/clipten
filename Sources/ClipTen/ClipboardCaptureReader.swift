import AppKit

@MainActor
enum ClipboardCaptureReader {
    static func read(_ pasteboard: NSPasteboard) -> ClipboardCapture? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        // File-copy items may carry a thumbnail too; this version deliberately
        // excludes file URLs rather than treating a Finder preview as the image.
        guard !items.contains(where: { $0.types.contains(.fileURL) }) else { return nil }
        let formats: [ClipboardImageFormat] = [.png, .tiff]
        let hasImage = items.contains { item in
            formats.contains { item.types.contains(.init($0.pasteboardType)) }
                || item.types.contains(.init("com.compuserve.gif"))
        }
        if hasImage {
            guard items.count == 1 else { return .rejected(.multipleItems) }
            let item = items[0]
            var candidates: [ClipboardImageCandidate] = []
            var issue: HistoryIssue?
            for format in formats where item.types.contains(.init(format.pasteboardType)) {
                guard let data = item.data(forType: .init(format.pasteboardType)) else {
                    issue = issue ?? .invalidImage
                    continue
                }
                guard data.count <= ClipboardImageProcessor.maximumBytes else {
                    issue = .imageTooLarge
                    continue
                }
                candidates.append(.init(format: format, data: data))
            }
            guard !candidates.isEmpty else { return .rejected(issue ?? .unsupportedImage) }
            return .images(candidates, rejectedIssue: issue)
        }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .text(text)
    }
}

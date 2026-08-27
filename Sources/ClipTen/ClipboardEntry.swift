import Foundation

enum ClipboardImageFormat: String, Codable, Sendable {
    case png, tiff
    var pasteboardType: String { self == .png ? "public.png" : "public.tiff" }
}

struct ClipboardImage: Codable, Equatable, Sendable {
    let format: ClipboardImageFormat
    let digest: String
    let width: Int
    let height: Int
    let byteCount: Int
    var filename: String { "\(digest).\(format.rawValue)" }
    var isValid: Bool {
        digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
            && byteCount > 0 && byteCount <= ClipboardImageProcessor.maximumBytes
            && width > 0 && height > 0 && width <= ClipboardImageProcessor.maximumPixels / height
    }
}

struct ClipboardEntry: Codable, Equatable, Identifiable, Sendable {
    enum Content: Codable, Equatable, Sendable {
        case text(String)
        case image(ClipboardImage)
    }
    let id: UUID
    let content: Content
    init(id: UUID = UUID(), content: Content) {
        self.id = id
        self.content = content
    }
    var text: String? {
        guard case .text(let text) = content else { return nil }
        return text
    }
    var image: ClipboardImage? {
        guard case .image(let image) = content else { return nil }
        return image
    }
}

enum HistoryIssue: Error, Equatable, LocalizedError, Sendable {
    case imageTooLarge, invalidImage, unsupportedImage, multipleItems
    case storageRead, storageWrite, readOnly, imageUnavailable, cleanupFailed
    case clipboardChanged, clipboardWrite
    var errorDescription: String? {
        switch self {
        case .imageTooLarge: "图片超过 20 MB 或 4000 万像素，未记录"
        case .invalidImage: "图片数据损坏，未记录"
        case .unsupportedImage: "暂不支持动图或多页图片，未记录"
        case .multipleItems: "暂不支持一次复制多张图片，未记录"
        case .storageRead: "历史存储不可读，已停止写入；原文件未改动"
        case .storageWrite: "历史保存失败，原有记录已保留"
        case .readOnly: "历史处于只读保护状态，请检查存储后重启"
        case .imageUnavailable: "图片文件不可用，未修改剪贴板"
        case .cleanupFailed: "记录已保存，但旧图片文件清理失败"
        case .clipboardChanged: "剪贴板已有新内容，已取消这次复制"
        case .clipboardWrite: "写入剪贴板失败，请重试"
        }
    }
}

struct ClipboardImageCandidate: Sendable {
    let format: ClipboardImageFormat
    let data: Data
}

enum ClipboardCapture: Sendable {
    case text(String)
    case images([ClipboardImageCandidate], rejectedIssue: HistoryIssue?)
    case rejected(HistoryIssue)
}

enum ClipboardPayload: Sendable {
    case text(String)
    case image(Data, ClipboardImageFormat)
}

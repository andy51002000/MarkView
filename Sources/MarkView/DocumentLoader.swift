import Foundation

struct LoadedDocument: Sendable {
    let text: String
    let blocks: [MarkdownBlock]
    let inlineCache: InlineRenderCache
}

enum DocumentLoader {
    static let maximumFileSize = 10 * 1_024 * 1_024

    static func load(url: URL) throws -> LoadedDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > maximumFileSize {
            throw DocumentLoadError.fileTooLarge(fileSize)
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumFileSize else {
            throw DocumentLoadError.fileTooLarge(data.count)
        }
        guard let text = decode(data) else {
            throw DocumentLoadError.unsupportedEncoding
        }
        // Both passes run on the loading task's background context and honor
        // cooperative cancellation so superseded reloads stop early.
        let blocks = try MarkdownParser.parse(text, checkingCancellation: true)
        let cache = try InlineRenderCache.build(for: blocks, checkingCancellation: true)
        return LoadedDocument(text: text, blocks: blocks, inlineCache: cache)
    }

    private static func decode(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1252,
            .macOSRoman,
            .isoLatin1
        ]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }
}

enum DocumentLoadError: LocalizedError {
    case fileTooLarge(Int)
    case unsupportedEncoding

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let bytes):
            return "File is \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)); the limit is 10 MB."
        case .unsupportedEncoding:
            return "The file uses an unsupported text encoding."
        }
    }
}

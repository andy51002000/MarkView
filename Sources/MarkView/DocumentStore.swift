import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    static let shared = DocumentStore()

    @Published var rawText: String = ""
    @Published var fileName: String = ""
    @Published var errorMessage: String?
    @Published var baseURL: URL?
    @Published var fileURL: URL?
    @Published var blocks: [MarkdownBlock] = []
    @Published var allowsRemoteImages = false

    private static let allowedExtensions: Set<String> = ["md", "markdown", "mdown", "txt"]
    nonisolated private static let maximumFileSize = 10 * 1_024 * 1_024
    private var activeLoadID = UUID()

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let md = UTType(filenameExtension: "md"),
           let markdown = UTType(filenameExtension: "markdown") {
            panel.allowedContentTypes = [md, markdown, .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func load(url: URL) {
        let loadID = UUID()
        activeLoadID = loadID
        clearDocument()

        let ext = url.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            errorMessage = "Unsupported file type: .\(ext). Choose a .md or .markdown file."
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.readAndParse(url: url)
            await self?.finishLoading(result, url: url, loadID: loadID)
        }
    }

    func allowRemoteImages() {
        guard fileURL != nil else { return }
        allowsRemoteImages = true
    }

    private func finishLoading(
        _ result: Result<(String, [MarkdownBlock]), Error>,
        url: URL,
        loadID: UUID
    ) {
        guard activeLoadID == loadID else { return }
        switch result {
        case .success(let (text, parsedBlocks)):
            rawText = text
            fileName = url.lastPathComponent
            baseURL = url.deletingLastPathComponent().standardizedFileURL
            fileURL = url
            blocks = parsedBlocks
            errorMessage = nil
        case .failure(let error):
            clearDocument()
            errorMessage = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func clearDocument() {
        rawText = ""
        fileName = ""
        baseURL = nil
        fileURL = nil
        blocks = []
        allowsRemoteImages = false
        errorMessage = nil
    }

    nonisolated private static func readAndParse(
        url: URL
    ) -> Result<(String, [MarkdownBlock]), Error> {
        Result {
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
            return (text, MarkdownParser.parse(text))
        }
    }

    nonisolated private static func decode(_ data: Data) -> String? {
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

    private enum DocumentLoadError: LocalizedError {
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

    func copyPath() {
        guard let path = fileURL?.path else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func copyMarkdown() {
        guard !rawText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawText, forType: .string)
    }
}

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
    @Published var inlineCache: InlineRenderCache = .empty

    private static let allowedExtensions: Set<String> = ["md", "markdown", "mdown", "txt"]
    private var activeLoadID = UUID()
    private var fileWatcher: FileWatcher?
    private var inFlightLoad: Task<Void, Never>?

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
        stopWatching()
        clearDocument()

        let ext = url.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            errorMessage = "Unsupported file type: .\(ext). Choose a .md or .markdown file."
            return
        }
        loadDocument(at: url.standardizedFileURL, startWatchingOnSuccess: true)
    }

    func reload() {
        guard let fileURL else { return }
        loadDocument(at: fileURL, startWatchingOnSuccess: false)
    }

    private func loadDocument(at url: URL, startWatchingOnSuccess: Bool) {
        let loadID = UUID()
        activeLoadID = loadID
        // Cancel any parse still running for a previous (now superseded)
        // load so rapid saves don't stack background work.
        inFlightLoad?.cancel()
        inFlightLoad = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try DocumentLoader.load(url: url) }
            if case .failure(let error) = result, error is CancellationError {
                return // superseded load; a newer one owns the UI state
            }
            await self?.finishLoading(
                result,
                url: url,
                loadID: loadID,
                startWatchingOnSuccess: startWatchingOnSuccess
            )
        }
    }

    private func finishLoading(
        _ result: Result<LoadedDocument, Error>,
        url: URL,
        loadID: UUID,
        startWatchingOnSuccess: Bool
    ) {
        guard activeLoadID == loadID else { return }
        switch result {
        case .success(let document):
            rawText = document.text
            fileName = url.lastPathComponent
            baseURL = url.deletingLastPathComponent().standardizedFileURL
            fileURL = url
            inlineCache = document.inlineCache
            blocks = document.blocks
            errorMessage = nil
            if startWatchingOnSuccess || fileWatcher == nil {
                startWatching(url: url)
            }
        case .failure(let error):
            stopWatching()
            clearDocument()
            errorMessage = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func startWatching(url: URL) {
        stopWatching()
        let watcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in
                guard self?.fileURL == url else { return }
                self?.reload()
            }
        }
        fileWatcher = watcher
        watcher.start()
    }

    private func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    private func clearDocument() {
        rawText = ""
        fileName = ""
        baseURL = nil
        fileURL = nil
        blocks = []
        errorMessage = nil
    }

    // Returns true when something was actually copied, so the UI can show
    // confirmation feedback only for real copies.
    @discardableResult
    func copyPath() -> Bool {
        guard let path = fileURL?.path else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        return true
    }

    @discardableResult
    func copyMarkdown() -> Bool {
        guard !rawText.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawText, forType: .string)
        return true
    }
}

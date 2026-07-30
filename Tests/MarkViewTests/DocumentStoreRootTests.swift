import Foundation
import Testing
@testable import MarkView

@Suite(.serialized) @MainActor struct DocumentStoreRootTests {
    private let fileManager = FileManager.default

    @Test func reloadKeepsCachedRootAndSwitchingDocumentRecomputes() async throws {
        let container = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: container) }
        let firstRoot = container.appendingPathComponent("first", isDirectory: true)
        let firstBlog = firstRoot.appendingPathComponent("blog", isDirectory: true)
        let secondRoot = container.appendingPathComponent("second", isDirectory: true)
        let secondBlog = secondRoot.appendingPathComponent("blog", isDirectory: true)
        try createDirectory(firstBlog)
        try createDirectory(secondBlog)
        let marker = firstRoot.appendingPathComponent("README.md")
        try "first".write(to: marker, atomically: true, encoding: .utf8)
        try "second".write(to: secondRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let firstDocument = firstBlog.appendingPathComponent("post.md")
        let secondDocument = secondBlog.appendingPathComponent("post.md")
        try "# first".write(to: firstDocument, atomically: true, encoding: .utf8)
        try "# second".write(to: secondDocument, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.load(url: firstDocument)
        try await waitUntil { store.rawText == "# first" }
        let cached = try #require(store.projectRootResolution)
        #expect(cached.rootURL == ProjectRootResolver.canonical(firstRoot))
        #expect(cached.marker == "README.md")

        try fileManager.removeItem(at: marker)
        try "# first reloaded".write(to: firstDocument, atomically: true, encoding: .utf8)
        store.reload()
        try await waitUntil { store.rawText == "# first reloaded" }
        #expect(store.projectRootResolution == cached,
                "Reload must reuse the root computed when the document was opened")

        store.load(url: secondDocument)
        try await waitUntil { store.rawText == "# second" }
        #expect(store.securityRootURL == ProjectRootResolver.canonical(secondRoot))
        #expect(store.projectRootResolution?.marker == "Package.swift")
    }

    @Test func failedReloadClearsCachedRoot() async throws {
        let root = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let blog = root.appendingPathComponent("blog", isDirectory: true)
        try createDirectory(blog)
        try "project".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let document = blog.appendingPathComponent("post.md")
        try "# available".write(to: document, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.load(url: document)
        try await waitUntil { store.rawText == "# available" }
        #expect(store.securityRootURL != nil)

        try fileManager.removeItem(at: document)
        store.reload()
        try await waitUntil { store.errorMessage != nil }
        #expect(store.rawText.isEmpty)
        #expect(store.fileURL == nil)
        #expect(store.baseURL == nil)
        #expect(store.securityRootURL == nil)
        #expect(store.projectRootResolution == nil)
        #expect(store.blocks.isEmpty)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for DocumentStore state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("markview-store-root-tests-\(UUID().uuidString)", isDirectory: true)
        try createDirectory(url)
        return url
    }

    private func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

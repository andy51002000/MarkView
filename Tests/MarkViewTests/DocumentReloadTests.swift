import Foundation
import Testing
@testable import MarkView

@Suite(.serialized) struct DocumentReloadTests {

    @Test func loaderReadsUpdatedContentOnReload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.md")

        try "# Initial".write(to: documentURL, atomically: false, encoding: .utf8)
        #expect(try DocumentLoader.load(url: documentURL).text == "# Initial")

        try "# Updated".write(to: documentURL, atomically: false, encoding: .utf8)
        let reloaded = try DocumentLoader.load(url: documentURL)
        #expect(reloaded.text == "# Updated")
        #expect(reloaded.blocks.count == 1)
    }

    @Test func loaderReadsContentAfterAtomicReplacement() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.md")
        let replacementURL = directory.appendingPathComponent("replacement.md")

        try "old inode".write(to: documentURL, atomically: false, encoding: .utf8)
        try "new inode".write(to: replacementURL, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(documentURL, withItemAt: replacementURL)

        #expect(try DocumentLoader.load(url: documentURL).text == "new inode")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markview-reload-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import AppKit
import Foundation
import Testing
@testable import MarkView

@Suite(.serialized) struct ProjectRootResolverTests {
    private let fileManager = FileManager.default

    @Test func nearestTrustedMarkerWins() throws {
        let root = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let outer = root.appendingPathComponent("outer", isDirectory: true)
        let inner = outer.appendingPathComponent("inner", isDirectory: true)
        let blog = inner.appendingPathComponent("blog", isDirectory: true)
        try createDirectory(blog)
        try "outer".write(to: outer.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "inner".write(to: inner.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let document = blog.appendingPathComponent("post.md")
        try "# post".write(to: document, atomically: true, encoding: .utf8)

        let resolution = ProjectRootResolver.resolve(documentURL: document, homeURL: root)

        #expect(resolution.rootURL == ProjectRootResolver.canonical(inner))
        #expect(resolution.marker == "Package.swift")
        #expect(resolution.scannedDirectoryCount == 2)
    }

    @Test func gitFileOrDirectoryIsTrusted() throws {
        for gitIsDirectory in [false, true] {
            let root = try temporaryDirectory()
            defer { try? fileManager.removeItem(at: root) }
            let blog = root.appendingPathComponent("blog", isDirectory: true)
            try createDirectory(blog)
            let marker = root.appendingPathComponent(".git", isDirectory: gitIsDirectory)
            if gitIsDirectory {
                try createDirectory(marker)
            } else {
                try "gitdir: elsewhere".write(to: marker, atomically: true, encoding: .utf8)
            }
            let document = blog.appendingPathComponent("post.md")
            try "# post".write(to: document, atomically: true, encoding: .utf8)
            #expect(ProjectRootResolver.resolve(documentURL: document, homeURL: root).rootURL == root)
        }
    }

    @Test func noMarkerFallsBackToDocumentDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let blog = root.appendingPathComponent("blog", isDirectory: true)
        try createDirectory(blog)
        let document = blog.appendingPathComponent("post.md")
        try "# post".write(to: document, atomically: true, encoding: .utf8)
        try "instructions".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let resolution = ProjectRootResolver.resolve(documentURL: document, homeURL: root)

        #expect(resolution.rootURL == ProjectRootResolver.canonical(blog))
        #expect(resolution.marker == nil)
        #expect(isRejected(ImageSourceResolver.resolve(
            "../outside.jpg",
            documentBaseURL: blog,
            securityRootURL: resolution.rootURL
        )))
    }

    @Test func markerSearchNeverCrossesHomeBoundary() throws {
        let container = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: container) }
        let home = container.appendingPathComponent("home", isDirectory: true)
        let blog = home.appendingPathComponent("project/blog", isDirectory: true)
        try createDirectory(blog)
        try "outside-home".write(
            to: container.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let document = blog.appendingPathComponent("post.md")
        try "# post".write(to: document, atomically: true, encoding: .utf8)

        let resolution = ProjectRootResolver.resolve(documentURL: document, homeURL: home)

        #expect(resolution.rootURL == ProjectRootResolver.canonical(blog))
        #expect(resolution.marker == nil)
        #expect(resolution.scannedDirectoryCount == 3)
    }

    @Test func sameDirectoryAndSiblingAssetInsideProjectAreAccepted() throws {
        let project = try makeProject()
        defer { try? fileManager.removeItem(at: project.root) }
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: project.blog.appendingPathComponent("same.jpg"))
        let sibling = project.root.appendingPathComponent("assets/page.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: sibling)

        let same = ImageSourceResolver.resolve(
            "same.jpg",
            documentBaseURL: project.blog,
            securityRootURL: project.root
        )
        let parent = ImageSourceResolver.resolve(
            "../assets/page.jpg",
            documentBaseURL: project.blog,
            securityRootURL: project.root
        )

        #expect(localURL(same) == ProjectRootResolver.canonical(project.blog.appendingPathComponent("same.jpg")))
        #expect(localURL(parent) == ProjectRootResolver.canonical(sibling))
    }

    @Test func crossRootPrefixCollisionAndEncodedTraversalAreRejected() throws {
        let root = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        let privateProject = root.appendingPathComponent("project-private", isDirectory: true)
        let blog = project.appendingPathComponent("blog", isDirectory: true)
        try createDirectory(blog)
        try createDirectory(privateProject)

        let prefixCollision = ImageSourceResolver.resolve(
            "../../project-private/secret.jpg",
            documentBaseURL: blog,
            securityRootURL: project
        )
        #expect(isRejected(prefixCollision))
        if case .rejected(let message) = prefixCollision {
            #expect(message.contains("project root directory"))
        }
        #expect(isRejected(ImageSourceResolver.resolve(
            "%2e%2e/%2e%2e/project-private/secret.jpg",
            documentBaseURL: blog,
            securityRootURL: project
        )))
        #expect(!ProjectRootResolver.contains(privateProject, in: project))
    }

    @Test func absoluteFileAndHTTPRemainRejectedWhileHTTPSIsAllowed() throws {
        let base = fileManager.temporaryDirectory
        for source in ["/etc/hosts", "%2Fetc/hosts", "file:///etc/hosts", "http://example.com/a.png"] {
            #expect(isRejected(ImageSourceResolver.resolve(
                source,
                documentBaseURL: base,
                securityRootURL: base
            )), "Expected rejection for \(source)")
        }
        guard case .remote(let url) = ImageSourceResolver.resolve(
            "https://example.com/a.png",
            documentBaseURL: base,
            securityRootURL: base
        ) else {
            Issue.record("HTTPS source should remain allowed")
            return
        }
        #expect(url.scheme == "https")
    }

    @Test func spacesCJKPercentEncodingQueryAndFragmentResolveLocally() throws {
        let project = try makeProject()
        defer { try? fileManager.removeItem(at: project.root) }
        let expected = project.root.appendingPathComponent("assets/my 圖片.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: expected)

        let result = ImageSourceResolver.resolve(
            "../assets/my%20%E5%9C%96%E7%89%87.jpg?cache=1#preview",
            documentBaseURL: project.blog,
            securityRootURL: project.root
        )

        #expect(localURL(result) == ProjectRootResolver.canonical(expected))
    }

    @Test func symlinkEscapeIsRejected() throws {
        let root = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        let blog = project.appendingPathComponent("blog", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try createDirectory(blog)
        try createDirectory(outside)
        try fileManager.createSymbolicLink(
            at: project.appendingPathComponent("linked-assets"),
            withDestinationURL: outside
        )

        let result = ImageSourceResolver.resolve(
            "../linked-assets/secret.jpg",
            documentBaseURL: blog,
            securityRootURL: project
        )
        #expect(isRejected(result))
    }

    private func temporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("markview-root-tests-\(UUID().uuidString)", isDirectory: true)
        try createDirectory(url)
        return url
    }

    private func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeProject() throws -> (root: URL, blog: URL) {
        let root = try temporaryDirectory()
        let blog = root.appendingPathComponent("blog", isDirectory: true)
        try createDirectory(blog)
        try createDirectory(root.appendingPathComponent("assets", isDirectory: true))
        try "project".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return (root, blog)
    }

    private func isRejected(_ result: ImageSourceResolution) -> Bool {
        if case .rejected = result { return true }
        return false
    }

    private func localURL(_ result: ImageSourceResolution) -> URL? {
        if case .local(let url) = result { return url }
        return nil
    }

}

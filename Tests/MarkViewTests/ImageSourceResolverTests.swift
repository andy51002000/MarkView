import Foundation
import Testing
@testable import MarkView

@Suite struct ImageSourceResolverTests {

    private var baseURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("markview-tests-docdir", isDirectory: true)
    }

    @Test func fileSchemeIsRejected() throws {
        let result = ImageSourceResolver.resolve(
            "file:///etc/hosts", relativeTo: baseURL, allowsRemoteImages: true)
        guard case .rejected = result else {
            Issue.record("file:// sources must be rejected, got \(result)")
            return
        }
    }

    @Test func httpIsRejectedEvenWhenRemoteAllowed() throws {
        let result = ImageSourceResolver.resolve(
            "http://example.com/a.png", relativeTo: baseURL, allowsRemoteImages: true)
        guard case .rejected = result else {
            Issue.record("Plain HTTP must never be loaded, got \(result)")
            return
        }
    }

    @Test func httpsBlockedByDefault() throws {
        let result = ImageSourceResolver.resolve(
            "https://example.com/a.png", relativeTo: baseURL, allowsRemoteImages: false)
        guard case .rejected = result else {
            Issue.record("Remote images must be blocked by default, got \(result)")
            return
        }
    }

    @Test func httpsAllowedWhenOptedIn() throws {
        let result = ImageSourceResolver.resolve(
            "https://example.com/a.png", relativeTo: baseURL, allowsRemoteImages: true)
        guard case .remote(let url) = result else {
            Issue.record("Expected an approved remote URL, got \(result)")
            return
        }
        #expect(url.scheme == "https")
        #expect(url.host == "example.com")
    }

    @Test func absolutePathIsRejected() throws {
        let result = ImageSourceResolver.resolve(
            "/etc/hosts", relativeTo: baseURL, allowsRemoteImages: false)
        guard case .rejected = result else {
            Issue.record("Absolute paths must be rejected, got \(result)")
            return
        }
    }

    @Test func parentTraversalIsRejected() throws {
        let result = ImageSourceResolver.resolve(
            "../outside/secret.png", relativeTo: baseURL, allowsRemoteImages: false)
        guard case .rejected = result else {
            Issue.record("../ traversal outside the document directory must be rejected, got \(result)")
            return
        }
    }

    @Test func nestedTraversalEscapingBaseIsRejected() throws {
        let result = ImageSourceResolver.resolve(
            "assets/../../secret.png", relativeTo: baseURL, allowsRemoteImages: false)
        guard case .rejected = result else {
            Issue.record("Traversal that resolves outside the base must be rejected, got \(result)")
            return
        }
    }

    @Test func relativePathInsideBaseIsAccepted() throws {
        let result = ImageSourceResolver.resolve(
            "assets/logo.png", relativeTo: baseURL, allowsRemoteImages: false)
        guard case .local(let url) = result else {
            Issue.record("Expected a resolved local URL, got \(result)")
            return
        }
        #expect(url.path.hasSuffix("assets/logo.png"))
    }

    @Test func traversalThatStaysInsideBaseIsAccepted() throws {
        let result = ImageSourceResolver.resolve(
            "assets/../logo.png", relativeTo: baseURL, allowsRemoteImages: false)
        guard case .local(let url) = result else {
            Issue.record("In-base traversal should resolve to a local URL, got \(result)")
            return
        }
        #expect(url.path.hasSuffix("logo.png"))
        #expect(!url.path.contains(".."))
    }
}

import AppKit
import Testing
@testable import MarkView

@Suite struct QuickLookRenderingTests {

    private func render(_ markdown: String, baseURL: URL? = nil) -> NSAttributedString {
        QuickLookRenderer.attributedString(
            for: MarkdownParser.parse(markdown),
            baseURL: baseURL
        )
    }

    @Test func rendersHeadingWithHeadingFont() throws {
        let output = render("# Big Title")
        let text = output.string
        #expect(text.contains("Big Title"))
        let range = (text as NSString).range(of: "Big Title")
        let font = output.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > QuickLookRenderer.Fonts.base.pointSize,
                "Heading must render larger than body text")
    }

    @Test func rendersTableWithTextTableBlocks() throws {
        let output = render("""
        | Name | Value |
        | ---- | ----- |
        | a    | 1     |
        """)
        #expect(output.string.contains("Name"))
        #expect(output.string.contains("a"))

        // Header cell must carry an NSTextTableBlock paragraph style.
        let range = (output.string as NSString).range(of: "Name")
        let style = output.attribute(
            .paragraphStyle, at: range.location, effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(style != nil)
        #expect(style!.textBlocks.isEmpty == false,
                "Table cells must use NSTextTable layout")
    }

    @Test func rendersNestedListWithIndentationAndMarkers() throws {
        let output = render("""
        - parent
            - child
        1. ordered
        - [x] done task
        """)
        let text = output.string
        #expect(text.contains("•  parent"))
        #expect(text.contains("    •  child"), "Nested item must be indented")
        #expect(text.contains("1.  ordered"))
        #expect(text.contains("☑  done task"))
    }

    @Test func rendersCodeBlockInMonospace() throws {
        let output = render("""
        ```swift
        let x = 1
        ```
        """)
        let range = (output.string as NSString).range(of: "let x = 1")
        #expect(range.location != NSNotFound)
        let font = output.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.monoSpace),
                "Code must render in a monospaced font")
    }

    @Test func boldInlineTextGetsBoldTrait() throws {
        let output = render("plain **bolded** tail")
        let range = (output.string as NSString).range(of: "bolded")
        #expect(range.location != NSNotFound)
        let font = output.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test func remoteImageIsNeverEmbeddedOnlyPlaceholder() throws {
        let output = render("![logo](https://example.com/logo.png)")
        #expect(output.string.contains("remote image not loaded"),
                "Remote images must show a placeholder, not fetch content")
        var hasAttachment = false
        output.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: output.length)
        ) { value, _, _ in
            if value != nil { hasAttachment = true }
        }
        #expect(!hasAttachment, "No image attachment may exist for remote sources")
    }

    @Test func escapingLocalImagePathShowsRejection() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("qltest-docdir", isDirectory: true)
        let output = render("![escape](../outside/secret.png)", baseURL: base)
        var hasAttachment = false
        output.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: output.length)
        ) { value, _, _ in
            if value != nil { hasAttachment = true }
        }
        #expect(!hasAttachment, "Path-escaping local images must not be loaded")
        #expect(output.string.contains("escape"))
    }

    @Test func hugeDocumentIsTruncatedWithNotice() throws {
        let blocks = MarkdownParser.parse(
            (1...(QuickLookRenderer.blockLimit + 50))
                .map { "paragraph \($0)" }
                .joined(separator: "\n\n")
        )
        #expect(blocks.count > QuickLookRenderer.blockLimit)
        let output = QuickLookRenderer.attributedString(for: blocks, baseURL: nil)
        #expect(output.string.contains("preview truncated"))
    }

    @Test func linkGetsLinkAttribute() throws {
        let output = render("see [docs](https://example.com/docs)")
        var foundLink = false
        output.enumerateAttribute(
            .link, in: NSRange(location: 0, length: output.length)
        ) { value, _, _ in
            if value != nil { foundLink = true }
        }
        #expect(foundLink, "Markdown links must carry .link attributes")
    }
}

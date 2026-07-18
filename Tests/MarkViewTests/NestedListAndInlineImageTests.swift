import Foundation
import Testing
@testable import MarkView

@Suite struct NestedListAndInlineImageTests {

    @Test func threeLevelMixedListBuildsTree() throws {
        let input = "- root\n  1. first\n  2. second\n    - [ ] pending\n    - [x] done\n- sibling"
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 1)
        guard case .list(_, let roots) = blocks[0] else {
            Issue.record("Expected a nested list block")
            return
        }

        #expect(roots.count == 2)
        #expect(roots[0].marker == .unordered)
        #expect(roots[0].text == "root")
        #expect(roots[0].children.map(\.marker) == [.ordered, .ordered])
        #expect(roots[0].children.map(\.text) == ["first", "second"])
        #expect(roots[0].children[1].children.map(\.marker) == [
            .task(checked: false),
            .task(checked: true)
        ])
        #expect(roots[1].text == "sibling")
    }

    @Test func fourSpacesAndTabsCreateNestedLevels() throws {
        let fourSpaces = MarkdownParser.parse("- root\n    - child")
        guard case .list(_, let spaceRoots) = fourSpaces.first else {
            Issue.record("Four-space indentation should create a nested list")
            return
        }
        #expect(spaceRoots[0].children[0].text == "child")

        let tab = MarkdownParser.parse("- root\n\t1. child")
        guard case .list(_, let tabRoots) = tab.first else {
            Issue.record("Tab indentation should create a nested list")
            return
        }
        #expect(tabRoots[0].children[0].marker == .ordered)
    }

    @Test func flatListsKeepLegacyBlocks() throws {
        let unordered = MarkdownParser.parse("- one\n- two")
        guard case .unorderedList(_, let items) = unordered.first else {
            Issue.record("Flat unordered list should retain its legacy block")
            return
        }
        #expect(items == ["one", "two"])

        let ordered = MarkdownParser.parse("1. one\n2. two")
        guard case .orderedList = ordered.first else {
            Issue.record("Flat ordered list should retain its legacy block")
            return
        }
    }

    @Test func nestedListIDsAreDeterministicAcrossReparses() {
        let input = "- root\n  1. child\n    - [x] done"
        #expect(MarkdownParser.parse(input).map(\.id) == MarkdownParser.parse(input).map(\.id))
    }

    @Test func paragraphInlineImagePreservesSurroundingText() throws {
        let blocks = MarkdownParser.parse("Before ![logo](assets/logo.png) after")
        guard case .paragraph(_, let text) = blocks.first else {
            Issue.record("Expected a paragraph block")
            return
        }
        #expect(parseInlineSegments(text) == [
            .text("Before "),
            .image(alt: "logo", source: "assets/logo.png"),
            .text(" after")
        ])
    }

    @Test func tableCellInlineImageProducesSegments() throws {
        let input = "| Item | Preview |\n| --- | --- |\n| Logo | before ![logo](https://example.com/logo.png) after |"
        let blocks = MarkdownParser.parse(input)
        guard case .table(_, _, let rows) = blocks.first else {
            Issue.record("Expected a table block")
            return
        }
        #expect(parseInlineSegments(rows[0][1]) == [
            .text("before "),
            .image(alt: "logo", source: "https://example.com/logo.png"),
            .text(" after")
        ])
    }

    @Test func inlineCodeImageSyntaxRemainsText() {
        let input = "before `![literal](https://example.com/a.png)` after"
        #expect(parseInlineSegments(input) == [.text(input)])
    }

    @Test func standaloneImageRemainsImageBlock() throws {
        let blocks = MarkdownParser.parse("![logo](assets/logo.png)")
        guard case .image(_, let alt, let source) = blocks.first else {
            Issue.record("Standalone image should retain its image block")
            return
        }
        #expect(alt == "logo")
        #expect(source == "assets/logo.png")
    }

    @Test func inlineTextSegmentsArePrecomputedInCache() throws {
        let blocks = MarkdownParser.parse("Before ![logo](assets/logo.png) after")
        let cache = try InlineRenderCache.build(for: blocks)
        #expect(cache["Before "] != nil)
        #expect(cache[" after"] != nil)
    }

    @Test func unsafeInlineImageSourcesRemainRejected() {
        let base = URL(fileURLWithPath: "/tmp/markview-doc", isDirectory: true)
        let inputs = [
            "http://example.com/a.png",
            "file:///tmp/a.png",
            "/tmp/a.png",
            "../a.png"
        ]
        for source in inputs {
            let segments = parseInlineSegments("before ![unsafe](\(source)) after")
            guard case .image(_, let parsedSource) = segments[1] else {
                Issue.record("Expected an inline image segment for \(source)")
                continue
            }
            guard case .rejected = ImageSourceResolver.resolve(parsedSource, relativeTo: base) else {
                Issue.record("Unsafe inline source should be rejected: \(source)")
                continue
            }
        }
    }
}

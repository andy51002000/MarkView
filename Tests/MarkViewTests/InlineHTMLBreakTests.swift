import Testing
@testable import MarkView

@Suite struct InlineHTMLBreakTests {

    @Test func allSupportedBreakVariantsBecomeNewlines() {
        let input = "a<br>b<br/>c<br />d</br>e<BR>f<Br />g"
        #expect(replacingHTMLLineBreaks(in: input) == "a\nb\nc\nd\ne\nf\ng")
    }

    @Test func tableCellBreakBecomesNewline() throws {
        let input = """
        | Time | Session |
        | --- | --- |
        | 11:00 | KEY001 (to 11:00)<br>Day 1 keynote |
        """
        let blocks = MarkdownParser.parse(input)
        guard case .table(_, _, let rows) = blocks.first else {
            Issue.record("Expected a table block")
            return
        }
        #expect(replacingHTMLLineBreaks(in: rows[0][1]) == "KEY001 (to 11:00)\nDay 1 keynote")
    }

    @Test func paragraphBreakBecomesNewline() throws {
        let blocks = MarkdownParser.parse("first<br/>second")
        guard case .paragraph(_, let text) = blocks.first else {
            Issue.record("Expected a paragraph block")
            return
        }
        #expect(replacingHTMLLineBreaks(in: text) == "first\nsecond")
    }

    @Test func listAndQuoteBreaksBecomeNewlines() throws {
        let blocks = MarkdownParser.parse("- first<br />second\n\n> third</br>fourth")
        guard case .unorderedList(_, let items) = blocks.first else {
            Issue.record("Expected an unordered list block")
            return
        }
        #expect(replacingHTMLLineBreaks(in: items[0]) == "first\nsecond")
        guard case .quote(_, let quote) = blocks.last else {
            Issue.record("Expected a quote block")
            return
        }
        #expect(replacingHTMLLineBreaks(in: quote) == "third\nfourth")
    }

    @Test func inlineCodeBreakRemainsLiteral() {
        let input = "before `<br>` and ``<BR />`` after<br>next"
        #expect(
            replacingHTMLLineBreaks(in: input)
                == "before `<br>` and ``<BR />`` after\nnext"
        )
    }

    @Test func fencedCodeBreakRemainsLiteral() throws {
        let blocks = MarkdownParser.parse("""
        ```html
        first<br>second
        ```
        """)
        guard case .codeBlock(_, _, let code) = blocks.first else {
            Issue.record("Expected a code block")
            return
        }
        #expect(code == "first<br>second")
    }
}

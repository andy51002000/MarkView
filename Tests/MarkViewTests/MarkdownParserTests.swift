import Testing
@testable import MarkView

@Suite struct MarkdownParserTests {

    // MARK: - Tables

    @Test func pipeTableParsing() throws {
        let input = """
        | Name | Value |
        | ---- | ----- |
        | a    | 1     |
        | b    | 2     |
        """
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 1)
        guard case .table(_, let headers, let rows) = blocks[0] else {
            Issue.record("Expected a table block, got \(blocks[0])")
            return
        }
        #expect(headers == ["Name", "Value"])
        #expect(rows == [["a", "1"], ["b", "2"]])
    }

    @Test func tableWithUnevenRowsAndEscapedPipes() throws {
        let input = """
        | Col1 | Col2 | Col3 |
        | --- | --- | --- |
        | only-one |
        | a \\| b | `x|y` | z |
        """
        let blocks = MarkdownParser.parse(input)
        guard case .table(_, let headers, let rows) = blocks.first else {
            Issue.record("Expected a table block")
            return
        }
        #expect(headers.count == 3)
        #expect(rows[0] == ["only-one"])
        #expect(rows[1] == ["a | b", "`x|y`", "z"])
    }

    @Test func textWithoutSeparatorIsNotATable() throws {
        let input = "a | b | c\njust a paragraph"
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 1)
        guard case .paragraph = blocks[0] else {
            Issue.record("Expected a paragraph, got \(blocks[0])")
            return
        }
    }

    // MARK: - Task lists

    @Test func taskListParsing() throws {
        let input = """
        - [ ] open item
        - [x] done item
        - [X] also done
        """
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 1)
        guard case .taskList(_, let items) = blocks[0] else {
            Issue.record("Expected a task list block, got \(blocks[0])")
            return
        }
        #expect(items.count == 3)
        #expect(items[0] == TaskItem(checked: false, text: "open item"))
        #expect(items[1] == TaskItem(checked: true, text: "done item"))
        #expect(items[2].checked)
    }

    @Test func taskListSeparatedFromPlainList() throws {
        let input = """
        - plain item
        - [ ] task item
        """
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 2)
        guard case .unorderedList(_, let items) = blocks[0] else {
            Issue.record("Expected an unordered list first")
            return
        }
        #expect(items == ["plain item"])
        guard case .taskList(_, let tasks) = blocks[1] else {
            Issue.record("Expected a task list second")
            return
        }
        #expect(tasks == [TaskItem(checked: false, text: "task item")])
    }

    // MARK: - Soft breaks

    @Test func softBreakPreservedInsideParagraph() throws {
        let input = "first line\nsecond line\n\nnext paragraph"
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 2)
        guard case .paragraph(_, let text) = blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(text == "first line\nsecond line",
                "Adjacent lines must stay in one paragraph joined by a newline")
    }

    // MARK: - Headings / code fences

    @Test func headingAndCodeBlock() throws {
        let input = """
        # Title

        ```swift
        let x = 1
        ```
        """
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 2)
        guard case .heading(_, let level, let text) = blocks[0] else {
            Issue.record("Expected a heading")
            return
        }
        #expect(level == 1)
        #expect(text == "Title")
        guard case .codeBlock(_, let lang, let code) = blocks[1] else {
            Issue.record("Expected a code block")
            return
        }
        #expect(lang == "swift")
        #expect(code == "let x = 1")
    }

    @Test func strayFenceDoesNotSwallowHeadings() throws {
        let input = """
        ```
        # Real Heading

        | H | I |
        | - | - |
        | 1 | 2 |
        """
        let blocks = MarkdownParser.parse(input)
        let hasHeading = blocks.contains { block in
            if case .heading(_, 1, "Real Heading") = block { return true }
            return false
        }
        #expect(hasHeading, "A stray unbalanced fence must not hide subsequent headings")
        let hasTable = blocks.contains { block in
            if case .table = block { return true }
            return false
        }
        #expect(hasTable, "A stray unbalanced fence must not hide subsequent tables")
    }

    // MARK: - Stable block IDs

    @Test func blockIDsAreUniqueAndStableWithinAParse() throws {
        let input = """
        # A

        para

        # A
        """
        let blocks = MarkdownParser.parse(input)
        #expect(blocks.count == 3)
        let ids = blocks.map(\.id)
        #expect(Set(ids).count == ids.count,
                "Every block needs a distinct ID even when content repeats")
        // Reading .id twice must return the same value (no regeneration).
        #expect(blocks[0].id == blocks[0].id)
    }
}

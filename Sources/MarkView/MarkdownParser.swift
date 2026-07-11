import Foundation

// A single task-list entry.
struct TaskItem: Hashable, Sendable {
    let checked: Bool
    let text: String
}

// A lightweight block-level Markdown model.
enum MarkdownBlock: Identifiable, Sendable {
    case heading(id: UUID = UUID(), level: Int, text: String)
    case paragraph(id: UUID = UUID(), text: String)
    case unorderedList(id: UUID = UUID(), items: [String])
    case orderedList(id: UUID = UUID(), items: [String])
    case taskList(id: UUID = UUID(), items: [TaskItem])
    case codeBlock(id: UUID = UUID(), language: String?, code: String)
    case quote(id: UUID = UUID(), text: String)
    case table(id: UUID = UUID(), headers: [String], rows: [[String]])
    case image(id: UUID = UUID(), alt: String, source: String)
    case thematicBreak(id: UUID = UUID())

    var id: UUID {
        switch self {
        case .heading(let id, _, _),
             .paragraph(let id, _),
             .unorderedList(let id, _),
             .orderedList(let id, _),
             .taskList(let id, _),
             .codeBlock(let id, _, _),
             .quote(let id, _),
             .table(let id, _, _),
             .image(let id, _, _),
             .thematicBreak(let id):
            return id
        }
    }
}

// Minimal, dependency-free Markdown block parser.
struct MarkdownParser {
    static func parse(_ input: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let realFences = computeRealFences(lines)

        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let text = paragraphBuffer.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    blocks.append(.paragraph(text: text))
                }
                paragraphBuffer.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block (only when this fence is a recognized opener;
            // stray/unbalanced fences are treated as plain text so tables and
            // headings after them still render).
            if trimmed.hasPrefix("```"), realFences.contains(i) {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if realFences.contains(i) { break }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang,
                                         code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // Blank line
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Thematic break
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.thematicBreak())
                i += 1
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                i += 1
                continue
            }

            // Standalone image: a line that is only ![alt](src)
            if let image = parseStandaloneImage(trimmed) {
                flushParagraph()
                blocks.append(image)
                i += 1
                continue
            }

            // GitHub-style pipe table: a header row followed by a separator row
            // like | --- | --- |.
            if trimmed.contains("|"),
               i + 1 < lines.count,
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                let headers = splitTableRow(trimmed)
                i += 2 // consume header + separator
                var rows: [[String]] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.contains("|"), !t.isEmpty else { break }
                    rows.append(splitTableRow(t))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quoteLines.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Task list (- [ ] / - [x]) — must be checked before plain lists.
            if parseTaskItem(trimmed) != nil {
                flushParagraph()
                var items: [TaskItem] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let item = parseTaskItem(t) else { break }
                    items.append(item)
                    i += 1
                }
                blocks.append(.taskList(items: items))
                continue
            }

            // Unordered list
            if isUnorderedItem(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isUnorderedItem(t), parseTaskItem(t) == nil else { break }
                    items.append(stripUnorderedMarker(t))
                    i += 1
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if isOrderedItem(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isOrderedItem(t) else { break }
                    items.append(stripOrderedMarker(t))
                    i += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Default: accumulate paragraph
            paragraphBuffer.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // Determines which ``` lines are genuine code-fence delimiters.
    // Sequential pairing is standard, but a stray/unbalanced fence (odd count)
    // can swallow real content (headings/tables) into a "code block". When the
    // fence count is odd, we drop opener candidates whose enclosed region looks
    // like real Markdown (contains an ATX heading), which recovers the content.
    private static func computeRealFences(_ lines: [String]) -> Set<Int> {
        var fenceIdx: [Int] = []
        for (idx, line) in lines.enumerated()
        where line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            fenceIdx.append(idx)
        }
        guard !fenceIdx.isEmpty else { return [] }

        // Well-formed (even count): pair sequentially.
        if fenceIdx.count % 2 == 0 {
            return Set(fenceIdx)
        }

        // Unbalanced: greedily pair, but skip an opener when the region it would
        // enclose contains an ATX heading line (strong sign of a stray fence).
        var result = Set<Int>()
        var k = 0
        while k < fenceIdx.count {
            let open = fenceIdx[k]
            guard k + 1 < fenceIdx.count else {
                // Dangling final opener with no close: ignore it (treat as text).
                break
            }
            let close = fenceIdx[k + 1]
            let encloses = (open + 1 < close)
                ? lines[(open + 1)..<close].contains(where: { looksLikeHeading($0) })
                : false
            if encloses {
                // Stray opener: skip just this one, retry pairing from next fence.
                k += 1
                continue
            }
            result.insert(open)
            result.insert(close)
            k += 2
        }
        return result
    }

    private static func looksLikeHeading(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return false }
        let hashes = t.prefix(while: { $0 == "#" })
        return hashes.count >= 1 && hashes.count <= 6
            && t.dropFirst(hashes.count).first == " "
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex && line[idx] == "#" && level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    private static func isUnorderedItem(_ line: String) -> Bool {
        return line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    // Parses "- [ ] text" / "- [x] text" (also * and +). Returns nil otherwise.
    private static func parseTaskItem(_ line: String) -> TaskItem? {
        guard isUnorderedItem(line) else { return nil }
        let afterMarker = String(line.dropFirst(2)) // drop "- "
        let lower = afterMarker.lowercased()
        if lower.hasPrefix("[ ] ") || lower == "[ ]" {
            return TaskItem(checked: false,
                            text: String(afterMarker.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }
        if lower.hasPrefix("[x] ") || lower == "[x]" {
            return TaskItem(checked: true,
                            text: String(afterMarker.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func stripUnorderedMarker(_ line: String) -> String {
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func isOrderedItem(_ line: String) -> Bool {
        // e.g. "1. text"
        guard let dotRange = line.range(of: ". ") else { return false }
        let prefix = line[line.startIndex..<dotRange.lowerBound]
        return !prefix.isEmpty && prefix.allSatisfy { $0.isNumber }
    }

    private static func stripOrderedMarker(_ line: String) -> String {
        guard let dotRange = line.range(of: ". ") else { return line }
        return String(line[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Tables

    // Matches a separator row such as "| --- | :--: |" or "---|---".
    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("-") else { return false }
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        for cell in cells {
            let allowed = cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
            if !allowed || !cell.contains("-") { return false }
        }
        return true
    }

    // Splits a table row on unescaped pipes that are not inside `code spans`.
    // Handles "\|" (escaped pipe) and pipes within backtick spans.
    private static func splitTableRow(_ line: String) -> [String] {
        let s = line.trimmingCharacters(in: .whitespaces)
        var cells: [String] = []
        var current = ""
        var inCode = false
        var escaped = false

        for ch in s {
            if escaped {
                // Preserve the escaped pipe as a literal pipe in the cell.
                current.append(ch == "|" ? "|" : "\\\(ch)")
                escaped = false
                continue
            }
            switch ch {
            case "\\":
                escaped = true
            case "`":
                inCode.toggle()
                current.append(ch)
            case "|" where !inCode:
                cells.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        cells.append(current)

        // Drop leading/trailing empty cells produced by the outer pipes.
        if let first = cells.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            cells.removeFirst()
        }
        if let last = cells.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            cells.removeLast()
        }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Images

    // Matches a line that is exactly ![alt](source), optionally with a title.
    private static func parseStandaloneImage(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("!["), let closeBracket = line.firstIndex(of: "]") else {
            return nil
        }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<closeBracket])
        let afterBracket = line.index(after: closeBracket)
        guard afterBracket < line.endIndex, line[afterBracket] == "(",
              line.hasSuffix(")") else { return nil }
        let inside = String(line[line.index(after: afterBracket)..<line.index(before: line.endIndex)])
        // Drop an optional quoted title while preserving spaces inside the URL.
        var source = inside.trimmingCharacters(in: .whitespaces)
        if source.hasSuffix("\"") || source.hasSuffix("'") {
            let quote = source.last!
            if let titleStart = source.dropLast().lastIndex(of: quote),
               titleStart > source.startIndex,
               source[source.index(before: titleStart)].isWhitespace {
                source = String(source[..<source.index(before: titleStart)])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        guard !source.isEmpty else { return nil }
        return .image(alt: alt, source: source)
    }
}

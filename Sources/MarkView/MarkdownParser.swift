import Foundation

// Incremental FNV-1a 64-bit hasher; stable across processes and launches.
struct FNV1a {
    private(set) var value: UInt64 = 0xcbf29ce484222325

    mutating func combine(byte: UInt8) {
        value ^= UInt64(byte)
        value = value &* 0x100000001b3
    }

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
    }
}

// A single task-list entry.
struct TaskItem: Hashable, Sendable {
    let checked: Bool
    let text: String
}

enum ListMarker: Hashable, Sendable {
    case unordered
    case ordered
    case task(checked: Bool)
}

struct ListItem: Hashable, Sendable {
    let marker: ListMarker
    let text: String
    let children: [ListItem]
}

// A lightweight block-level Markdown model.
//
// IDs are deterministic: derived from the block's content plus an occurrence
// counter (see MarkdownParser.assignStableIDs). Re-parsing the same document
// yields the same ID sequence, so SwiftUI keeps view identity (and scroll
// position) across auto-reloads; duplicate blocks still get distinct IDs.
enum MarkdownBlock: Identifiable, Sendable {
    case heading(id: String = "", level: Int, text: String)
    case paragraph(id: String = "", text: String)
    case unorderedList(id: String = "", items: [String])
    case orderedList(id: String = "", items: [String])
    case taskList(id: String = "", items: [TaskItem])
    case list(id: String = "", items: [ListItem])
    case codeBlock(id: String = "", language: String?, code: String)
    case quote(id: String = "", text: String)
    case table(id: String = "", headers: [String], rows: [[String]])
    case image(id: String = "", alt: String, source: String)
    case thematicBreak(id: String = "")

    var id: String {
        switch self {
        case .heading(let id, _, _),
             .paragraph(let id, _),
             .unorderedList(let id, _),
             .orderedList(let id, _),
             .taskList(let id, _),
             .list(let id, _),
             .codeBlock(let id, _, _),
             .quote(let id, _),
             .table(let id, _, _),
             .image(let id, _, _),
             .thematicBreak(let id):
            return id
        }
    }

    // A stable 64-bit digest of the block's content (FNV-1a, process- and
    // launch-independent, unlike Hasher). Field separators (0x1D-0x1F) keep
    // adjacent fields from aliasing each other.
    var contentHash: UInt64 {
        var h = FNV1a()
        switch self {
        case .heading(_, let level, let text):
            h.combine(byte: 0x01); h.combine(byte: UInt8(level)); h.combine(text)
        case .paragraph(_, let text):
            h.combine(byte: 0x02); h.combine(text)
        case .unorderedList(_, let items):
            h.combine(byte: 0x03)
            for item in items { h.combine(item); h.combine(byte: 0x1F) }
        case .orderedList(_, let items):
            h.combine(byte: 0x04)
            for item in items { h.combine(item); h.combine(byte: 0x1F) }
        case .taskList(_, let items):
            h.combine(byte: 0x05)
            for item in items {
                h.combine(byte: item.checked ? 1 : 0)
                h.combine(item.text); h.combine(byte: 0x1F)
            }
        case .list(_, let items):
            h.combine(byte: 0x0B)
            combine(items, into: &h)
        case .codeBlock(_, let language, let code):
            h.combine(byte: 0x06); h.combine(language ?? ""); h.combine(byte: 0x1E); h.combine(code)
        case .quote(_, let text):
            h.combine(byte: 0x07); h.combine(text)
        case .table(_, let headers, let rows):
            h.combine(byte: 0x08)
            for header in headers { h.combine(header); h.combine(byte: 0x1F) }
            h.combine(byte: 0x1E)
            for row in rows {
                for cell in row { h.combine(cell); h.combine(byte: 0x1F) }
                h.combine(byte: 0x1D)
            }
        case .image(_, let alt, let source):
            h.combine(byte: 0x09); h.combine(alt); h.combine(byte: 0x1E); h.combine(source)
        case .thematicBreak:
            h.combine(byte: 0x0A)
        }
        return h.value
    }

    private func combine(_ items: [ListItem], into hasher: inout FNV1a) {
        for item in items {
            switch item.marker {
            case .unordered:
                hasher.combine(byte: 0x01)
            case .ordered:
                hasher.combine(byte: 0x02)
            case .task(let checked):
                hasher.combine(byte: checked ? 0x04 : 0x03)
            }
            hasher.combine(item.text)
            hasher.combine(byte: 0x1E)
            combine(item.children, into: &hasher)
            hasher.combine(byte: 0x1D)
        }
    }

    func withID(_ newID: String) -> MarkdownBlock {
        switch self {
        case .heading(_, let level, let text):
            return .heading(id: newID, level: level, text: text)
        case .paragraph(_, let text):
            return .paragraph(id: newID, text: text)
        case .unorderedList(_, let items):
            return .unorderedList(id: newID, items: items)
        case .orderedList(_, let items):
            return .orderedList(id: newID, items: items)
        case .taskList(_, let items):
            return .taskList(id: newID, items: items)
        case .list(_, let items):
            return .list(id: newID, items: items)
        case .codeBlock(_, let language, let code):
            return .codeBlock(id: newID, language: language, code: code)
        case .quote(_, let text):
            return .quote(id: newID, text: text)
        case .table(_, let headers, let rows):
            return .table(id: newID, headers: headers, rows: rows)
        case .image(_, let alt, let source):
            return .image(id: newID, alt: alt, source: source)
        case .thematicBreak:
            return .thematicBreak(id: newID)
        }
    }
}

// Minimal, dependency-free Markdown block parser.
struct MarkdownParser {
    // Number of lines processed between cooperative cancellation checks.
    private static let cancellationCheckStride = 4_096

    static func parse(_ input: String) -> [MarkdownBlock] {
        // Non-cancellable parse never throws.
        (try? parse(input, checkingCancellation: false)) ?? []
    }

    // Cancellable variant used by background document loads: throws
    // CancellationError when the surrounding Task is cancelled, so stacked
    // reloads stop wasting CPU on obsolete documents.
    static func parse(
        _ input: String,
        checkingCancellation: Bool
    ) throws -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let realFences = computeRealFences(lines)

        var i = 0
        var paragraphBuffer: [String] = []
        var nextCancellationCheck = cancellationCheckStride

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
            if checkingCancellation, i >= nextCancellationCheck {
                try Task.checkCancellation()
                nextCancellationCheck = i + Self.cancellationCheckStride
            }

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

            // Consecutive list lines are parsed together so indentation and
            // mixed marker types can form a nested tree. Flat homogeneous runs
            // keep the legacy block cases for compatibility and fast rendering.
            if parseListLine(line) != nil {
                flushParagraph()
                var listLines: [ParsedListLine] = []
                while i < lines.count, let parsed = parseListLine(lines[i]) {
                    listLines.append(parsed)
                    i += 1
                }
                blocks.append(contentsOf: makeListBlocks(from: listLines))
                continue
            }

            // Default: accumulate paragraph
            paragraphBuffer.append(trimmed)
            i += 1
        }
        flushParagraph()
        return assignStableIDs(to: blocks)
    }

    // Derives a deterministic ID for each block from its content digest plus
    // an occurrence counter. Identical documents produce identical ID
    // sequences (stable view identity across reloads); duplicate blocks in
    // one document stay distinct via the occurrence index.
    private static func assignStableIDs(to blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        var occurrences: [UInt64: Int] = [:]
        occurrences.reserveCapacity(blocks.count)
        return blocks.map { block in
            let hash = block.contentHash
            let occurrence = occurrences[hash, default: 0]
            occurrences[hash] = occurrence + 1
            return block.withID("\(String(hash, radix: 16))-\(occurrence)")
        }
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

    private struct ParsedListLine {
        let indent: Int
        let marker: ListMarker
        let text: String
    }

    private struct MutableListItem {
        let marker: ListMarker
        let text: String
        var children: [MutableListItem]

        var value: ListItem {
            ListItem(marker: marker, text: text, children: children.map(\.value))
        }
    }

    private static func parseListLine(_ line: String) -> ParsedListLine? {
        var index = line.startIndex
        var indent = 0
        while index < line.endIndex {
            if line[index] == " " {
                indent += 1
            } else if line[index] == "\t" {
                indent += 4
            } else {
                break
            }
            index = line.index(after: index)
        }

        let content = String(line[index...])
        if let task = parseTaskItem(content) {
            return ParsedListLine(
                indent: indent,
                marker: .task(checked: task.checked),
                text: task.text
            )
        }
        if isUnorderedItem(content) {
            return ParsedListLine(
                indent: indent,
                marker: .unordered,
                text: stripUnorderedMarker(content)
            )
        }
        if isOrderedItem(content) {
            return ParsedListLine(
                indent: indent,
                marker: .ordered,
                text: stripOrderedMarker(content)
            )
        }
        return nil
    }

    private static func makeListBlocks(from lines: [ParsedListLine]) -> [MarkdownBlock] {
        guard let first = lines.first else { return [] }
        let hasNestedItem = lines.contains { $0.indent > first.indent }
        let markers = Set(lines.map(\.marker))

        if !hasNestedItem, markers.count == 1 {
            switch first.marker {
            case .unordered:
                return [.unorderedList(items: lines.map(\.text))]
            case .ordered:
                return [.orderedList(items: lines.map(\.text))]
            case .task:
                let tasks = lines.compactMap { line -> TaskItem? in
                    guard case .task(let checked) = line.marker else { return nil }
                    return TaskItem(checked: checked, text: line.text)
                }
                return [.taskList(items: tasks)]
            }
        }

        if !hasNestedItem {
            var blocks: [MarkdownBlock] = []
            var start = 0
            while start < lines.count {
                let marker = lines[start].marker
                var end = start + 1
                while end < lines.count, sameListKind(lines[end].marker, marker) {
                    end += 1
                }
                let run = Array(lines[start..<end])
                switch marker {
                case .unordered:
                    blocks.append(.unorderedList(items: run.map(\.text)))
                case .ordered:
                    blocks.append(.orderedList(items: run.map(\.text)))
                case .task:
                    blocks.append(.taskList(items: run.compactMap { line in
                        guard case .task(let checked) = line.marker else { return nil }
                        return TaskItem(checked: checked, text: line.text)
                    }))
                }
                start = end
            }
            return blocks
        }

        var roots: [MutableListItem] = []
        var path: [Int] = []
        var indentStack: [Int] = []

        for line in lines {
            while let lastIndent = indentStack.last, line.indent <= lastIndent {
                indentStack.removeLast()
                path.removeLast()
            }

            let item = MutableListItem(marker: line.marker, text: line.text, children: [])
            if path.isEmpty {
                roots.append(item)
                path = [roots.count - 1]
                indentStack = [line.indent]
            } else {
                append(item, to: &roots, parentPath: path)
                path.append(childCount(in: roots, at: path) - 1)
                indentStack.append(line.indent)
            }
        }

        return [.list(items: roots.map(\.value))]
    }

    private static func sameListKind(_ lhs: ListMarker, _ rhs: ListMarker) -> Bool {
        switch (lhs, rhs) {
        case (.unordered, .unordered), (.ordered, .ordered), (.task, .task): return true
        default: return false
        }
    }

    private static func append(
        _ item: MutableListItem,
        to roots: inout [MutableListItem],
        parentPath: [Int]
    ) {
        func appendRecursively(
            _ item: MutableListItem,
            to items: inout [MutableListItem],
            path: ArraySlice<Int>
        ) {
            guard let index = path.first else { return }
            if path.count == 1 {
                items[index].children.append(item)
            } else {
                appendRecursively(item, to: &items[index].children, path: path.dropFirst())
            }
        }
        appendRecursively(item, to: &roots, path: parentPath[...])
    }

    private static func childCount(in roots: [MutableListItem], at path: [Int]) -> Int {
        var items = roots
        var current: MutableListItem?
        for index in path {
            current = items[index]
            items = current?.children ?? []
        }
        return current?.children.count ?? 0
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

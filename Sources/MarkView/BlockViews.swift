import SwiftUI

// MARK: - Inline rendering

enum InlineSegment: Equatable, Sendable {
    case text(String)
    case image(alt: String, source: String)
}

func parseInlineSegments(_ input: String) -> [InlineSegment] {
    guard input.contains("![") else { return [.text(input)] }

    var segments: [InlineSegment] = []
    var textStart = input.startIndex
    var index = input.startIndex

    func appendText(through end: String.Index) {
        guard textStart < end else { return }
        let text = String(input[textStart..<end])
        if !text.isEmpty { segments.append(.text(text)) }
    }

    while index < input.endIndex {
        if input[index] == "`", !isEscaped(index, in: input) {
            let openerEnd = endOfBacktickRun(at: index, in: input)
            let length = input.distance(from: index, to: openerEnd)
            if let closerEnd = closingBacktickRun(length: length, after: openerEnd, in: input) {
                index = closerEnd
                continue
            }
            index = openerEnd
            continue
        }

        guard input[index...].hasPrefix("!["), !isEscaped(index, in: input),
              let parsed = parseInlineImage(at: index, in: input) else {
            index = input.index(after: index)
            continue
        }

        appendText(through: index)
        segments.append(.image(alt: parsed.alt, source: parsed.source))
        index = parsed.end
        textStart = parsed.end
    }

    appendText(through: input.endIndex)
    return segments.isEmpty ? [.text(input)] : segments
}

private func parseInlineImage(
    at start: String.Index,
    in input: String
) -> (alt: String, source: String, end: String.Index)? {
    let altStart = input.index(start, offsetBy: 2)
    guard let closeBracket = input[altStart...].firstIndex(of: "]") else { return nil }
    let openParen = input.index(after: closeBracket)
    guard openParen < input.endIndex, input[openParen] == "(" else { return nil }
    let sourceStart = input.index(after: openParen)
    guard let closeParen = input[sourceStart...].firstIndex(of: ")") else { return nil }

    let alt = String(input[altStart..<closeBracket])
    let source = String(input[sourceStart..<closeParen])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else { return nil }
    return (alt, source, input.index(after: closeParen))
}

// Renders inline Markdown (bold/italic/code/links) with <br> normalization.
// This is the single source of truth used both by the background cache
// builder and by the on-demand fallback path.
func renderInlineMarkdown(_ text: String) -> AttributedString {
    let normalized = replacingHTMLLineBreaks(in: text)
    if let attributed = try? AttributedString(
        markdown: normalized,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
        return attributed
    }
    return AttributedString(normalized)
}

// Immutable cache of pre-rendered inline strings, built off the main thread
// during document load so view bodies avoid AttributedString(markdown:) work.
struct InlineRenderCache: Sendable {
    static let empty = InlineRenderCache(storage: [:])

    private let storage: [String: AttributedString]

    private init(storage: [String: AttributedString]) {
        self.storage = storage
    }

    subscript(text: String) -> AttributedString? {
        storage[text]
    }

    // Above this block count, skip precomputing: LazyVStack only renders
    // visible rows on demand, so paying seconds of up-front render work for
    // huge documents would delay first paint for little benefit.
    static let precomputeBlockLimit = 20_000

    // Renders every inline-bearing string in the parsed document exactly once.
    static func build(
        for blocks: [MarkdownBlock],
        checkingCancellation: Bool = false
    ) throws -> InlineRenderCache {
        guard blocks.count <= precomputeBlockLimit else { return .empty }
        var storage: [String: AttributedString] = [:]
        var processed = 0

        func add(_ text: String) throws {
            for segment in parseInlineSegments(text) {
                guard case .text(let segmentText) = segment,
                      storage[segmentText] == nil else { continue }
                storage[segmentText] = renderInlineMarkdown(segmentText)
                processed += 1
                if checkingCancellation, processed % 512 == 0 {
                    try Task.checkCancellation()
                }
            }
        }

        for block in blocks {
            switch block {
            case .heading(_, _, let text), .paragraph(_, let text), .quote(_, let text):
                try add(text)
            case .unorderedList(_, let items), .orderedList(_, let items):
                for item in items { try add(item) }
            case .taskList(_, let items):
                for item in items { try add(item.text) }
            case .list(_, let items):
                func addItems(_ items: [ListItem]) throws {
                    for item in items {
                        try add(item.text)
                        try addItems(item.children)
                    }
                }
                try addItems(items)
            case .table(_, let headers, let rows):
                for header in headers { try add(header) }
                for row in rows { for cell in row { try add(cell) } }
            case .codeBlock, .image, .thematicBreak:
                continue // rendered as plain text; no inline pass needed
            }
        }
        return InlineRenderCache(storage: storage)
    }
}

// Shared inline Markdown renderer. Prefers the pre-rendered cache and falls
// back to on-demand rendering for strings not covered by it.
func inlineMarkdownText(_ text: String, cache: InlineRenderCache = .empty) -> Text {
    Text(cache[text] ?? renderInlineMarkdown(text))
}

func replacingHTMLLineBreaks(in text: String) -> String {
    // Fast paths: no "<" means nothing to replace; no "`" means no code
    // spans to protect, so the plain-text pass suffices.
    guard text.utf8.contains(UInt8(ascii: "<")) else { return text }
    guard text.utf8.contains(UInt8(ascii: "`")) else {
        return replacingHTMLLineBreaks(inPlainText: text)
    }

    var result = ""
    var plainStart = text.startIndex
    var index = text.startIndex

    while index < text.endIndex {
        guard text[index] == "`", !isEscaped(index, in: text) else {
            index = text.index(after: index)
            continue
        }

        let openerEnd = endOfBacktickRun(at: index, in: text)
        let delimiterLength = text.distance(from: index, to: openerEnd)
        guard let closerEnd = closingBacktickRun(
            length: delimiterLength,
            after: openerEnd,
            in: text
        ) else {
            index = openerEnd
            continue
        }

        result += replacingHTMLLineBreaks(inPlainText: String(text[plainStart..<index]))
        result += String(text[index..<closerEnd])
        index = closerEnd
        plainStart = closerEnd
    }

    result += replacingHTMLLineBreaks(inPlainText: String(text[plainStart...]))
    return result
}

// Compiled once; String(options: .regularExpression) re-parses the pattern
// on every call, which showed up in the hot render path.
private let htmlBreakRegex = try! NSRegularExpression(
    pattern: #"</?br\s*/?>"#,
    options: [.caseInsensitive]
)

private func replacingHTMLLineBreaks(inPlainText text: String) -> String {
    // Fast path: the vast majority of lines contain no "<" at all.
    guard text.utf8.contains(UInt8(ascii: "<")) else { return text }
    let range = NSRange(text.startIndex..., in: text)
    return htmlBreakRegex.stringByReplacingMatches(
        in: text,
        options: [],
        range: range,
        withTemplate: "\n"
    )
}

private func closingBacktickRun(
    length: Int,
    after start: String.Index,
    in text: String
) -> String.Index? {
    var index = start
    while index < text.endIndex {
        guard text[index] == "`", !isEscaped(index, in: text) else {
            index = text.index(after: index)
            continue
        }
        let runEnd = endOfBacktickRun(at: index, in: text)
        if text.distance(from: index, to: runEnd) == length {
            return runEnd
        }
        index = runEnd
    }
    return nil
}

private func endOfBacktickRun(at start: String.Index, in text: String) -> String.Index {
    var end = start
    while end < text.endIndex, text[end] == "`" {
        end = text.index(after: end)
    }
    return end
}

private func isEscaped(_ index: String.Index, in text: String) -> Bool {
    var cursor = index
    var backslashCount = 0
    while cursor > text.startIndex {
        let previous = text.index(before: cursor)
        guard text[previous] == "\\" else { break }
        backslashCount += 1
        cursor = previous
    }
    return backslashCount.isMultiple(of: 2) == false
}

// MARK: - Inline mixed content

struct InlineContentView: View {
    let content: String
    let baseURL: URL?
    var inlineCache: InlineRenderCache = .empty

    var body: some View {
        let segments = parseInlineSegments(content)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    inlineMarkdownText(text, cache: inlineCache)
                case .image(let alt, let source):
                    ImageBlockView(
                        alt: alt,
                        source: source,
                        baseURL: baseURL,
                        maximumHeight: 200
                    )
                }
            }
        }
    }
}

// MARK: - Table

struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    var baseURL: URL? = nil
    var inlineCache: InlineRenderCache = .empty

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            // Lazy rows: big tables only lay out what scrolls into view.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    dataRow(row, isEven: idx % 2 == 0)
                    if idx < rows.count - 1 { Divider().opacity(0.4) }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.3))
        )
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                cell(col < headers.count ? headers[col] : "")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                if col < columnCount - 1 {
                    Divider().frame(height: 18)
                }
            }
        }
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
    }

    private func dataRow(_ row: [String], isEven: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                cell(col < row.count ? row[col] : "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if col < columnCount - 1 {
                    Divider().frame(height: 18)
                }
            }
        }
        .padding(.vertical, 6)
        .background(isEven ? Color.clear : Color.secondary.opacity(0.05))
    }

    private func cell(_ content: String) -> some View {
        InlineContentView(content: content, baseURL: baseURL, inlineCache: inlineCache)
            .font(.body)
            .padding(.horizontal, 10)
            .textSelection(.enabled)
    }
}

// MARK: - Image

enum ImageSourceResolution: Equatable {
    case local(URL)
    case remote(URL)
    case rejected(String)
}

enum ImageSourceResolver {
    static func resolve(
        _ source: String,
        relativeTo baseURL: URL?
    ) -> ImageSourceResolution {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .rejected("Empty image source")
        }

        if let scheme = URLComponents(string: trimmed)?.scheme {
            guard scheme.lowercased() == "https" else {
                return .rejected("Only HTTPS remote images are allowed")
            }
            guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                  let url = URL(string: encoded),
                  url.scheme?.lowercased() == "https",
                  url.host != nil else {
                return .rejected("Invalid HTTPS image URL")
            }
            return .remote(url)
        }

        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("\\") else {
            return .rejected("Absolute image paths are not allowed")
        }
        guard let baseURL else {
            return .rejected("Local image has no document directory")
        }

        let base = baseURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = base
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard candidate.path.hasPrefix(basePath) else {
            return .rejected("Local image path escapes the document directory")
        }
        return .local(candidate)
    }
}

struct ImageBlockView: View {
    let alt: String
    let source: String
    let baseURL: URL?
    var maximumHeight: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            imageContent
            if !alt.isEmpty {
                Text(alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        switch ImageSourceResolver.resolve(source, relativeTo: baseURL) {
        case .local(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maximumHeight, alignment: .leading)
            } else {
                fallback("Cannot load local image: \(url.lastPathComponent)")
            }
        case .remote(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: maximumHeight, alignment: .leading)
                case .failure:
                    fallback("Cannot load remote image")
                @unknown default:
                    fallback("Cannot load image")
                }
            }
        case .rejected(let message):
            fallback(message)
        }
    }

    private func fallback(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
            Text("\(alt.isEmpty ? "" : "\(alt) — ")\(message)")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

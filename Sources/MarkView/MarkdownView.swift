import SwiftUI

// Centralized reading-typography constants. Tuned for comfortable long-form
// reading (including CJK text, which needs looser leading than Latin).
// The Quick Look renderer mirrors these values — adjust both together.
enum ReadingSpacing {
    /// Vertical gap between top-level blocks (paragraph → paragraph, etc.).
    static let block: CGFloat = 18
    /// Extra leading between wrapped lines inside a paragraph/quote.
    /// ~5pt on a 13pt body approximates a 1.4x effective line height.
    static let line: CGFloat = 5
    /// Vertical gap between items of the same list.
    static let listItem: CGFloat = 9
    /// Horizontal gap between a list marker (bullet/number/checkbox) and text.
    static let listMarkerGap: CGFloat = 10
    /// Indentation for each nested list level.
    static let nestedIndent: CGFloat = 28
    /// Extra space above major headings (h1/h2) separating sections.
    static let headingTopMajor: CGFloat = 16
    /// Extra space above minor headings (h3+).
    static let headingTopMinor: CGFloat = 8
}

// A contiguous run of blocks rendered as one lazy row. Chunking keeps the
// outer lazy list small (hundreds of rows instead of hundreds of thousands),
// which avoids exhausting SwiftUI's attribute graph on huge documents while
// still deferring off-screen layout work.
private struct BlockChunk: Identifiable {
    let id: String
    let blocks: ArraySlice<MarkdownBlock>
}

struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var baseURL: URL? = nil
    var inlineCache: InlineRenderCache = .empty

    private static let chunkSize = 64

    private var chunks: [BlockChunk] {
        stride(from: 0, to: blocks.count, by: Self.chunkSize).map { start in
            let slice = blocks[start..<min(start + Self.chunkSize, blocks.count)]
            // Chunk identity derives from its first block's stable ID, so
            // unchanged regions keep view identity across reloads.
            return BlockChunk(id: "\(slice.first?.id ?? "empty")@\(start)", blocks: slice)
        }
    }

    var body: some View {
        // Lazy at chunk granularity: only chunks near the viewport are
        // instantiated, so large documents stay responsive.
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(chunks) { chunk in
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(chunk.blocks) { block in
                        blockView(block)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(_, let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level <= 2 ? ReadingSpacing.headingTopMajor
                                          : ReadingSpacing.headingTopMinor)

        case .paragraph(_, let text):
            InlineContentView(content: text, baseURL: baseURL, inlineCache: inlineCache)
                .font(.body)
                .lineSpacing(ReadingSpacing.line)

        case .unorderedList(_, let items):
            VStack(alignment: .leading, spacing: ReadingSpacing.listItem) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: ReadingSpacing.listMarkerGap) {
                        Text("•").font(.body)
                        inlineText(item).font(.body).lineSpacing(ReadingSpacing.line)
                    }
                }
            }

        case .orderedList(_, let items):
            VStack(alignment: .leading, spacing: ReadingSpacing.listItem) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: ReadingSpacing.listMarkerGap) {
                        Text("\(idx + 1).").font(.body).monospacedDigit()
                        inlineText(item).font(.body).lineSpacing(ReadingSpacing.line)
                    }
                }
            }

        case .codeBlock(_, let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )
            }

        case .quote(_, let text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                inlineText(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

        case .taskList(_, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.checked ? Color.accentColor : Color.secondary)
                        inlineText(item.text)
                            .font(.body)
                            .foregroundStyle(item.checked ? .secondary : .primary)
                    }
                }
            }

        case .list(_, let items):
            NestedListView(items: items, inlineCache: inlineCache)

        case .table(_, let headers, let rows):
            TableBlockView(
                headers: headers,
                rows: rows,
                baseURL: baseURL,
                inlineCache: inlineCache
            )

        case .image(_, let alt, let source):
            ImageBlockView(alt: alt, source: source, baseURL: baseURL)

        case .thematicBreak:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 28)
        case 2: return .system(size: 23)
        case 3: return .system(size: 19)
        case 4: return .system(size: 16)
        default: return .system(size: 14)
        }
    }

    // Uses SwiftUI's native inline Markdown for bold/italic/code/links,
    // served from the background-built cache when available.
    private func inlineText(_ text: String) -> Text {
        inlineMarkdownText(text, cache: inlineCache)
    }
}

private struct NestedListView: View {
    let items: [ListItem]
    var inlineCache: InlineRenderCache = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: ReadingSpacing.listItem) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                NestedListItemView(
                    item: item,
                    orderedIndex: orderedIndex(at: index),
                    inlineCache: inlineCache
                )
            }
        }
    }

    private func orderedIndex(at index: Int) -> Int? {
        guard case .ordered = items[index].marker else { return nil }
        return items[..<index].reduce(1) { count, item in
            if case .ordered = item.marker { return count + 1 }
            return count
        }
    }
}

private struct NestedListItemView: View {
    let item: ListItem
    let orderedIndex: Int?
    var inlineCache: InlineRenderCache = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: ReadingSpacing.listItem) {
            HStack(alignment: .firstTextBaseline, spacing: ReadingSpacing.listMarkerGap) {
                marker
                    .frame(minWidth: 18, alignment: .trailing)
                inlineMarkdownText(item.text, cache: inlineCache)
                    .font(.body)
                    .lineSpacing(ReadingSpacing.line)
                    .foregroundStyle(taskChecked ? .secondary : .primary)
            }
            if !item.children.isEmpty {
                NestedListView(items: item.children, inlineCache: inlineCache)
                    .padding(.leading, ReadingSpacing.nestedIndent)
            }
        }
    }

    @ViewBuilder
    private var marker: some View {
        switch item.marker {
        case .unordered:
            Text("•").font(.body)
        case .ordered:
            Text("\(orderedIndex ?? 1).").font(.body).monospacedDigit()
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
        }
    }

    private var taskChecked: Bool {
        if case .task(let checked) = item.marker { return checked }
        return false
    }
}

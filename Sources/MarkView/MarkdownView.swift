import SwiftUI

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
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(_, let text):
            inlineText(text)
                .font(.body)
                .lineSpacing(3)

        case .unorderedList(_, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(.body)
                        inlineText(item).font(.body)
                    }
                }
            }

        case .orderedList(_, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).").font(.body).monospacedDigit()
                        inlineText(item).font(.body)
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

        case .table(_, let headers, let rows):
            TableBlockView(headers: headers, rows: rows)

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

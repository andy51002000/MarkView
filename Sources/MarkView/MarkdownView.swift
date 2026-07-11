import SwiftUI

struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var baseURL: URL? = nil
    var allowsRemoteImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                blockView(block)
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
            ImageBlockView(
                alt: alt,
                source: source,
                baseURL: baseURL,
                allowsRemoteImages: allowsRemoteImages
            )

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

    // Uses SwiftUI's native inline Markdown for bold/italic/code/links.
    private func inlineText(_ text: String) -> Text {
        inlineMarkdownText(text)
    }
}

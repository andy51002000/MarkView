import SwiftUI

// Shared inline Markdown renderer (bold/italic/code/links).
func inlineMarkdownText(_ text: String) -> Text {
    let normalized = replacingHTMLLineBreaks(in: text)
    if let attributed = try? AttributedString(
        markdown: normalized,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
        return Text(attributed)
    }
    return Text(normalized)
}

func replacingHTMLLineBreaks(in text: String) -> String {
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

private func replacingHTMLLineBreaks(inPlainText text: String) -> String {
    text.replacingOccurrences(
        of: #"</?br\s*/?>"#,
        with: "\n",
        options: [.regularExpression, .caseInsensitive]
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

// MARK: - Table

struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                dataRow(row, isEven: idx % 2 == 0)
                if idx < rows.count - 1 { Divider().opacity(0.4) }
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
        inlineMarkdownText(content)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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

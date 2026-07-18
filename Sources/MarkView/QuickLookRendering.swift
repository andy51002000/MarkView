import AppKit
import Foundation

// Renders parsed Markdown blocks into an NSAttributedString for the Quick
// Look preview extension (NSTextView-based). Shared with the main target so
// it stays unit-testable via `swift test`.
//
// Security model (stricter than the app): remote images are NEVER fetched —
// they render as a placeholder line. Local images must resolve inside the
// previewed file's directory (same ImageSourceResolver policy as the app).
enum QuickLookRenderer {

    // Documents beyond this many blocks are truncated with a notice; Quick
    // Look previews are meant to open instantly.
    static let blockLimit = 4_000

    static func attributedString(
        for blocks: [MarkdownBlock],
        baseURL: URL?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let shown = blocks.prefix(blockLimit)

        for block in shown {
            result.append(render(block, baseURL: baseURL))
            result.append(plain("\n"))
        }

        if blocks.count > blockLimit {
            result.append(styled(
                "… preview truncated (\(blocks.count - blockLimit) more blocks). Open in MarkView for the full document.",
                font: Fonts.base,
                color: .secondaryLabelColor
            ))
        }
        return result
    }

    // MARK: - Fonts / constants

    enum Fonts {
        static let base = NSFont.systemFont(ofSize: 13)
        static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        static func heading(_ level: Int) -> NSFont {
            let sizes: [CGFloat] = [24, 20, 17, 15, 13.5, 13]
            let size = sizes[min(max(level, 1), 6) - 1]
            return NSFont.boldSystemFont(ofSize: size)
        }

        static func bold(_ font: NSFont) -> NSFont {
            NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }

        static func italic(_ font: NSFont) -> NSFont {
            NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
    }

    private static let codeBackground = NSColor.textBackgroundColor.blended(
        withFraction: 0.5, of: .quaternaryLabelColor
    ) ?? .quaternaryLabelColor

    // MARK: - Block rendering

    private static func render(_ block: MarkdownBlock, baseURL: URL?) -> NSAttributedString {
        switch block {
        case .heading(_, let level, let text):
            return withParagraphSpacing(
                inline(text, font: Fonts.heading(level), baseURL: baseURL),
                spacingBefore: level <= 2 ? 10 : 6
            )

        case .paragraph(_, let text):
            return inline(text, font: Fonts.base, baseURL: baseURL)

        case .unorderedList(_, let items):
            return renderList(items.map { ListItem(marker: .unordered, text: $0, children: []) },
                              baseURL: baseURL)

        case .orderedList(_, let items):
            return renderList(items.map { ListItem(marker: .ordered, text: $0, children: []) },
                              baseURL: baseURL)

        case .taskList(_, let items):
            return renderList(items.map {
                ListItem(marker: .task(checked: $0.checked), text: $0.text, children: [])
            }, baseURL: baseURL)

        case .list(_, let items):
            return renderList(items, baseURL: baseURL)

        case .codeBlock(_, let language, let code):
            let m = NSMutableAttributedString()
            if let language, !language.isEmpty {
                m.append(styled(language + "\n", font: Fonts.mono.withSize(10),
                                color: .secondaryLabelColor))
            }
            let body = NSMutableAttributedString(
                string: code + "\n",
                attributes: [
                    .font: Fonts.mono,
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: codeBackground
                ]
            )
            m.append(body)
            return m

        case .quote(_, let text):
            let quoted = NSMutableAttributedString()
            for line in text.components(separatedBy: "\n") {
                quoted.append(styled("│ ", font: Fonts.base, color: .tertiaryLabelColor))
                quoted.append(inline(line, font: Fonts.base, baseURL: baseURL,
                                     color: .secondaryLabelColor))
                quoted.append(plain("\n"))
            }
            return quoted

        case .table(_, let headers, let rows):
            return renderTable(headers: headers, rows: rows, baseURL: baseURL)

        case .image(_, let alt, let source):
            return renderImage(alt: alt, source: source, baseURL: baseURL)

        case .thematicBreak:
            return styled(String(repeating: "\u{2500}", count: 36) + "\n",
                          font: Fonts.base, color: .tertiaryLabelColor)
        }
    }

    // MARK: - Lists

    private static func renderList(
        _ items: [ListItem],
        baseURL: URL?,
        depth: Int = 0,
        counter: inout Int
    ) -> NSAttributedString {
        let m = NSMutableAttributedString()
        for item in items {
            let indent = String(repeating: "    ", count: depth)
            let marker: String
            switch item.marker {
            case .unordered: marker = "•  "
            case .ordered:
                counter += 1
                marker = "\(counter).  "
            case .task(let checked): marker = checked ? "☑  " : "☐  "
            }
            m.append(styled(indent + marker, font: Fonts.base, color: .secondaryLabelColor))
            m.append(inline(item.text, font: Fonts.base, baseURL: baseURL))
            m.append(plain("\n"))
            if !item.children.isEmpty {
                var childCounter = 0
                m.append(renderList(item.children, baseURL: baseURL,
                                    depth: depth + 1, counter: &childCounter))
            }
        }
        return m
    }

    private static func renderList(
        _ items: [ListItem],
        baseURL: URL?
    ) -> NSAttributedString {
        var counter = 0
        return renderList(items, baseURL: baseURL, depth: 0, counter: &counter)
    }

    // MARK: - Tables

    private static func renderTable(
        headers: [String],
        rows: [[String]],
        baseURL: URL?
    ) -> NSAttributedString {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return plain("") }

        let table = NSTextTable()
        table.numberOfColumns = columns
        table.setContentWidth(100, type: .percentageValueType)

        let result = NSMutableAttributedString()
        let allRows = [headers] + rows

        for (rowIndex, row) in allRows.enumerated() {
            for column in 0..<columns {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex, rowSpan: 1,
                    startingColumn: column, columnSpan: 1
                )
                block.setBorderColor(.separatorColor)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setWidth(4, type: .absoluteValueType, for: .padding)
                if rowIndex == 0 {
                    block.backgroundColor = .quaternaryLabelColor
                }

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]

                let content = column < row.count ? row[column] : ""
                let font = rowIndex == 0 ? Fonts.bold(Fonts.base) : Fonts.base
                let cell = NSMutableAttributedString(
                    attributedString: inline(content, font: font, baseURL: baseURL)
                )
                cell.append(plain("\n"))
                cell.addAttribute(
                    .paragraphStyle, value: style,
                    range: NSRange(location: 0, length: cell.length)
                )
                result.append(cell)
            }
        }
        return result
    }

    // MARK: - Images

    private static func renderImage(
        alt: String,
        source: String,
        baseURL: URL?
    ) -> NSAttributedString {
        let label = alt.isEmpty ? "image" : alt
        switch ImageSourceResolver.resolve(source, relativeTo: baseURL) {
        case .remote:
            // Never fetch remote content from a Quick Look preview.
            return styled("🖼 \(label) (remote image not loaded in Quick Look)\n",
                          font: Fonts.base, color: .secondaryLabelColor)
        case .rejected(let reason):
            return styled("🖼 \(label) (\(reason))\n",
                          font: Fonts.base, color: .secondaryLabelColor)
        case .local(let url):
            guard let image = NSImage(contentsOf: url) else {
                return styled("🖼 \(label) (cannot load: \(url.lastPathComponent))\n",
                              font: Fonts.base, color: .secondaryLabelColor)
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            // Cap display width so huge images don't dominate the preview.
            let maxWidth: CGFloat = 560
            if image.size.width > maxWidth, image.size.width > 0 {
                let scale = maxWidth / image.size.width
                attachment.bounds = NSRect(
                    x: 0, y: 0,
                    width: maxWidth,
                    height: image.size.height * scale
                )
            }
            let m = NSMutableAttributedString(attachment: attachment)
            m.append(plain("\n"))
            if !alt.isEmpty {
                m.append(styled(alt + "\n", font: Fonts.base.withSize(11),
                                color: .secondaryLabelColor))
            }
            return m
        }
    }

    // MARK: - Inline rendering

    // Converts inline Markdown (bold/italic/code/links + <br> + inline
    // images) into an NSAttributedString with concrete AppKit attributes.
    static func inline(
        _ text: String,
        font: NSFont,
        baseURL: URL?,
        color: NSColor = .labelColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in parseInlineSegments(text) {
            switch segment {
            case .text(let value):
                result.append(resolveIntents(renderInlineMarkdown(value),
                                             baseFont: font, color: color))
            case .image(let alt, let source):
                result.append(renderImage(alt: alt, source: source, baseURL: baseURL))
            }
        }
        return result
    }

    // Maps SwiftUI-independent presentation intents from AttributedString
    // (produced by AttributedString(markdown:)) onto AppKit font traits so
    // NSTextView actually displays bold/italic/code/links.
    private static func resolveIntents(
        _ attributed: AttributedString,
        baseFont: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in attributed.runs {
            let runText = String(attributed[run.range].characters)
            var font = baseFont
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]

            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { font = Fonts.bold(font) }
                if intent.contains(.emphasized) { font = Fonts.italic(font) }
                if intent.contains(.code) {
                    font = Fonts.mono.withSize(max(font.pointSize - 1, 10))
                    attributes[.backgroundColor] = codeBackground
                }
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributes[.font] = font
            result.append(NSAttributedString(string: runText, attributes: attributes))
        }
        return result
    }

    // MARK: - Small helpers

    private static func plain(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: Fonts.base])
    }

    private static func styled(
        _ string: String,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color
        ])
    }

    private static func withParagraphSpacing(
        _ attributed: NSAttributedString,
        spacingBefore: CGFloat
    ) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attributed)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = 4
        m.addAttribute(.paragraphStyle, value: style,
                       range: NSRange(location: 0, length: m.length))
        return m
    }
}

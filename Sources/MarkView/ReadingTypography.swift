import SwiftUI

// Reading-typography tokens modeled on the Atlassian Design System
// (atlassian.design/foundations/typography), the system behind Confluence
// pages. Verified reference values:
//   - Body L (long-form default): 16px font / 24px line height (1.5x),
//     paragraph spacing 16px (1.0x font size)
//   - Heading scale: minor third (x1.2, rounded to multiples of 4):
//     32/28/24/20/16/14/12 with ~1.2x line height
//   - Long-form minimum font size: 16px; optimal line length 60-80 chars
//     (Confluence content column ~760px)
// Mapping to points (macOS pt ~= web px at 1x):
//   body 15pt (between Apple's 13pt UI default and Atlassian's 16px
//   long-form floor), line height 1.5x => 22.5pt target, paragraph gap
//   1.0x font => 15pt, headings from the Atlassian heading scale.
// The Quick Look renderer mirrors these values — adjust both together.
enum ReadingTypography {
    // MARK: Font sizes (Atlassian heading tokens, minor-third scale)
    /// Long-form body size. Atlassian Body L is 16px; 15pt keeps macOS
    /// text rendering crisp while staying near the long-form floor.
    static let bodySize: CGFloat = 15
    /// h1..h6 mapped to heading.xlarge(28)/large(24)/medium(20)/small(16)/
    /// xsmall(14)/xxsmall(12→13 floor for legibility).
    static let headingSizes: [CGFloat] = [28, 24, 20, 16, 14, 13]
    /// Code block / inline-code base (Atlassian font.code is smaller than body).
    static let codeSize: CGFloat = 13

    // MARK: Line rhythm
    /// Extra leading so body reaches ~1.5x line height (Confluence Body L).
    /// 15pt SF natural line height ≈ 18pt; +4.5 ≈ 22.5 = 1.5 x 15.
    static let line: CGFloat = 4.5
    /// Paragraph/block gap = 1.0x body font size (Atlassian Body L
    /// paragraph spacing token: 16px on 16px font).
    static let block: CGFloat = 15
    /// Heading line height multiplier is ~1.2x — SwiftUI's natural single-
    /// line height already approximates this; no extra leading needed.

    // MARK: Headings
    /// Space above h1/h2 ≈ 2x block gap total (Confluence separates major
    /// sections with roughly double paragraph rhythm). Rendered gap =
    /// block(15) + this padding.
    static let headingTopMajor: CGFloat = 17   // 15 + 17 = 32 total
    /// Space above h3-h6 ≈ 1.5x block gap total.
    static let headingTopMinor: CGFloat = 8    // 15 + 8 = 23 total

    // MARK: Lists
    /// Items in one list sit tighter than paragraphs (a list reads as one
    /// group): half the block gap.
    static let listItem: CGFloat = 8
    /// Marker-to-text gap.
    static let listMarkerGap: CGFloat = 10
    /// Nested list indent: Atlassian/Confluence indent lists by 24px/level.
    static let nestedIndent: CGFloat = 24

    // MARK: Layout
    /// Content column cap. Confluence's fixed-width content column is
    /// ~760px — the single biggest contributor to its reading feel.
    static let contentMaxWidth: CGFloat = 760
    /// Fonts derived from the tokens.
    static var bodyFont: Font { .system(size: bodySize) }
    static func headingFont(_ level: Int) -> Font {
        .system(size: headingSizes[min(max(level, 1), headingSizes.count) - 1])
    }

    /// Zoom-scaled metrics for the view layer. Pure value computation —
    /// no parsing, no cache interaction, cheap enough to derive per render.
    static func metrics(zoom: CGFloat) -> ReadingMetrics {
        ReadingMetrics(zoom: zoom)
    }
}

// All typography/layout tokens scaled by the current zoom factor.
// Views read these instead of the raw statics so browser-style zoom
// (⌘+/⌘−/⌘0) scales text and rhythm together.
struct ReadingMetrics: Equatable {
    let zoom: CGFloat

    var bodySize: CGFloat { ReadingTypography.bodySize * zoom }
    var codeSize: CGFloat { ReadingTypography.codeSize * zoom }
    var line: CGFloat { ReadingTypography.line * zoom }
    var block: CGFloat { ReadingTypography.block * zoom }
    var headingTopMajor: CGFloat { ReadingTypography.headingTopMajor * zoom }
    var headingTopMinor: CGFloat { ReadingTypography.headingTopMinor * zoom }
    var listItem: CGFloat { ReadingTypography.listItem * zoom }
    var listMarkerGap: CGFloat { ReadingTypography.listMarkerGap * zoom }
    var nestedIndent: CGFloat { ReadingTypography.nestedIndent * zoom }
    /// The reading column grows with zoom so zoomed text keeps the same
    /// characters-per-line rhythm instead of wrapping ever tighter.
    var contentMaxWidth: CGFloat { ReadingTypography.contentMaxWidth * zoom }

    var bodyFont: Font { .system(size: bodySize) }
    var codeFont: Font { .system(size: codeSize, design: .monospaced) }
    func headingFont(_ level: Int) -> Font {
        let sizes = ReadingTypography.headingSizes
        return .system(size: sizes[min(max(level, 1), sizes.count) - 1] * zoom)
    }
    func headingSize(_ level: Int) -> CGFloat {
        let sizes = ReadingTypography.headingSizes
        return sizes[min(max(level, 1), sizes.count) - 1] * zoom
    }
}

// Backward-compatible alias used across views.
typealias ReadingSpacing = ReadingTypography

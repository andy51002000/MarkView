import Foundation
import Testing
@testable import MarkView

@Suite @MainActor struct ZoomModelTests {

    private func freshModel() -> ZoomModel {
        let defaults = UserDefaults(suiteName: "zoom-tests-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: "zoom-tests")
        return ZoomModel(defaults: defaults)
    }

    @Test func defaultsTo100Percent() {
        let zoom = freshModel()
        #expect(zoom.scale == 1.0)
        #expect(zoom.percentText == "100%")
    }

    @Test func stepIncreasesByTenPercent() {
        let zoom = freshModel()
        zoom.zoomIn()
        #expect(abs(zoom.scale - 1.1) < 0.0001)
        #expect(zoom.percentText == "110%")
        zoom.zoomOut()
        zoom.zoomOut()
        #expect(abs(zoom.scale - 0.9) < 0.0001)
        #expect(zoom.percentText == "90%")
    }

    @Test func clampsAtBounds() {
        let zoom = freshModel()
        for _ in 0..<50 { zoom.zoomIn() }
        #expect(zoom.scale == ZoomModel.maxScale)
        #expect(!zoom.canZoomIn)
        #expect(zoom.canZoomOut)
        for _ in 0..<50 { zoom.zoomOut() }
        #expect(zoom.scale == ZoomModel.minScale)
        #expect(!zoom.canZoomOut)
        #expect(zoom.canZoomIn)
    }

    @Test func resetReturnsTo100() {
        let zoom = freshModel()
        zoom.zoomIn(); zoom.zoomIn(); zoom.zoomIn()
        zoom.reset()
        #expect(zoom.scale == 1.0)
    }

    @Test func repeatedStepsStayOnGrid() {
        let zoom = freshModel()
        // 30 mixed steps must never produce float-dust percentages.
        for i in 0..<30 {
            if i % 3 == 0 { zoom.zoomOut() } else { zoom.zoomIn() }
            let pct = zoom.scale * 100
            #expect(abs(pct - pct.rounded()) < 0.001,
                    "scale must stay on the 10% grid, got \(zoom.scale)")
        }
    }

    @Test func persistsAndRestores() {
        let suite = "zoom-tests-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let zoom = ZoomModel(defaults: defaults)
        zoom.zoomIn()
        zoom.zoomIn()
        let restored = ZoomModel(defaults: defaults)
        #expect(abs(restored.scale - 1.2) < 0.0001)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func storedOutOfRangeValueIsClamped() {
        let suite = "zoom-tests-clamp-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(9.9, forKey: "MarkViewZoomScale")
        let zoom = ZoomModel(defaults: defaults)
        #expect(zoom.scale == ZoomModel.maxScale)
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite struct ReadingMetricsTests {

    @Test func scalesAllTokensLinearly() {
        let base = ReadingTypography.metrics(zoom: 1.0)
        let doubled = ReadingTypography.metrics(zoom: 2.0)
        #expect(doubled.bodySize == base.bodySize * 2)
        #expect(doubled.codeSize == base.codeSize * 2)
        #expect(doubled.line == base.line * 2)
        #expect(doubled.block == base.block * 2)
        #expect(doubled.headingTopMajor == base.headingTopMajor * 2)
        #expect(doubled.headingTopMinor == base.headingTopMinor * 2)
        #expect(doubled.listItem == base.listItem * 2)
        #expect(doubled.listMarkerGap == base.listMarkerGap * 2)
        #expect(doubled.nestedIndent == base.nestedIndent * 2)
        #expect(doubled.contentMaxWidth == base.contentMaxWidth * 2)
    }

    @Test func headingScalePreservedUnderZoom() {
        let m = ReadingTypography.metrics(zoom: 1.5)
        for level in 1...6 {
            #expect(m.headingSize(level) ==
                    ReadingTypography.headingSizes[level - 1] * 1.5)
        }
        // Out-of-range levels clamp like the unscaled API.
        #expect(m.headingSize(0) == m.headingSize(1))
        #expect(m.headingSize(9) == m.headingSize(6))
    }

    @Test func unitZoomMatchesStaticTokens() {
        let m = ReadingTypography.metrics(zoom: 1.0)
        #expect(m.bodySize == ReadingTypography.bodySize)
        #expect(m.block == ReadingTypography.block)
        #expect(m.contentMaxWidth == ReadingTypography.contentMaxWidth)
    }

    // Architecture guarantee: zoom must not re-parse or disturb block
    // identity / cache contents. Parsing the same document before and
    // after computing metrics yields identical IDs, and the inline cache
    // is untouched by metric computation (it has no font dependency).
    @Test func zoomHasNoParserOrCacheSideEffects() throws {
        let doc = """
        # Title

        Body with **bold** and `code`.

        - item one
        - item two

        | A | B |
        | - | - |
        | 1 | 2 |
        """
        let before = MarkdownParser.parse(doc)
        let cacheBefore = try InlineRenderCache.build(for: before)

        // Simulate a zoom burst: compute many scaled metric sets.
        for z in stride(from: 0.5, through: 3.0, by: 0.1) {
            _ = ReadingTypography.metrics(zoom: z)
        }

        let after = MarkdownParser.parse(doc)
        let cacheAfter = try InlineRenderCache.build(for: after)

        #expect(before.map(\.id) == after.map(\.id),
                "Block ID sequence must be identical across zoom changes")
        // Cache coverage identical: same inline strings cached, same values.
        for text in ["Title", "Body with **bold** and `code`.",
                     "item one", "item two", "A", "1"] {
            #expect((cacheBefore[text] == nil) == (cacheAfter[text] == nil))
            #expect(cacheBefore[text] == cacheAfter[text])
        }
    }
}

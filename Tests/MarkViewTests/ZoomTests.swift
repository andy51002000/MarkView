import Combine
import Foundation
import Testing
@testable import MarkView

@Suite @MainActor struct ZoomModelTests {

    private final class PersistenceSpy {
        var values: [Double] = []
    }

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

    @Test func magnificationUpdatesContinuouslyAndPersistsOnlyOnEnd() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.0) { spy.values.append($0) }

        zoom.beginMagnification()
        zoom.updateMagnification(1.137)
        #expect(abs(zoom.scale - 1.137) < 0.0001)
        #expect(zoom.percentText == "114%")
        #expect(spy.values.isEmpty)

        zoom.updateMagnification(1.264)
        #expect(abs(zoom.scale - 1.264) < 0.0001)
        #expect(spy.values.isEmpty)

        zoom.endMagnification()
        #expect(abs(zoom.scale - 1.3) < 0.0001)
        #expect(spy.values == [1.3])
        #expect(!zoom.isMagnifying)
    }

    @Test func magnificationClampsAtBoundsWithoutDrift() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.0) { spy.values.append($0) }

        zoom.updateMagnification(10)
        #expect(zoom.scale == ZoomModel.maxScale)
        zoom.endMagnification()
        #expect(zoom.scale == ZoomModel.maxScale)

        zoom.updateMagnification(0.01)
        #expect(zoom.scale == ZoomModel.minScale)
        zoom.endMagnification()
        #expect(zoom.scale == ZoomModel.minScale)

        for _ in 0..<20 {
            zoom.updateMagnification(1.04)
            zoom.endMagnification()
        }
        #expect(zoom.scale == ZoomModel.minScale)
        #expect(spy.values == [ZoomModel.maxScale, ZoomModel.minScale])
    }

    @Test func cancelledMagnificationRestoresCommittedScaleWithoutPersisting() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.2) { spy.values.append($0) }

        zoom.updateMagnification(1.75)
        #expect(abs(zoom.scale - 2.1) < 0.0001)
        zoom.cancelMagnification()

        #expect(abs(zoom.scale - 1.2) < 0.0001)
        #expect(spy.values.isEmpty)
        #expect(!zoom.isMagnifying)
    }

    @Test func keyboardStepDuringGestureRebasesWithoutJumpingBack() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.0) { spy.values.append($0) }

        zoom.updateMagnification(1.5)
        #expect(abs(zoom.scale - 1.5) < 0.0001)
        zoom.zoomIn()
        #expect(abs(zoom.scale - 1.6) < 0.0001)
        #expect(spy.values == [1.6])

        zoom.updateMagnification(1.65)
        #expect(abs(zoom.scale - 1.76) < 0.0001)
        zoom.endMagnification()
        #expect(abs(zoom.scale - 1.8) < 0.0001)
        #expect(spy.values == [1.6, 1.8])
    }

    @Test func resetDuringGestureBecomesNewBase() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.4) { spy.values.append($0) }

        zoom.updateMagnification(1.5)
        zoom.reset()
        #expect(zoom.scale == 1.0)
        #expect(spy.values == [1.0])

        // Same magnification value after reset must stay at the reset scale.
        zoom.updateMagnification(1.5)
        #expect(zoom.scale == 1.0)
        zoom.updateMagnification(1.65)
        #expect(abs(zoom.scale - 1.1) < 0.0001)
        zoom.endMagnification()

        #expect(abs(zoom.scale - 1.1) < 0.0001)
        #expect(spy.values == [1.0, 1.1])
    }

    @Test func endingAtCommittedGridPointDoesNotWriteAgain() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.0) { spy.values.append($0) }

        zoom.updateMagnification(1.04)
        zoom.endMagnification()

        #expect(zoom.scale == 1.0)
        #expect(spy.values.isEmpty)
    }

    @Test func sameValueOutsideGestureDoesNotPublishOrPersist() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.0) { spy.values.append($0) }
        var publishedChanges = 0
        let observation = zoom.objectWillChange.sink { publishedChanges += 1 }
        defer { observation.cancel() }

        zoom.setScale(1.0)
        zoom.reset()

        #expect(zoom.scale == 1.0)
        #expect(publishedChanges == 0)
        #expect(spy.values.isEmpty)
    }

    @Test func sameValueDuringGestureRebasesWithoutPublishing() {
        let spy = PersistenceSpy()
        let zoom = ZoomModel(initialScale: 1.0) { spy.values.append($0) }

        zoom.updateMagnification(1.5)
        #expect(abs(zoom.scale - 1.5) < 0.0001)
        var publishedChanges = 0
        let observation = zoom.objectWillChange.sink { publishedChanges += 1 }
        defer { observation.cancel() }

        // 1.5 snaps to the current 1.5, but must still become the new gesture
        // base at magnification 1.5 so subsequent movement is relative to it.
        zoom.setScale(1.5)
        #expect(publishedChanges == 0)
        #expect(spy.values == [1.5])

        zoom.updateMagnification(1.65)
        #expect(abs(zoom.scale - 1.65) < 0.0001)
        zoom.endMagnification()
        #expect(abs(zoom.scale - 1.7) < 0.0001)
        #expect(spy.values == [1.5, 1.7])
    }

    @Test func committedMagnificationRestoresAfterRelaunch() {
        let suite = "zoom-tests-pinch-restore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let zoom = ZoomModel(defaults: defaults)

        zoom.updateMagnification(1.74)
        zoom.endMagnification()
        let restored = ZoomModel(defaults: defaults)

        #expect(abs(zoom.scale - 1.7) < 0.0001)
        #expect(abs(restored.scale - 1.7) < 0.0001)
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

    // Review regression guards: these dimensions were once hard-coded
    // (760 / 18 / 3) and did not track zoom.
    @Test func contentColumnScalesWithZoom() {
        #expect(ReadingTypography.metrics(zoom: 1.0).contentMaxWidth == 760)
        #expect(ReadingTypography.metrics(zoom: 3.0).contentMaxWidth == 2280,
                "300% zoom must widen the column 3x to keep chars/line")
        #expect(ReadingTypography.metrics(zoom: 0.5).contentMaxWidth == 380)
    }

    @Test func tableDividerTracksBodyLine() {
        let base = ReadingTypography.metrics(zoom: 1.0)
        #expect(base.tableDividerHeight == base.bodySize + base.line,
                "divider = one body line, not a fixed 18pt")
        let zoomed = ReadingTypography.metrics(zoom: 3.0)
        #expect(zoomed.tableDividerHeight == base.tableDividerHeight * 3)
    }

    @Test func quoteBarScalesWithinBounds() {
        #expect(ReadingTypography.metrics(zoom: 1.0).quoteBarWidth == 3)
        #expect(ReadingTypography.metrics(zoom: 0.5).quoteBarWidth == 2,
                "min clamp keeps the bar visible at 50%")
        #expect(ReadingTypography.metrics(zoom: 3.0).quoteBarWidth == 6,
                "max clamp keeps the bar tasteful at 300%")
        #expect(ReadingTypography.metrics(zoom: 1.5).quoteBarWidth == 4.5)
    }

    // Architecture guarantee: zoom must not re-parse or disturb block
    // identity / cache contents. Parsing the same document before and
    // after computing metrics yields identical IDs, and the inline cache
    // is untouched by metric computation (it has no font dependency).
    @Test @MainActor func zoomHasNoParserOrCacheSideEffects() throws {
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

        // Simulate 10 trackpad sessions with continuous unsnapped updates.
        let zoom = ZoomModel(initialScale: 1.0) { _ in }
        for session in 0..<10 {
            let direction = session.isMultiple(of: 2) ? 1.0 : -1.0
            for frame in 0..<24 {
                let magnification = 1.0 + direction * Double(frame) * 0.008
                zoom.updateMagnification(magnification)
                _ = ReadingTypography.metrics(zoom: zoom.scale)
            }
            zoom.endMagnification()
        }

        let after = MarkdownParser.parse(doc)
        let cacheAfter = try InlineRenderCache.build(for: after)

        #expect(before.count == after.count)
        #expect(before.map(\.id) == after.map(\.id),
                "Block ID sequence must be identical across zoom changes")
        #expect(makeBlockChunks(before).map(\.id) == makeBlockChunks(after).map(\.id),
                "64-block LazyVStack chunking must be unaffected by zoom")
        // Cache coverage identical: same inline strings cached, same values.
        for text in ["Title", "Body with **bold** and `code`.",
                     "item one", "item two", "A", "1"] {
            #expect((cacheBefore[text] == nil) == (cacheAfter[text] == nil))
            #expect(cacheBefore[text] == cacheAfter[text])
        }
    }
}

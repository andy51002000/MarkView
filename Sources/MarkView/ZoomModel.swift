import Foundation
import SwiftUI

// Browser-style zoom state. Pure view-layer preference: changing zoom never
// touches DocumentLoader/MarkdownParser, never mutates blocks or the
// InlineRenderCache — views just re-evaluate fonts/spacing from the scaled
// typography metrics.
@MainActor
final class ZoomModel: ObservableObject {
    // 50%–300% in 10% steps, matching common browser behavior.
    static let minScale: Double = 0.5
    static let maxScale: Double = 3.0
    static let step: Double = 0.1
    static let defaultScale: Double = 1.0

    private static let defaultsKey = "MarkViewZoomScale"

    @Published private(set) var scale: Double

    private let persistScale: (Double) -> Void
    private var committedScale: Double
    private var gestureBaseScale: Double?
    private var gestureReferenceMagnification = 1.0
    private var latestMagnification = 1.0

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.double(forKey: Self.defaultsKey)
        let initial = stored == 0 ? Self.defaultScale : Self.clamp(stored)
        self.scale = initial
        self.committedScale = initial
        self.persistScale = { defaults.set($0, forKey: Self.defaultsKey) }
    }

    init(initialScale: Double, persistScale: @escaping (Double) -> Void) {
        let initial = Self.clamp(initialScale)
        self.scale = initial
        self.committedScale = initial
        self.persistScale = persistScale
    }

    var percentText: String {
        "\(Int((scale * 100).rounded()))%"
    }

    var canZoomIn: Bool { scale < Self.maxScale - 0.0001 }
    var canZoomOut: Bool { scale > Self.minScale + 0.0001 }
    var isMagnifying: Bool { gestureBaseScale != nil }

    func zoomIn() {
        setScale(scale + Self.step)
    }

    func zoomOut() {
        setScale(scale - Self.step)
    }

    func reset() {
        setScale(Self.defaultScale)
    }

    func setScale(_ newValue: Double) {
        let final = Self.snap(newValue)
        scale = final
        commit(final)

        // A toolbar or keyboard command during a pinch becomes the new base at
        // the gesture's current magnification, so later changes never jump back.
        if gestureBaseScale != nil {
            gestureBaseScale = final
            gestureReferenceMagnification = latestMagnification
        }
    }

    func beginMagnification() {
        guard gestureBaseScale == nil else { return }
        gestureBaseScale = scale
        gestureReferenceMagnification = 1.0
        latestMagnification = 1.0
    }

    func updateMagnification(_ magnification: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        if gestureBaseScale == nil { beginMagnification() }
        latestMagnification = magnification
        guard let base = gestureBaseScale else { return }
        let relative = magnification / gestureReferenceMagnification
        scale = Self.clamp(base * relative)
    }

    func endMagnification(_ magnification: Double? = nil) {
        guard gestureBaseScale != nil else { return }
        if let magnification { updateMagnification(magnification) }
        let final = Self.snap(scale)
        scale = final
        clearGesture()
        commit(final)
    }

    func cancelMagnification() {
        guard gestureBaseScale != nil else { return }
        scale = committedScale
        clearGesture()
    }

    private func commit(_ value: Double) {
        guard abs(value - committedScale) > 0.0001 else { return }
        committedScale = value
        persistScale(value)
    }

    private func clearGesture() {
        gestureBaseScale = nil
        gestureReferenceMagnification = 1.0
        latestMagnification = 1.0
    }

    static func snap(_ value: Double) -> Double {
        let clamped = clamp(value)
        return clamp((clamped / step).rounded() * step)
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, minScale), maxScale)
    }
}

// Environment plumbing: views read zoom-scaled typography metrics from the
// environment so every block/list/table cell scales without threading a
// parameter through the whole view tree.
private struct ReadingMetricsKey: EnvironmentKey {
    static let defaultValue = ReadingMetrics(zoom: 1.0)
}

extension EnvironmentValues {
    var readingMetrics: ReadingMetrics {
        get { self[ReadingMetricsKey.self] }
        set { self[ReadingMetricsKey.self] = newValue }
    }
}

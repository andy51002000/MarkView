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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.defaultsKey)
        self.scale = stored == 0 ? Self.defaultScale : Self.clamp(stored)
    }

    var percentText: String {
        "\(Int((scale * 100).rounded()))%"
    }

    var canZoomIn: Bool { scale < Self.maxScale - 0.0001 }
    var canZoomOut: Bool { scale > Self.minScale + 0.0001 }

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
        // Snap to the step grid so repeated +/- never accumulates float dust
        // (0.30000000000000004%-style artifacts in the label).
        let clamped = Self.clamp(newValue)
        let snapped = (clamped / Self.step).rounded() * Self.step
        let final = Self.clamp(snapped)
        guard final != scale else { return }
        scale = final
        defaults.set(final, forKey: Self.defaultsKey)
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

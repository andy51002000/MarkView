import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var zoom: ZoomModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                store.openWithPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                store.reload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(store.fileURL == nil)

            CopyFeedbackButton(title: "Copy Path", systemImage: "doc.on.clipboard") {
                store.copyPath()
            }
            .disabled(store.fileURL == nil)

            CopyFeedbackButton(title: "Copy Markdown", systemImage: "doc.on.doc") {
                store.copyMarkdown()
            }
            .disabled(store.rawText.isEmpty)

            Spacer()

            zoomControl

            Text(store.fileName.isEmpty ? "No file" : store.fileName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
    }

    // Compact browser-style zoom control: − / percentage / +.
    // Clicking the percentage resets to 100%.
    private var zoomControl: some View {
        HStack(spacing: 2) {
            Button {
                zoom.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(!zoom.canZoomOut)
            .help("Zoom out (⌘−)")
            .accessibilityLabel("Zoom Out")

            Button {
                zoom.reset()
            } label: {
                Text(zoom.percentText)
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 44)
            }
            .buttonStyle(.borderless)
            .help("Reset zoom to 100% (⌘0)")
            .accessibilityLabel("Reset Zoom")
            .accessibilityValue(zoom.percentText)
            .accessibilityIdentifier("zoom-reset")

            Button {
                zoom.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(!zoom.canZoomIn)
            .help("Zoom in (⌘+)")
            .accessibilityLabel("Zoom In")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.errorMessage {
            emptyState(icon: "exclamationmark.triangle", title: error)
        } else if store.rawText.isEmpty {
            emptyState(icon: "doc.text",
                       title: "Open a Markdown file to preview it",
                       subtitle: "⌘O — supports .md and .markdown")
        } else {
            // Metrics derived here (not from the toolbar's environment scope)
            // so the reading column scales with the zoom factor: at 300% the
            // column is 3x wide, preserving characters-per-line rhythm.
            let metrics = ReadingTypography.metrics(zoom: zoom.scale)
            ScrollView {
                MarkdownView(
                    blocks: store.blocks,
                    baseURL: store.baseURL,
                    inlineCache: store.inlineCache
                )
                .environment(\.readingMetrics, metrics)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: metrics.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DocumentStore

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

            Text(store.fileName.isEmpty ? "No file" : store.fileName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
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
            ScrollView {
                MarkdownView(
                    blocks: store.blocks,
                    baseURL: store.baseURL,
                    inlineCache: store.inlineCache
                )
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: ReadingTypography.contentMaxWidth, alignment: .leading)
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

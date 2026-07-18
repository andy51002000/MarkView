import Cocoa
import Quartz

// Quick Look preview extension entry point. Compiled together with the
// shared parser/renderer sources by install.sh (see MarkViewQuickLook.appex
// assembly there); not part of the SwiftPM build.
class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        // Never called with a nib; provide a plain container view.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 800))
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let rendered: NSAttributedString
            do {
                let document = try DocumentLoader.load(url: url)
                rendered = QuickLookRenderer.attributedString(
                    for: document.blocks,
                    baseURL: url.deletingLastPathComponent().standardizedFileURL
                )
            } catch {
                DispatchQueue.main.async { handler(error) }
                return
            }

            DispatchQueue.main.async {
                self.install(rendered)
                handler(nil)
            }
        }
    }

    private func install(_ content: NSAttributedString) {
        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0,
            width: scrollView.contentSize.width,
            height: scrollView.contentSize.height
        ))
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(content)

        scrollView.documentView = textView
        view.addSubview(scrollView)
    }
}

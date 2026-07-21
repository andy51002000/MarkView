# MarkView

A fast, lightweight, **native macOS Markdown viewer** built with SwiftUI — no Electron, no external dependencies. It opens `.md` / `.markdown` files and renders a read-only preview of common Markdown.

> **MarkView at a glance:** ~1 MB native SwiftUI app (660 KB binary) — a free, actively-maintained, zero-dependency Markdown viewer for macOS (13+). No Electron. Press Space in Finder to preview `.md` files. MIT licensed. Free alternative to Marked 2.

**Website:** https://andy51002000.github.io/MarkView/

## Features

- Native SwiftUI app (low memory footprint, instant launch)
- Open `.md`, `.markdown`, `.mdown`, `.txt` via toolbar button or `⌘O`
- Read-only rendering of:
  - Headings (`#`–`######`)
  - Paragraphs with inline **bold**, *italic*, `inline code`, and [links](https://example.com)
  - Unordered, ordered, and task lists with mixed nested indentation
  - Fenced code blocks (```` ``` ````) with language label
  - Blockquotes
  - GitHub-style pipe tables (header separator, uneven rows handled)
  - Standalone and inline images in paragraphs/table cells — contained local paths and remote HTTPS images load automatically; unsafe or missing images show a fallback
  - Horizontal rules
- Manual reload with `⌘R` plus automatic refresh when the open file changes externally, including atomic saves
- Browser-style zoom: `⌘+` / `⌘−` / `⌘0`, 50%–300% in 10% steps, with a toolbar control — pure display scaling (no re-parse), instant even on 100k-block files
- Text selection enabled
- Zero third-party dependencies (pure SwiftPM + SwiftUI)

See the full [User Guide](docs/user-guide.md) for shortcuts and behavior details.

## Key metrics

| Metric | Value |
|--------|-------|
| Installed app size | ~1.2 MB (executable ~660 KB) |
| Parse time (5 MB / 115k-block document) | ~0.4 s (background, UI never freezes) |
| Third-party dependencies | 0 (pure SwiftPM + SwiftUI) |
| License | MIT (free) |
| Minimum macOS | 13 (Ventura), Intel & Apple Silicon |
| Xcode required to build | No — Swift Command Line Tools are enough |

## How MarkView compares

| App | Price | Approx. size* | Engine | Role |
|-----|-------|--------------|--------|------|
| **MarkView** | **Free (MIT)** | **~1.2 MB** | Native SwiftUI | Viewer |
| Marked 2 | $13.99 | ~8 MB | Native (WebKit) | Viewer |
| Typora | $14.99 | ~90 MB | Electron | Editor |
| MacDown | Free | ~13 MB | Native | Editor (no longer actively maintained) |
| Obsidian | Free / paid sync | ~213 MB | Electron | Knowledge base |
| VS Code | Free | ~500 MB | Electron | Editor / IDE |

*Sizes and prices approximate as of mid-2026, from vendor download pages. All of these are excellent tools — MarkView's niche is the **free + native + actively-maintained pure viewer** combination: reading Markdown without paying, without Electron, and without a setup ceremony.

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ toolchain (Swift 6.x works). Full Xcode is **not** required — Command Line Tools are enough for `swift build`/`swift run`.

## Build

```bash
swift build
```

Release build:

```bash
swift build -c release
```

## Run (fastest local path)

```bash
swift run
```

This launches the app window. Click **Open** (or press `⌘O`) and choose a Markdown file — e.g. the bundled `Samples/SAMPLE.md`.

> Note: `swift run` launches an unbundled executable. NSOpenPanel and the window work when run from a normal user session (a logged-in macOS desktop). If launched over a headless/SSH session without a window server, the GUI cannot display — build still succeeds.

## Install as a default `.md` / `.markdown` app

Build a `.app` bundle, install it to `~/Applications`, register it with LaunchServices, and set it as the default handler for Markdown files:

```bash
bash install.sh
```

After this, double-clicking a `.md` or `.markdown` file in Finder opens it in MarkView. The app also supports `⌘O` and multiple file open events.

> If Finder still shows an old app in "Open With", right-click a file → Open With → Other → MarkView, or log out/in to let LaunchServices refresh its cache. macOS may show a Gatekeeper prompt on first launch because the bundle is ad-hoc signed (right-click → Open to approve).

## Quick Look preview (press Space in Finder)

`install.sh` also builds and embeds a **Quick Look preview extension**
(`MarkViewQuickLook.appex`), so selecting a `.md` / `.markdown` file in Finder
and pressing **Space** shows a rendered preview (headings, lists — including
nested, tables, code blocks, quotes, links, local images) instead of plain
text. The extension is compiled with `swiftc` directly — no Xcode required —
and reuses the app's parser.

Quick Look previews follow a stricter security model than the app:

- **Remote images are never fetched** in a preview (a placeholder line is
  shown instead), so pressing Space on an untrusted document contacts no
  network hosts.
- Local images must live inside the previewed file's directory (same
  path-escape rules as the app).
- Very large documents are truncated in the preview with a notice; open the
  file in MarkView for the full render.

If a preview still shows plain text after installing:

1. Check the extension is registered: `pluginkit -m -p com.apple.quicklook.preview | grep markview`
2. Make sure it is enabled in **System Settings → Login Items & Extensions →
   Quick Look**.
3. Reset the Quick Look cache: `qlmanage -r && qlmanage -r cache`, then retry.

## Tests

Run the unit test suite (parser + image-source security):

```bash
swift test        # with full Xcode installed
make test         # with Command Line Tools only (adds the framework search flags)
```

The tests use the Swift Testing library. With a CLT-only setup,
`Testing.framework` is not on the default search path, so `make test` passes
the required `-F`/`-rpath` flags to `swift test` automatically.

## Manual verification

1. `swift build` — compiles with no errors.
2. `swift run` — the window appears with an empty-state prompt.
3. Press `⌘O` (or click **Open**) and select `Samples/SAMPLE.md`.
4. Confirm the preview shows: the H1 title, headings, bold/italic/inline-code, a link, both list types, a Swift code block, a blockquote, and a horizontal rule.

## Project structure

```
Package.swift
Sources/MarkView/
  MarkViewApp.swift      # @main app entry point + menu commands
  ContentView.swift      # window layout, toolbar, empty states
  DocumentStore.swift    # file open, reload state, and monitoring lifecycle
  DocumentLoader.swift   # size-limited background-safe file loading
  FileWatcher.swift      # debounced file and directory change monitoring
  MarkdownParser.swift   # dependency-free block parser
  MarkdownView.swift     # SwiftUI block renderer (uses AttributedString for inline)
  BlockViews.swift       # table/image block views + image source security
  QuickLookRendering.swift # NSAttributedString renderer shared with the QL extension
QuickLookExtension/      # Quick Look preview extension (built by install.sh)
  PreviewViewController.swift
  Info.plist
  MarkViewQuickLook.entitlements
Tests/MarkViewTests/     # test suite (parser, image security, QL rendering)
Samples/SAMPLE.md        # demo document exercising all features
```

## Privacy & security model for images

- **Remote HTTPS images load automatically.** Opening an untrusted document can
  contact image hosts referenced by that document.
- **HTTPS only.** Plain `http://` image URLs are never loaded. `file://` and
  every other scheme are always rejected.
- **Local images are sandboxed to the document folder.** Relative paths are
  resolved against the opened file's directory; absolute paths and `../`
  traversal that escapes that directory are rejected (symlinks are resolved
  before the check).

## Notes / limitations

- The block parser intentionally targets common Markdown rather than the full CommonMark specification. Inline emphasis/links use SwiftUI's native `AttributedString(markdown:)`.
- Tables use GitHub pipe syntax and require the `| --- |` separator row under the header.
- Remote HTTPS images load automatically; HTTP is never loaded. Local images must use paths that remain inside the opened `.md` file's directory.
- To make a double-clickable `.app`, wrap the release binary in an app bundle (future enhancement); for the MVP, `swift run` is the fastest path.

## FAQ

**Is MarkView free?**
Yes — MIT licensed, zero cost, no subscription, no in-app purchase, no telemetry.

**Is MarkView a viewer or an editor?**
Viewer only. It never modifies your files; pair it with any editor (VS Code, Vim, Sublime Text) for writing.

**Does it work without Xcode?**
Yes. Swift Command Line Tools are sufficient (`xcode-select --install`).

**How do I get Quick Look previews in Finder?**
Run `bash install.sh`. It builds and registers the Quick Look extension; pressing Space on a `.md` file in Finder then shows rendered Markdown.

**Is it safe to open untrusted files?**
MarkView is read-only and isolates untrusted content: HTTPS-only remote images, local images sandboxed to the document folder (`../` traversal blocked), and a Quick Look extension that makes zero network requests.

**Why is it only ~1 MB when Obsidian is ~213 MB?**
MarkView renders with SwiftUI, which ships with macOS. Obsidian, Typora, and VS Code bundle a full Chromium/Electron runtime.

**Is this a Marked 2 alternative?**
For free native Markdown viewing, yes. Marked 2 ($13.99) has more theming/export features; MarkView is free, MIT open-source, smaller (~1 MB installed), and has a stricter image-security model.

**Does it handle large files?**
A 5 MB / 115,000-block document parses in ~0.4 s in the background; the UI stays responsive throughout.

## Contributing

Contributions are welcome. To get started:

```bash
swift build   # compile
swift test    # run the unit tests (or `make test` with CLT-only setups)
```

Please keep changes dependency-free (pure SwiftPM + SwiftUI) and add or update
tests for parser and image-security behavior.

## License

MarkView is released under the [MIT License](LICENSE).
Copyright (c) MarkView Contributors.

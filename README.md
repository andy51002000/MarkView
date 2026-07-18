# MarkView

A fast, lightweight, **native macOS Markdown viewer** built with SwiftUI — no Electron, no external dependencies. It opens `.md` / `.markdown` files and renders a read-only preview of common Markdown.

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
- Text selection enabled
- Zero third-party dependencies (pure SwiftPM + SwiftUI)

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
Tests/MarkViewTests/     # XCTest suite (parser, image source resolution)
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

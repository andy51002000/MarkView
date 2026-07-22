# MarkView User Guide

MarkView is a read-only Markdown viewer for macOS. This guide covers everyday
usage, keyboard shortcuts, and behavior details.

## Opening files

- **⌘O** or the **Open** toolbar button — pick any `.md`, `.markdown`,
  `.mdown`, or `.txt` file.
- Double-click a Markdown file in Finder once MarkView is set as the default
  opener (`install.sh` offers this during installation).
- Drag a file onto the app icon in the Dock.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘O | Open a file |
| ⌘R | Reload the current file |
| ⌘+ (or ⌘=) | Zoom in (10% steps) |
| ⌘− | Zoom out (10% steps) |
| ⌘0 | Reset zoom to 100% |

## Zoom

MarkView zooms like a browser: text, headings, code, tables, list markers,
and all spacing scale together, and the reading column widens proportionally
so the characters-per-line rhythm stays constant.

- Range: **50% – 300%**.
- Trackpad: pinch with two fingers over the Markdown content. The preview and
  percentage update continuously while pinching; releasing snaps to the nearest
  10% and saves that level. If macOS cancels the gesture, MarkView returns to
  the last committed level without writing a preference. Two-finger scrolling
  continues to work normally.
- The gesture is content-only: pinching over the toolbar does not zoom.
- Controls: the **− / percentage / +** control in the toolbar (click the
  percentage to reset to 100%), or the shortcuts above (also in the View menu).
  Toolbar and keyboard changes use 10% steps and take effect immediately, even
  during a pinch, without jumping back when the gesture ends.
- The committed zoom level applies app-wide and is remembered across launches.
- Images are never upscaled beyond their natural size; only their surrounding
  spacing scales.
- Zooming is a pure display setting — the document is not re-parsed, so even
  100k-block files re-render instantly at the new size.

## Auto-reload

When the opened file changes on disk (including atomic saves from editors
like VS Code), MarkView refreshes the preview automatically and keeps your
scroll position for unchanged content. ⌘R forces a reload at any time.

## Toolbar utilities

- **Copy Path** — puts the absolute file path on the clipboard.
- **Copy Markdown** — copies the full Markdown source.
- Both flash a green checkmark to confirm the copy.

## Quick Look (Finder preview)

After running `install.sh`, select any `.md` file in Finder and press
**Space** to see rendered Markdown without launching the app. Quick Look
previews use a fixed **100%** system-readable text size — they intentionally do
**not** follow the app's zoom preference or trackpad pinch gestures, since Quick
Look panels are sized by the system and shared across apps.

## Security model

- Remote images load only over HTTPS, and only after you click
  **Load Remote Images** for the current document.
- Local images must live inside the opened file's folder; paths that escape
  it (absolute or `../`) are rejected.
- Quick Look previews never make network requests.
- MarkView never modifies, executes, or transmits your files.

#!/bin/bash
# Build MarkView, package it as a .app bundle, install to ~/Applications,
# register with LaunchServices, and set it as the default handler for .md/.markdown.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MarkView"
BUNDLE_ID="com.markview.app"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release --package-path "$PROJECT_DIR"
BIN_PATH="$(swift build -c release --package-path "$PROJECT_DIR" --show-bin-path)/$APP_NAME"

echo "==> Assembling app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE" || echo "   (codesign skipped/failed; app will still run locally)"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Registering with LaunchServices (force refresh)"
"$LSREGISTER" -f -R -trusted "$APP_BUNDLE"

echo "==> Setting default handler for .md / .markdown"
# Use Swift + LaunchServices to set default role handler for the markdown UTIs.
/usr/bin/swift - "$BUNDLE_ID" <<'SWIFT' || echo "   (default handler set skipped)"
import Foundation
import CoreServices
import UniformTypeIdentifiers

let bundleID = CommandLine.arguments[1] as CFString
// Static markdown UTIs plus the system's dynamic UTI for the .markdown extension
// (macOS assigns a dyn.* type when no app formally declares .markdown).
var utis = ["net.daringfireball.markdown", "public.markdown"]
if let dyn = UTType(filenameExtension: "markdown")?.identifier { utis.append(dyn) }
if let dynMd = UTType(filenameExtension: "md")?.identifier { utis.append(dynMd) }
for uti in Set(utis) {
    let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID)
    print("   \(uti): status \(status)")
}
SWIFT

echo "==> Refreshing this app's LaunchServices registration"
"$LSREGISTER" -f -R -trusted "$APP_BUNDLE"

echo "==> Done. Installed to $APP_BUNDLE"
echo "If Finder still shows a stale icon or handler, restart Finder manually or log out and back in."
echo ""
echo "If a specific .md file still opens with another app, it has a per-file"
echo "override. Clear it with: Finder > right-click the file > Get Info >"
echo "'Open with' > choose MarkView > 'Change All…'."

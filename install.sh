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

echo "==> Building Quick Look extension binary (swiftc, no Xcode required)"
QL_NAME="MarkViewQuickLook"
QL_BUILD_DIR="$PROJECT_DIR/.build/quicklook"
mkdir -p "$QL_BUILD_DIR"
# The extension reuses the app's parser/loader/renderer sources directly.
QL_SOURCES=(
    "$PROJECT_DIR/QuickLookExtension/PreviewViewController.swift"
    "$PROJECT_DIR/Sources/MarkView/MarkdownParser.swift"
    "$PROJECT_DIR/Sources/MarkView/DocumentLoader.swift"
    "$PROJECT_DIR/Sources/MarkView/BlockViews.swift"
    "$PROJECT_DIR/Sources/MarkView/QuickLookRendering.swift"
    "$PROJECT_DIR/Sources/MarkView/ReadingTypography.swift"
)
swiftc -O -parse-as-library -application-extension \
    -module-name "$QL_NAME" \
    -target "$(uname -m)-apple-macos13.0" \
    -framework Cocoa -framework Quartz \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -Xlinker -application_extension \
    -o "$QL_BUILD_DIR/$QL_NAME" \
    "${QL_SOURCES[@]}"

echo "==> Assembling app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Embedding Quick Look extension (.appex)"
APPEX="$APP_BUNDLE/Contents/PlugIns/$QL_NAME.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$QL_BUILD_DIR/$QL_NAME" "$APPEX/Contents/MacOS/$QL_NAME"
cp "$PROJECT_DIR/QuickLookExtension/Info.plist" "$APPEX/Contents/Info.plist"

echo "==> Ad-hoc code signing"
# Sign the appex with sandbox entitlements first (required for the QL host
# to accept the extension), then the outer app.
codesign --force --sign - \
    --entitlements "$PROJECT_DIR/QuickLookExtension/$QL_NAME.entitlements" \
    "$APPEX" || echo "   (appex codesign skipped/failed)"
codesign --force --sign - "$APP_BUNDLE" || echo "   (codesign skipped/failed; app will still run locally)"

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

echo "==> Registering Quick Look extension with PlugInKit"
pluginkit -a "$APPEX" || echo "   (pluginkit add failed; extension may register on first app launch)"
pluginkit -e use -i "$BUNDLE_ID.quicklook" || echo "   (pluginkit enable failed; enable in System Settings > Login Items & Extensions > Quick Look)"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "==> Done. Installed to $APP_BUNDLE"
echo "Quick Look: select a .md file in Finder and press Space to preview."
echo "If the preview doesn't use MarkView yet, check System Settings >"
echo "Login Items & Extensions > Quick Look and make sure MarkView is enabled."
echo "If Finder still shows a stale icon or handler, restart Finder manually or log out and back in."
echo ""
echo "If a specific .md file still opens with another app, it has a per-file"
echo "override. Clear it with: Finder > right-click the file > Get Info >"
echo "'Open with' > choose MarkView > 'Change All…'."

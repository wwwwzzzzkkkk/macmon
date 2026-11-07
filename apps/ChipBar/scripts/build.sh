#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release --arch arm64
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/chipbar-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ChipBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -X .build/arm64-apple-macosx/release/ChipBar "$APP/Contents/MacOS/ChipBar"
./scripts/icon.sh "$APP/Contents/Resources"
cp -X Assets/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
VERSION="$(python3 scripts/version.py show)"
python3 - "$APP" "$VERSION" <<'PYINFO'
import plistlib, sys
from pathlib import Path
app, version = sys.argv[1:]
metadata = {
    "CFBundleIdentifier": "local.chipbar.monitor",
    "CFBundleName": "ChipBar", "CFBundleDisplayName": "ChipBar",
    "CFBundleExecutable": "ChipBar", "CFBundlePackageType": "APPL",
    "CFBundleIconFile": "AppIcon.icns",
    "CFBundleShortVersionString": version, "CFBundleVersion": version,
    "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
    "NSHighResolutionCapable": True,
}
with (Path(app) / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump(metadata, stream)
PYINFO

# Install the real WidgetKit extension in the macOS application bundle.
# SwiftPM builds the menu-bar executable; the .appex has its own @main entry
# point, extension Info.plist, sandbox identity, signature and OS lifecycle.
# On CI an arm64 extension is cross-compiled using the same Xcode/macOS SDK.
WIDGET="$APP/Contents/PlugIns/ChipBarWidgets.appex"
mkdir -p "$WIDGET/Contents/MacOS" "$WIDGET/Contents/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -O -parse-as-library -application-extension \
  -sdk "$SDK_PATH" -target arm64-apple-macosx13.0 \
  Sources/ChipBarWidgets/ChipBarWidgets.swift \
  -o "$WIDGET/Contents/MacOS/ChipBarWidgets"
python3 - "$WIDGET" "$VERSION" "$STAGE" <<'PYWIDGET'
import plistlib
import sys
from pathlib import Path
widget, version, stage = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
info = {
    "CFBundleIdentifier": "local.chipbar.monitor.widgets",
    "CFBundleName": "ChipBar Widgets",
    "CFBundleDisplayName": "ChipBar Widgets",
    "CFBundleExecutable": "ChipBarWidgets",
    "CFBundlePackageType": "XPC!",
    "CFBundleShortVersionString": str(version),
    "CFBundleVersion": str(version),
    "LSMinimumSystemVersion": "13.0",
    "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
}
with (widget / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump(info, stream)
with (stage / "widget.entitlements").open("wb") as stream:
    plistlib.dump({"com.apple.security.app-sandbox": True}, stream)
PYWIDGET

# For a test build that should retain macOS TCC consent across updates,
# sign each build with the SAME real Keychain identity and preserve the bundle
# identifier. CI has no signing certificate and still uses ad-hoc (-) signing.
# A new ad-hoc build has a new code identity and can trigger OS consent again.
SIGN_IDENTITY="${CHIPBAR_CODESIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements "$STAGE/widget.entitlements" "$WIDGET"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
ditto --norsrc --noextattr "$APP" "$PWD/dist/ChipBar.app"
# File Provider may attach Finder metadata to the destination bundle in Documents.
# Remove only metadata prohibited by code signing, on our generated bundle.
xattr -dr com.apple.FinderInfo "$PWD/dist/ChipBar.app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$PWD/dist/ChipBar.app" 2>/dev/null || true
codesign --verify --deep --strict "$PWD/dist/ChipBar.app"
printf 'Built: %s\n' "$PWD/dist/ChipBar.app"

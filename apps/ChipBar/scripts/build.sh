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

# Build WidgetKit as an actual Xcode app-extension target, never a bare
# swiftc executable hand-wrapped as .appex. The latter can compile and sign
# successfully while chronod rejects or exits during widget registration.
# The real target embeds extension runtime metadata and XPC launch semantics.
WIDGET_PRODUCTS="$STAGE/widget-products"
xcodebuild \
  -project WidgetExtension/ChipBarWidgets.xcodeproj \
  -target ChipBarWidgets \
  -configuration Release \
  -sdk macosx \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  SYMROOT="$WIDGET_PRODUCTS" \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION="$VERSION" MARKETING_VERSION="$VERSION" \
  build
BUILT_WIDGET="$WIDGET_PRODUCTS/Release/ChipBarWidgets.appex"
test -x "$BUILT_WIDGET/Contents/MacOS/ChipBarWidgets" || {
  echo "ERROR: Xcode did not create ChipBarWidgets.appex" >&2
  exit 1
}
mkdir -p "$APP/Contents/PlugIns"
ditto --norsrc --noextattr "$BUILT_WIDGET" "$APP/Contents/PlugIns/ChipBarWidgets.appex"
WIDGET="$APP/Contents/PlugIns/ChipBarWidgets.appex"
python3 - "$STAGE" <<'PYWIDGET'
import plistlib
import sys
from pathlib import Path
with (Path(sys.argv[1]) / "widget.entitlements").open("wb") as stream:
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

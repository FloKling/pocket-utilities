#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release --arch arm64
APP="$(pwd)/dist/Pocket Utilities.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/arm64-apple-macosx/release/PocketUtilities "$APP/Contents/MacOS/PocketUtilities"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PocketUtilities</string>
<key>CFBundleIdentifier</key><string>local.PocketUtilities</string>
<key>CFBundleName</key><string>Pocket Utilities</string>
<key>CFBundleDisplayName</key><string>Pocket Utilities</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
SIGNING_IDENTITY="${POCKET_SIGNING_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    printf 'Warning: ad-hoc signing; updated builds may need Accessibility permission again.\n' >&2
fi
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --strict "$APP"
lipo -archs "$APP/Contents/MacOS/PocketUtilities"
printf '\nBuilt: %s\n' "$APP"

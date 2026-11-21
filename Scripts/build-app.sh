#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FinderCut"
BUNDLE_ID="com.wassime.FinderCut"
VERSION="1.0.0"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Prefer CommandLineTools if Xcode license hasn't been accepted yet.
if ! swift --version >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

echo "==> Building $APP_NAME (release)..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> Generating AppIcon.icns..."
swift "$ROOT_DIR/Scripts/generate-icon.swift" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> Code signing $APP_BUNDLE (ad-hoc)..."
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"

echo "==> Built successfully: $APP_BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    TARGET="/Applications/$APP_NAME.app"
    echo "==> Installing to $TARGET..."
    rm -rf "$TARGET"
    cp -R "$APP_BUNDLE" "$TARGET"
    echo "==> Installed: $TARGET"
fi

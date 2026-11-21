#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FinderCut"
VOLUME_NAME="FinderCut"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
FINAL_DMG="$BUILD_DIR/$APP_NAME.dmg"
RW_DMG="$BUILD_DIR/${APP_NAME}-temp.dmg"
STAGING_DIR="$(mktemp -d /tmp/findercut-dmg.XXXXXX)"
MOUNT_POINT=""

cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$STAGING_DIR" "$RW_DMG"
}
trap cleanup EXIT

if ! swift --version >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

# 1. Build fresh signed .app bundle
"$ROOT_DIR/Scripts/build-app.sh"

# 2. Prepare staging directory
echo "==> Preparing DMG contents..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$STAGING_DIR/.background"
swift "$ROOT_DIR/Scripts/generate-dmg-bg.swift" "$STAGING_DIR/.background/background.png"
cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"

# 3. Create writable DMG
rm -f "$RW_DMG" "$FINAL_DMG"
echo "==> Creating temporary read-write disk image..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    -size 40m \
    "$RW_DMG" >/dev/null

# 4. Mount and configure custom icon & Finder layout
echo "==> Mounting disk image to configure layout..."
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
MOUNT_POINT="$(echo "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    echo "Error: Failed to determine DMG mount point" >&2
    exit 1
fi

SETFILE_BIN=""
if [[ -x "/Library/Developer/CommandLineTools/usr/bin/SetFile" ]]; then
    SETFILE_BIN="/Library/Developer/CommandLineTools/usr/bin/SetFile"
elif command -v SetFile >/dev/null 2>&1; then
    SETFILE_BIN="$(command -v SetFile)"
fi

if [[ -n "$SETFILE_BIN" ]]; then
    "$SETFILE_BIN" -a C "$MOUNT_POINT" || true
    "$SETFILE_BIN" -a V "$MOUNT_POINT/.VolumeIcon.icns" || true
    "$SETFILE_BIN" -a V "$MOUNT_POINT/.background" || true
fi

# Apply Finder window layout (graceful fallback if Finder AppleScript is unavailable)
echo "==> Configuring Finder DMG window layout..."
osascript <<EOF 2>/dev/null || echo "Note: Skipped Finder visual layout customization (AppleScript not permitted)."
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {240, 180, 900, 580}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 104
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {185, 195}
        set position of item "Applications" of container window to {475, 195}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
sleep 1

echo "==> Detaching temporary disk image..."
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""

# 5. Compress into final read-only UDZO DMG
echo "==> Compressing final DMG..."
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG" >/dev/null

echo "==> Built installer DMG successfully: $FINAL_DMG"
ls -lh "$FINAL_DMG"

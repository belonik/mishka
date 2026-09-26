#!/bin/bash
#
# Builds Mishka.app — a self-contained macOS application bundle.
#
#   ./build.sh              release build (default)
#   ./build.sh debug        debug build
#   ./build.sh release run  build and launch
#
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
CONFIG="${1:-release}"
APP_NAME="Mishka"
BUNDLE_ID="app.mishka.notes"
VERSION="1.0"
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
# Keeps the Swift driver happy in sandboxed environments where the default
# Clang module cache lives outside the writable workspace.
MODULE_CACHE="${CLANG_MODULE_CACHE_PATH:-$ROOT/.dsh-modulecache}"

mkdir -p "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
# Keep SwiftPM's own caches beside the build instead of ~/Library, which is not
# always writable in sandboxed or CI environments.
export SWIFTPM_HOME="${SWIFTPM_HOME:-$ROOT/.build/swiftpm}"

echo "==> Building $APP_NAME ($CONFIG)"
swift build -c "$CONFIG" --disable-sandbox

BINARY="$BUILD_DIR/$CONFIG/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "error: expected binary at $BINARY" >&2
    exit 1
fi

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/MacOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
                <string>txt</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# --- App icon -------------------------------------------------------------
ICON_SOURCE="$CONTENTS/Resources/AppIcon.icns"
if [ ! -f "$ICON_SOURCE" ]; then
    echo "==> Rendering app icon"
    PNG="$BUILD_DIR/icon-1024.png"
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swift "$ROOT/Tools/make-icon.swift" "$PNG" >/dev/null

    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICON_SOURCE"
    rm -rf "$ICONSET"
fi

# --- Signature ------------------------------------------------------------
# Ad-hoc signing is enough for a locally built app and keeps macOS from
# re-prompting on every launch.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
    echo "warning: ad-hoc codesign failed; the app still runs locally"

echo "==> Done: $APP_DIR"

if [ "${2:-}" = "run" ]; then
    echo "==> Launching"
    open "$APP_DIR"
fi

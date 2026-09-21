#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DevCacheCleaner"
APP_DISPLAY_NAME="DevCache Cleaner"
APP_EXECUTABLE="DevCacheCleanerApp"
CLI_EXECUTABLE="devcache"
BUNDLE_ID="com.qiyue.DevCacheCleaner"
VERSION="${VERSION:-1.0.0}"
ICON_FILE="DevCacheCleaner.icns"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/release"
RESOURCE_DIR="$PROJECT_DIR/Sources/DevCacheApp/Resources"
PACKAGE_WORK_DIR="$BUILD_DIR/package-local"
PACKAGE_ROOT="$PACKAGE_WORK_DIR/root"
APP_BUNDLE="$PACKAGE_ROOT/Applications/$APP_NAME.app"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
PKG_PATH="${PKG_PATH:-$DIST_DIR/$APP_NAME.pkg}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_command swift
require_command codesign
require_command pkgbuild

echo "==> Building release binaries"
cd "$PROJECT_DIR"
swift build -c release

echo "==> Staging package root"
rm -rf "$PACKAGE_WORK_DIR"
mkdir -p \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources" \
  "$PACKAGE_ROOT/usr/local/bin" \
  "$DIST_DIR"

if [[ ! -x "$RELEASE_DIR/$APP_EXECUTABLE" ]]; then
  echo "error: missing app executable: $RELEASE_DIR/$APP_EXECUTABLE" >&2
  exit 1
fi

if [[ ! -x "$RELEASE_DIR/$CLI_EXECUTABLE" ]]; then
  echo "error: missing CLI executable: $RELEASE_DIR/$CLI_EXECUTABLE" >&2
  exit 1
fi

if [[ ! -f "$RESOURCE_DIR/$ICON_FILE" ]]; then
  echo "error: missing app icon: $RESOURCE_DIR/$ICON_FILE" >&2
  exit 1
fi

cp "$RELEASE_DIR/$APP_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
cp "$RELEASE_DIR/$CLI_EXECUTABLE" "$PACKAGE_ROOT/usr/local/bin/$CLI_EXECUTABLE"
cp "$RESOURCE_DIR/$ICON_FILE" "$APP_BUNDLE/Contents/Resources/$ICON_FILE"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE" "$PACKAGE_ROOT/usr/local/bin/$CLI_EXECUTABLE"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_DISPLAY_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$APP_EXECUTABLE</string>
	<key>CFBundleIconFile</key>
	<string>${ICON_FILE%.icns}</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_DISPLAY_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Signing app for local use"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Building installer package"
rm -f "$PKG_PATH"
pkgbuild \
  --root "$PACKAGE_ROOT" \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  --install-location / \
  "$PKG_PATH"

echo "==> Done"
echo "$PKG_PATH"

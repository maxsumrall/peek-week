#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Peek Week"
EXECUTABLE_NAME="PeekWeek"
BUNDLE_ID="dev.max.peekweek"
VERSION="${1:-0.1.0}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
ZIP_PATH="$BUILD_DIR/peek-week-macos.zip"
DMG_PATH="$BUILD_DIR/peek-week-macos.dmg"

SIGN_IDENTITY="${PEEK_WEEK_SIGN_IDENTITY:-Developer ID Application: Max Sumrall (PNZVBQP48R)}"
NOTARY_PROFILE="${PEEK_WEEK_NOTARY_PROFILE:-peek-week}"

mkdir -p "$BUILD_DIR"
rm -rf "$APP_DIR" "$ZIP_PATH" "$DMG_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swiftc \
  -O \
  -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -framework ServiceManagement \
  "$ROOT_DIR/Sources/PeekWeek/main.swift" \
  -o "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/Sources/PeekWeek/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# --- Sign ---
printf '==> Signing...\n'
codesign --force --deep --timestamp --options runtime \
  --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --verbose "$APP_DIR"

# --- Notarize ---
printf '==> Notarizing (this takes 1-5 minutes)...\n'
NOTARIZE_ZIP="$BUILD_DIR/_notarize.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
rm -f "$NOTARIZE_ZIP"

# --- Staple ---
printf '==> Stapling...\n'
xcrun stapler staple "$APP_DIR"

# --- Package ---
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if command -v create-dmg &>/dev/null; then
  create-dmg \
    --volname "Peek Week" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "Peek Week.app" 150 190 \
    --app-drop-link 450 190 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_DIR"
  printf 'Built dmg: %s\n' "$DMG_PATH"
fi

printf 'Built app: %s\n' "$APP_DIR"
printf 'Built zip: %s\n' "$ZIP_PATH"
printf '==> Done! App is signed, notarized, and stapled.\n'

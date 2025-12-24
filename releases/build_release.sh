#!/bin/bash
set -e

# OMFK Release Builder
# Creates .app bundle and .dmg for distribution

APP_NAME="OMFK"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Read version from VERSION file or use argument
if [ -n "$1" ]; then
    VERSION="$1"
else
    VERSION=$(cat "$PROJECT_DIR/VERSION" | tr -d '[:space:]')
fi

BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$SCRIPT_DIR/$APP_NAME-$VERSION.dmg"

echo "🚀 Building $APP_NAME v$VERSION"
echo "================================"

# Update VERSION file
echo "$VERSION" > "$PROJECT_DIR/VERSION"

# Update fallback version in SettingsView.swift
sed -i '' "s/return \"[0-9]*\.[0-9]*\.[0-9]*\"/return \"$VERSION\"/" "$PROJECT_DIR/OMFK/Sources/UI/SettingsView.swift"

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release binary
echo "📦 Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

BINARY_PATH="$PROJECT_DIR/.build/release/OMFK"
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Binary not found at $BINARY_PATH"
    exit 1
fi

# Create .app bundle structure
echo "📁 Creating app bundle..."
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"

# Copy resource bundle (required by Swift Package Manager)
# Bundle.main.bundleURL points to OMFK.app/, so bundle goes there
BUNDLE_PATH="$PROJECT_DIR/.build/release/OMFK_OMFK.bundle"
if [ -d "$BUNDLE_PATH" ]; then
    cp -r "$BUNDLE_PATH" "$APP_PATH/"
fi

# Copy icon
ICON_SRC="$PROJECT_DIR/OMFK/Assets.xcassets/AppIcon.appiconset/icon_512.png"
if [ -f "$ICON_SRC" ]; then
    # Convert PNG to ICNS
    mkdir -p "$BUILD_DIR/icon.iconset"
    sips -z 16 16 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_512x512.png" >/dev/null
    cp "$PROJECT_DIR/OMFK/Assets.xcassets/AppIcon.appiconset/icon_1024.png" "$BUILD_DIR/icon.iconset/icon_512x512@2x.png"
    iconutil -c icns "$BUILD_DIR/icon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
    rm -rf "$BUILD_DIR/icon.iconset"
fi

# Create Info.plist
cat > "$APP_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.omfk.OMFK</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

echo "✅ App bundle created: $APP_PATH"

# Create DMG
echo "💿 Creating DMG..."
rm -f "$DMG_PATH"

# Create temp DMG folder (clean first)
DMG_TEMP="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -r "$APP_PATH" "$DMG_TEMP/"

# Create symlink to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH" >/dev/null

rm -rf "$DMG_TEMP"

echo "✅ DMG created: $DMG_PATH"
echo ""
echo "================================"
echo "📦 Release artifacts:"
echo "   App: $APP_PATH"
echo "   DMG: $DMG_PATH"
echo ""
echo "To install: Open DMG and drag $APP_NAME to Applications"

# Publish to GitHub releases repo if --publish flag is passed
if [ "$2" = "--publish" ] || [ "$1" = "--publish" ]; then
    echo ""
    echo "🚀 Publishing to GitHub..."
    
    RELEASES_REPO="chernistry/omfk"
    TAG="v$VERSION"
    
    # Check if release already exists
    if gh release view "$TAG" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
        echo "⚠️  Release $TAG already exists. Deleting and recreating..."
        gh release delete "$TAG" --repo "$RELEASES_REPO" --yes
    fi
    
    # Create release
    gh release create "$TAG" "$DMG_PATH" \
        --repo "$RELEASES_REPO" \
        --title "OMFK $TAG" \
        --notes "## OMFK $TAG

Download the DMG and drag OMFK to Applications.

**Requirements:** macOS 13.0+

**Feedback:** [GitHub Issues](https://github.com/chernistry/omfk/issues)"
    
    echo "✅ Published to https://github.com/$RELEASES_REPO/releases/tag/$TAG"
fi

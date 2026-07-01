#!/bin/bash
set -e

# Configuration
APP_NAME="Nemo Voice Typing"
BUNDLE_ID="com.nemo.voicetyping"
VERSION="1.0"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="NemoVoiceTyping-$VERSION.dmg"

echo "Building Nemo Voice Typing executable..."
swift build -c release

echo "Creating App Bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Copying binary..."
cp "$BUILD_DIR/NemoVoiceTyping" "$APP_BUNDLE/Contents/MacOS/NemoVoiceTyping"
chmod +x "$APP_BUNDLE/Contents/MacOS/NemoVoiceTyping"

echo "Creating Info.plist..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NemoVoiceTyping</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Nemo Voice Typing needs access to the microphone to capture and recognize dictation.</string>
</dict>
</plist>
EOF

echo "Creating Entitlements..."
cat <<EOF > entitlements.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
EOF

# Code signing (Using Ad-hoc signing by default for local testing)
# To sign with a Developer ID, run: SIGN_IDENTITY="Developer ID Application: Name" ./create_dmg.sh
SIGN_IDENTITY=${SIGN_IDENTITY:-"-"}

echo "Signing application bundle with identity: '$SIGN_IDENTITY'..."
codesign --force --options runtime --entitlements entitlements.plist --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/NemoVoiceTyping"
codesign --force --options runtime --entitlements entitlements.plist --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

rm -f entitlements.plist

echo "Packaging into DMG..."
rm -f "$DMG_NAME"
temp_dmg="temp.dmg"
rm -f "$temp_dmg"

# Create a temporary read-write DMG
hdiutil create -srcfolder "$APP_BUNDLE" -volname "$APP_NAME" -fs HFS+ -fsopt -showresizes -ov -format UDRW "$temp_dmg"

# Convert to read-only compressed DMG
echo "Compressing DMG..."
hdiutil convert "$temp_dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"
rm -f "$temp_dmg"

# Sign the DMG itself
echo "Signing DMG..."
codesign --force --sign "$SIGN_IDENTITY" "$DMG_NAME"

echo "==========================================="
echo "Successfully created and signed: $DMG_NAME"
echo "To run the app:"
echo "1. Double click $DMG_NAME to mount it."
echo "2. Drag $APP_BUNDLE to your Applications folder."
echo "3. Double click the app in Applications to launch!"
echo "==========================================="

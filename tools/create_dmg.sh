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
    <string>14.0</string>
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
</dict>
</plist>
EOF

# Code signing.
# Accessibility permissions are tied to the app's code-signing identity. Ad-hoc
# signatures are fine for a one-off smoke test, but rebuilt ad-hoc apps can lose
# their trusted Accessibility grant and appear to ask for permission repeatedly.
# Use a stable Developer ID or local code-signing certificate for normal testing:
#   SIGN_IDENTITY="Developer ID Application: Name" ./tools/create_dmg.sh
SIGN_IDENTITY=${SIGN_IDENTITY:-""}

if [ -z "$SIGN_IDENTITY" ]; then
    VALID_IDENTITIES=$(security find-identity -v -p codesigning)
    if echo "$VALID_IDENTITIES" | grep -q "Nemo Voice Typing Local Signing"; then
        SIGN_IDENTITY="Nemo Voice Typing Local Signing"
        echo "Using local signing identity: '$SIGN_IDENTITY'"
    elif FIRST_CODESIGN_IDENTITY=$(echo "$VALID_IDENTITIES" | sed -n 's/^[[:space:]]*[0-9]*) [A-Fa-f0-9]\{40,\} "\(.*\)"/\1/p' | head -n 1); [ -n "$FIRST_CODESIGN_IDENTITY" ]; then
        SIGN_IDENTITY="$FIRST_CODESIGN_IDENTITY"
        echo "Using first available signing identity: '$SIGN_IDENTITY'"
    else
        SIGN_IDENTITY="-"
        echo "WARNING: using ad-hoc signing."
        echo "WARNING: macOS Accessibility permissions may reset after each rebuild."
        echo "WARNING: create or pass a stable signing identity with SIGN_IDENTITY to avoid repeated permission prompts."
    fi
fi

echo "Signing application bundle with identity: '$SIGN_IDENTITY'..."
codesign --force --options runtime --entitlements entitlements.plist --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/NemoVoiceTyping"
codesign --force --options runtime --entitlements entitlements.plist --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
if ! codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"; then
    echo "ERROR: code signature verification failed for $APP_BUNDLE" >&2
    echo "ERROR: install a valid code-signing certificate or run with SIGN_IDENTITY='-' for ad-hoc local testing." >&2
    exit 1
fi

rm -f entitlements.plist

echo "Packaging into DMG..."
rm -f "$DMG_NAME"
temp_dmg="temp.dmg"
rm -f "$temp_dmg"

# Create a temporary read-write DMG
hdiutil create -srcfolder "$APP_BUNDLE" -volname "$APP_NAME" -fs HFS+ -ov -format UDRW "$temp_dmg"

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

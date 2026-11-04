#!/bin/bash
# Bouwt "BCF Bridge.app" in de map build/.
# Met "install" erachter wordt de app ook naar /Applications gekopieerd en gestart:
#   scripts/build-app.sh install
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
APP="build/BCF Bridge.app"

echo "BCF Bridge $VERSION bouwen..."
swift build -c release --product BCFBridgeApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BCFBridgeApp "$APP/Contents/MacOS/BCF Bridge"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>BCF Bridge</string>
    <key>CFBundleIdentifier</key><string>nl.tonvanderkolk.bcf-bridge</string>
    <key>CFBundleName</key><string>BCF Bridge</string>
    <key>CFBundleDisplayName</key><string>BCF Bridge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc ondertekenen, nodig voor Apple Silicon en voor starten bij inloggen
codesign --force --sign - "$APP"
echo "Klaar: $APP"

if [[ "${1:-}" == "install" ]]; then
    # Draaiende versie netjes afsluiten (zodat faders worden losgelaten)
    if pgrep -x "BCF Bridge" >/dev/null; then
        osascript -e 'quit app "BCF Bridge"' || true
        sleep 2
    fi
    rm -rf "/Applications/BCF Bridge.app"
    cp -R "$APP" /Applications/
    open "/Applications/BCF Bridge.app"
    echo "Geïnstalleerd in /Applications en gestart. Kijk rechtsboven in de menubalk."
fi

#!/bin/bash
# Builds build/译喵.app from the Swift package.
#   Scripts/build.sh          build only
#   Scripts/build.sh --run    build, then (re)launch
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/译喵.app"
EXECUTABLE="Yimiao"
BUNDLE_ID="io.github.hannah-bbbb.yimiao"

swift build -c release
BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The icon is the cat himself, drawn by the same renderer as the live pet.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BINARY" --iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# macOS remembers the Accessibility grant by the app's "designated requirement". For an ad-hoc
# signature that is normally the hash of this exact binary, so every rebuild would look like a
# different app and silently lose the grant. Naming the bundle identifier as the requirement
# keeps the grant across rebuilds. The price: the grant then follows the identifier rather than
# one binary. To bind it to a certificate instead, set CODESIGN_IDENTITY or keep a code-signing
# identity in the keychain.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)".*/\1/p' | head -n 1)}"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
fi

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--run" ]]; then
    pkill -x "$EXECUTABLE" 2>/dev/null && sleep 0.5 || true
    open "$APP"
fi

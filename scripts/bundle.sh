#!/bin/bash
# Builds build/Kursor.app. With --install: replaces ~/Applications/Kursor.app and relaunches it.
#
# Signing: uses the "Kursor Local Signing" identity when it exists (see make-cert.sh), so
# macOS keeps Accessibility/Input Monitoring grants across rebuilds. Without it the app
# is ad-hoc signed and the permissions must be re-granted after every build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${KURSOR_SIGN_IDENTITY:-Kursor Local Signing}"
APP="build/Kursor.app"

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Kursor" "$APP/Contents/MacOS/Kursor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    SIGN="$IDENTITY"
else
    echo "warning: identity \"$IDENTITY\" not found, ad-hoc signing (permissions reset on every build)" >&2
    SIGN="-"
fi
codesign --force --sign "$SIGN" --identifier com.kaio.kursor "$APP"
codesign --verify "$APP"
echo "built $APP (signed: $SIGN)"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'tell application id "com.kaio.kursor" to quit' 2>/dev/null || true
    sleep 1
    pkill -x Kursor 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Kursor.app"
    ditto "$APP" "$HOME/Applications/Kursor.app"
    open "$HOME/Applications/Kursor.app"
    echo "installed to ~/Applications/Kursor.app"
fi

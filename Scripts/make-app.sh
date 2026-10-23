#!/bin/bash
# Builds the release executable and assembles a proper .app bundle.
#
# A bare SPM executable works, but a real .app bundle is strongly recommended:
# the macOS Accessibility prompt shows the bundle's name and icon, and the
# permission grant is tied to the bundle identity rather than a build path that
# changes on every rebuild.
#
# Usage:  ./Scripts/make-app.sh
# Output: ./build/WinMan.app

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="WinMan"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> Building release binary…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [ ! -x "$BIN_PATH" ]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Support/Info.plist" "$APP_DIR/Contents/Info.plist"

# Sign with a stable self-signed identity so the signature (and therefore the
# Accessibility/TCC grant) survives rebuilds. Falls back to ad-hoc if the cert
# is missing — but note ad-hoc signatures change every rebuild, which revokes a
# previously-granted Accessibility permission.
SIGN_ID="WindowManager Local Signing"
if security find-identity -v -p codesigning | grep -qF "$SIGN_ID"; then
    echo "==> Codesigning with stable identity: $SIGN_ID"
    codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
else
    echo "==> Codesigning (ad-hoc) — stable identity '$SIGN_ID' not found."
    echo "    Run Scripts/setup-signing.sh to create it (avoids re-granting"
    echo "    Accessibility permission after every rebuild)."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Done: $APP_DIR"

# If the app is installed in /Applications (so it can launch at login),
# refresh that copy and restart it from there. Killing every instance first
# avoids ending up with the installed app and a build copy both running —
# they would fight over the same global shortcuts.
INSTALL_DIR="/Applications/$APP_NAME.app"
if [ -d "$INSTALL_DIR" ]; then
    echo "==> Updating $INSTALL_DIR and restarting from there…"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR"
    ditto "$APP_DIR" "$INSTALL_DIR"
    open "$INSTALL_DIR"
    echo "==> Installed and launched: $INSTALL_DIR"
fi

echo
echo "Next steps:"
echo "  1. Open it:   open '$APP_DIR'"
echo "  2. Grant Accessibility access when prompted, or via"
echo "     System Settings → Privacy & Security → Accessibility."
echo "  3. Launch at login: Settings → System in the app (macOS may ask you"
echo "     to approve it under System Settings → General → Login Items)."

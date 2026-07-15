#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '%s\n' "$*"
}

abs_from_repo() {
    local path="$1"
    case "$path" in
        /*) printf '%s\n' "$path" ;;
        *) printf '%s\n' "$REPO_ROOT/$path" ;;
    esac
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

CONFIG="${CONFIG:-macos-arm64-clang}"
APP_NAME="${APP_NAME:-PoseidonGameDemo}"
DEFAULT_GAME_DATA="../Arma Cold War Assault Demo"

GAME_DATA="$(abs_from_repo "${GAME_DATA:-$DEFAULT_GAME_DATA}")"
DIST_DIR="$(abs_from_repo "${DIST_DIR:-dist/$CONFIG}")"

ENGINE_SOURCE="$DIST_DIR/PoseidonGameDemo"
PACKAGE_DIR="$DIST_DIR/package"
DMG_ROOT="$PACKAGE_DIR/dmg-root"
APP_BUNDLE="$DMG_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_GAME_DATA="$RESOURCES_DIR/GameData"
ENGINE_DEST="$MACOS_DIR/$APP_NAME.bin"
LAUNCHER="$MACOS_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/$APP_NAME-local-demo.dmg"

[[ "$PACKAGE_DIR" != "/" && -n "$PACKAGE_DIR" ]] || fail "unsafe package directory: $PACKAGE_DIR"
[[ "$DMG_PATH" == "$DIST_DIR"/* ]] || fail "unsafe DMG path: $DMG_PATH"

command -v ditto >/dev/null 2>&1 || fail "ditto is required on macOS"
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is required on macOS"

[[ -x "$ENGINE_SOURCE" ]] || fail "native binary not found or not executable: $ENGINE_SOURCE"
[[ -d "$GAME_DATA" ]] || fail "demo game data directory not found: $GAME_DATA"

for required_dir in AddOns BIN DTA Missions fonts; do
    [[ -d "$GAME_DATA/$required_dir" ]] || fail "demo game data is missing $required_dir/: $GAME_DATA"
done

log "Packaging $APP_NAME from:"
log "  binary:    $ENGINE_SOURCE"
log "  game data: $GAME_DATA"
log "  output:    $DMG_PATH"

rm -rf "$PACKAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_ROOT"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>community.poseidon.$APP_NAME.local</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1-local</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

ditto "$ENGINE_SOURCE" "$ENGINE_DEST"
chmod 755 "$ENGINE_DEST"

cat > "$LAUNCHER" <<'LAUNCHER'
#!/bin/sh
set -eu

APP_CONTENTS="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENGINE="$APP_CONTENTS/MacOS/PoseidonGameDemo.bin"
GAME_DATA="$APP_CONTENTS/Resources/GameData"

if [ ! -x "$ENGINE" ]; then
    printf 'error: embedded engine binary is missing or not executable: %s\n' "$ENGINE" >&2
    exit 127
fi

if [ ! -d "$GAME_DATA/DTA" ]; then
    printf 'error: embedded game data is missing or incomplete: %s\n' "$GAME_DATA" >&2
    exit 2
fi

exec "$ENGINE" \
    -C "$GAME_DATA" \
    --window \
    --no-splash \
    "$@"
LAUNCHER
chmod 755 "$LAUNCHER"

log "Copying demo game data into app bundle..."
ditto "$GAME_DATA" "$APP_GAME_DATA"

ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME Local Demo" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

log "Created DMG:"
du -sh "$DMG_PATH"

# Local Demo DMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an unsigned local/test DMG containing `PoseidonGameDemo.app`, the native Apple Silicon game binary, and the demo game data.

**Architecture:** Add one focused macOS packaging script under `package/macos/`. The script validates existing build output and demo data, creates a self-contained `.app` bundle in ignored `dist/`, copies demo data into `Contents/Resources/GameData`, writes a launcher script that passes `-C` to the engine, and creates a compressed DMG with `hdiutil`.

**Tech Stack:** POSIX shell, macOS `ditto`, macOS `hdiutil`, existing `dist/macos-arm64-clang/PoseidonGameDemo` binary.

---

## File Structure

- Create `package/macos/make-local-demo-dmg.sh`: owns all local DMG packaging behavior.
- Generated only, not committed: `dist/macos-arm64-clang/package/PoseidonGameDemo.app`.
- Generated only, not committed: `dist/macos-arm64-clang/PoseidonGameDemo-local-demo.dmg`.

No C++ engine changes are needed because the binary already supports `-C <game-data-dir>`.

### Task 1: Add The Packaging Script

**Files:**
- Create: `package/macos/make-local-demo-dmg.sh`

- [ ] **Step 1: Verify the script does not exist yet**

Run:

```bash
test ! -e package/macos/make-local-demo-dmg.sh
```

Expected: command exits `0`. If it exits non-zero, inspect the existing file before continuing and adapt this task instead of overwriting it.

- [ ] **Step 2: Create the packaging script**

Create `package/macos/make-local-demo-dmg.sh` with this exact content:

```bash
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
```

- [ ] **Step 3: Mark the script executable**

Run:

```bash
chmod 755 package/macos/make-local-demo-dmg.sh
```

Expected: command exits `0`.

- [ ] **Step 4: Verify shell syntax**

Run:

```bash
bash -n package/macos/make-local-demo-dmg.sh
```

Expected: command exits `0` with no output.

- [ ] **Step 5: Commit the script**

Run:

```bash
git add package/macos/make-local-demo-dmg.sh
git commit -m "build(macos): add local demo DMG package script"
```

Expected: commit succeeds and includes only `package/macos/make-local-demo-dmg.sh`.

### Task 2: Build And Verify The Local DMG

**Files:**
- Read: `package/macos/make-local-demo-dmg.sh`
- Generate: `dist/macos-arm64-clang/package/PoseidonGameDemo.app`
- Generate: `dist/macos-arm64-clang/PoseidonGameDemo-local-demo.dmg`

- [ ] **Step 1: Confirm the native binary exists**

Run:

```bash
file dist/macos-arm64-clang/PoseidonGameDemo
```

Expected output includes:

```text
Mach-O 64-bit executable arm64
```

- [ ] **Step 2: Run the packaging script**

Run:

```bash
package/macos/make-local-demo-dmg.sh
```

Expected: command exits `0`, copies the demo data, and prints the final DMG size.

- [ ] **Step 3: Verify generated app structure**

Run:

```bash
test -x dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo
test -x dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo.bin
test -d dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app/Contents/Resources/GameData/DTA
test -L dist/macos-arm64-clang/package/dmg-root/Applications
```

Expected: all commands exit `0`.

- [ ] **Step 4: Verify the DMG metadata**

Run:

```bash
hdiutil imageinfo dist/macos-arm64-clang/PoseidonGameDemo-local-demo.dmg
```

Expected output includes:

```text
Format: UDZO
```

- [ ] **Step 5: Inspect the generated launcher**

Run:

```bash
sed -n '1,80p' dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo
```

Expected output shows the launcher computing `APP_CONTENTS`, setting `GAME_DATA` under `Contents/Resources/GameData`, and executing `PoseidonGameDemo.bin` with `-C "$GAME_DATA" --window --no-splash`.

## Self-Review

- Spec coverage: Task 1 implements the `.app` layout, launcher, bundled game data copy, `Applications` symlink, local-only unsigned scope, and DMG creation. Task 2 verifies the generated app and DMG.
- Completeness scan: no deferred implementation steps.
- Type consistency: file and directory names match the design spec and script variables.

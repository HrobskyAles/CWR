# Local Demo DMG Packaging Design

**Date:** 2026-07-15

**Repository:** `/Users/ali/Developer/OPF_Remaster/CWR`

**Demo data:** `/Users/ali/Developer/OPF_Remaster/Arma Cold War Assault Demo`

## Objective

Create an unsigned local/test macOS DMG that can be copied to a second Mac and
run without manually placing game data beside the executable. The DMG should
contain a macOS `.app` bundle with the native Apple Silicon
`PoseidonGameDemo` binary and the demo game data embedded inside the bundle.

## Decision

Package a self-contained `PoseidonGameDemo.app` and wrap it in a compressed
DMG created with `hdiutil`.

The `.app` bundle should contain:

- `Contents/MacOS/PoseidonGameDemo`: a launcher script.
- `Contents/MacOS/PoseidonGameDemo.bin`: the native engine executable.
- `Contents/Resources/GameData/`: copied demo game data.
- `Contents/Info.plist`: minimal app metadata.

The launcher script should resolve its own bundle location and execute:

```sh
PoseidonGameDemo.bin -C "$APP_CONTENTS/Resources/GameData" --window --no-splash
```

This avoids engine changes because `PoseidonGameDemo` already supports
`-C <dir>` for the working game-data directory.

## Scope

This is a local test artifact, not a public installer.

Included:

- Unsigned `.app` bundle.
- Bundled demo game data.
- Compressed DMG output under `dist/macos-arm64-clang/`.
- A top-level `Applications` symlink in the DMG for normal drag-copy testing.
- Scripted rebuild of the package from existing build outputs.
- Basic validation that the DMG exists and contains the expected app bundle.

Excluded:

- Developer ID signing.
- Hardened runtime.
- Notarization.
- Universal or Intel macOS binaries.
- App Store packaging.
- Custom DMG artwork or Finder window layout.
- Any claim that the bundled game data is approved for public redistribution.

## Repository Evidence

- `CWR/docs/macos-build-and-run.md` documents the native Apple Silicon
  `PoseidonGameDemo` build and runtime command.
- `CWR/dist/macos-arm64-clang/PoseidonGameDemo` currently exists as a
  `Mach-O 64-bit executable arm64`.
- `otool -L` on the current binary shows system frameworks and system
  libraries only, so there is no immediate third-party dylib bundling step.
- The demo data directory is about 194 MB and contains expected game data
  folders such as `AddOns`, `BIN`, `DTA`, `Missions`, `MPMissions`, `Music`,
  `fonts`, and `Campaigns`.
- `GameBase::ParseCommandLine` applies `AppConfig::GetWorkingDirectory()` and
  calls `chdir()` on non-Windows platforms, so `-C` is the correct packaging
  boundary.

## Packaging Script

Add `package/macos/make-local-demo-dmg.sh`.

The script should run from the repository root and support these variables:

- `CONFIG`: build/preset name, default `macos-arm64-clang`.
- `APP_NAME`: default `PoseidonGameDemo`.
- `GAME_DATA`: default `../Arma Cold War Assault Demo`.
- `DIST_DIR`: default `dist/$CONFIG`.

The script should:

1. Resolve the repository root.
2. Check that `dist/$CONFIG/PoseidonGameDemo` exists and is executable.
3. Check that `GAME_DATA` exists and contains key data directories.
4. Recreate a staging directory under `dist/$CONFIG/package/`.
5. Create the `.app` directory structure.
6. Write `Contents/Info.plist`.
7. Copy the engine binary as `Contents/MacOS/PoseidonGameDemo.bin`.
8. Write the launcher script as `Contents/MacOS/PoseidonGameDemo`.
9. Copy the demo data to `Contents/Resources/GameData`.
10. Add an `Applications` symlink beside the `.app` in the DMG source folder.
11. Create `dist/$CONFIG/PoseidonGameDemo-local-demo.dmg` with `hdiutil`.
12. Print the final DMG path and size.

The script may remove and recreate only its own generated staging directory and
DMG path. It must not delete build outputs, source files, the original demo
data, or unrelated files in `dist/`.

## Runtime Behavior

Double-clicking the app should start the launcher script through LaunchServices.
The launcher should compute:

```sh
APP_CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
GAME_DATA="$APP_CONTENTS/Resources/GameData"
```

Then it should `exec` the native binary with the bundled data path:

```sh
exec "$APP_CONTENTS/MacOS/PoseidonGameDemo.bin" \
  -C "$GAME_DATA" \
  --window \
  --no-splash
```

The app should not rely on the user's current working directory, the source
checkout, or the original demo data path after packaging.

## Error Handling

The packaging script should fail early with clear messages when:

- the native binary has not been built;
- the demo data directory is missing;
- required game-data folders are missing;
- `hdiutil` is unavailable;
- DMG creation fails.

The launcher should fail through the process exit code if the embedded binary
or embedded game data cannot be found. It does not need a graphical error
dialog for this local test package.

## Verification

Required packaging checks:

```sh
cd /Users/ali/Developer/OPF_Remaster/CWR
package/macos/make-local-demo-dmg.sh
hdiutil imageinfo dist/macos-arm64-clang/PoseidonGameDemo-local-demo.dmg
```

Required app structure checks:

```sh
test -x dist/macos-arm64-clang/package/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo
test -x dist/macos-arm64-clang/package/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo.bin
test -d dist/macos-arm64-clang/package/PoseidonGameDemo.app/Contents/Resources/GameData/DTA
```

Optional smoke check:

```sh
dist/macos-arm64-clang/package/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo.bin \
  -C dist/macos-arm64-clang/package/PoseidonGameDemo.app/Contents/Resources/GameData \
  --check \
  --window \
  --no-sound \
  --no-splash \
  --no-menu-scene
```

Success for this design means the DMG is created, can be copied to another
Apple Silicon Mac, mounted there, and exposes an app that does not require
manual data placement.

## Second-Mac Notes

Because the app and DMG are unsigned and not notarized, macOS Gatekeeper may
block the first launch on the second Mac. For local testing, expected recovery
options are:

- right-click the app and choose Open;
- or remove quarantine from the copied app with
  `xattr -dr com.apple.quarantine PoseidonGameDemo.app`.

Copy the app out of the mounted DMG before launching, either to `/Applications`
or to a local test folder. The package is meant to be self-contained after that
copy; it should not depend on the mounted DMG or on the source checkout.

If the second Mac is Intel-only, this package will not run because the current
native build is Apple Silicon arm64 only.

## Follow-Up

If the local DMG proves useful, a separate public-distribution design should
cover signing, hardened runtime, notarization, icon generation, license review,
and whether demo data may be redistributed outside a private test flow.

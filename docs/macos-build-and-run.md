# macOS Build And Run Guide

This guide builds and runs the native Apple Silicon `PoseidonGameDemo` target
from Terminal. The macOS preset currently targets arm64 only.

## Requirements

- macOS on Apple Silicon.
- Xcode Command Line Tools.
- CMake, Ninja, and ccache.
- A bootstrapped vcpkg checkout.
- Demo or full game data. The source tree does not include game data.

For the local workspace used during the port, the paths are:

```sh
REPO="<folder-to-game-data>/CWR"
VCPKG_ROOT="<folder-to-game-data>/vcpkg"
GAME_DATA="<folder-to-game-data>/Arma Cold War Assault Demo"
```

Example:
```sh
REPO="/Users/ali/Developer/OPF_Remaster/CWR"
VCPKG_ROOT="/Users/ali/Developer/OPF_Remaster/vcpkg"
GAME_DATA="/Users/ali/Developer/OPF_Remaster/Arma Cold War Assault Demo"
```

If your checkout is somewhere else, change those paths before running the
commands below.

## Configure

```sh
cd "$REPO"
export VCPKG_ROOT

cmake --preset macos-arm64-clang
```

The first configure can take a while because vcpkg restores or builds the C++
dependencies for the `arm64-osx` triplet.

## Build

Build the demo game client:

```sh
cmake --build build/macos-arm64-clang --target PoseidonGameDemo
```

The executable is written to:

```text
build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo
```

CMake also copies the runtime binary to:

```text
dist/macos-arm64-clang/PoseidonGameDemo
```

To confirm it is a native arm64 macOS executable:

```sh
file build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo
```

Expected output includes:

```text
Mach-O 64-bit executable arm64
```

## Smoke Test

Use `--check` to initialize the game and exit. This is the fastest way to verify
that the binary can find the game data and bring up the engine.

```sh
GAME_EXE="$REPO/build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo"

"$GAME_EXE" \
  -C "$GAME_DATA" \
  --check \
  --window \
  --no-sound \
  --no-splash \
  --no-menu-scene
```

Exit code `0` means the startup smoke test passed. A warning about unsupported
legacy OpenGL features can appear on macOS; it is not fatal if the process exits
successfully.

## Run The Demo

Run from anywhere by passing the game-data directory with `-C`:

```sh
GAME_EXE="$REPO/build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo"

"$GAME_EXE" \
  -C "$GAME_DATA" \
  --window \
  --no-splash
```

Alternatively, run from inside the game-data directory:

```sh
cd "$GAME_DATA"
"$REPO/build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo" --window --no-splash
```

Useful run flags:

```text
-C, --work-dir <dir>     Game data directory with DTA/, Worlds/, etc.
--window                 Start windowed instead of fullscreen.
--width <pixels>         Window width.
--height <pixels>        Window height.
--no-splash              Skip splash screens.
--no-menu-scene          Skip the 3D menu background scene.
--no-sound               Disable sound.
--check                  Initialize subsystems, then exit.
```

For the full CLI list:

```sh
"$GAME_EXE" --help-full
```

## Create A Local Demo DMG

After building `PoseidonGameDemo`, you can create an unsigned local/test DMG
that contains a self-contained `PoseidonGameDemo.app` bundle. The app bundle
includes the native Apple Silicon binary and a copy of the demo game data under
`Contents/Resources/GameData`.

The packaging script reads the runtime binary from:

```text
dist/macos-arm64-clang/PoseidonGameDemo
```

If you followed the build steps above, CMake should already have copied the
binary there. Confirm it is present and native arm64:

```sh
file dist/macos-arm64-clang/PoseidonGameDemo
```

Expected output includes:

```text
Mach-O 64-bit executable arm64
```

Create the DMG:

```sh
cd "$REPO"
export GAME_DATA
package/macos/make-local-demo-dmg.sh
```

If your game data is not in the `GAME_DATA` variable, pass it inline:

```sh
GAME_DATA="/path/to/Arma Cold War Assault Demo" \
  package/macos/make-local-demo-dmg.sh
```

The script validates that `ditto`, `hdiutil`, the native binary, and the expected
demo data directories are available. It then creates:

```text
dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app
dist/macos-arm64-clang/PoseidonGameDemo-local-demo.dmg
```

Inside the app bundle, `Contents/MacOS/PoseidonGameDemo` is a launcher script
that runs `PoseidonGameDemo.bin` with:

```text
-C Contents/Resources/GameData --window --no-splash
```

Verify the generated app and DMG:

```sh
test -x dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo
test -x dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app/Contents/MacOS/PoseidonGameDemo.bin
test -d dist/macos-arm64-clang/package/dmg-root/PoseidonGameDemo.app/Contents/Resources/GameData/DTA
test -L dist/macos-arm64-clang/package/dmg-root/Applications
hdiutil imageinfo dist/macos-arm64-clang/PoseidonGameDemo-local-demo.dmg
```

`hdiutil imageinfo` should report `Format: UDZO`.

The generated DMG is unsigned and not notarized. It is meant for local testing,
copying to another Mac, or demo validation. macOS Gatekeeper may warn when the
app is opened; copy the app out of the mounted DMG before launching it. Do not
redistribute a DMG containing bundled game data unless the relevant asset license
allows it.

## Run Foundation Tests

The macOS port was verified with the Foundation unit test suite:

```sh
ctest \
  --test-dir build/macos-arm64-clang \
  -R PoseidonFoundationTests \
  --output-on-failure
```

## Common Problems

If CMake cannot find the vcpkg toolchain file, `VCPKG_ROOT` is not set or points
at the wrong checkout. Set it to the directory that contains
`scripts/buildsystems/vcpkg.cmake`.

If configure fails because `ccache` is missing, install ccache or remove the
`CMAKE_C_COMPILER_LAUNCHER` and `CMAKE_CXX_COMPILER_LAUNCHER` entries from the
base preset for your local build.

If startup fails immediately with missing data, check that `GAME_DATA` points at
the actual installed demo or game directory, not the source repository.

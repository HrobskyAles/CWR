# macOS Bootstrap Design

**Date:** 2026-07-05

**Repository:** `/Users/ali/Developer/OPF_Remaster/CWR`

**Demo data:** `/Users/ali/Developer/OPF_Remaster/Arma Cold War Assault Demo`

## Objective

Get the project running and prove that its source can be built from an Apple
Silicon Mac with the least initial porting work. This bootstrap deliberately
uses compatibility and virtualization: it is not a native macOS port.

## Decision

Use two independent tracks:

1. Run the supplied Windows x86-64 `PoseidonGameDemo.exe` with Whisky on macOS
   to validate the demo data, graphics, audio, input, and launch options.
2. Build the Linux x86-64 `PoseidonGameDemo` target from source in the
   repository-provided Steam Runtime 4 container, using OrbStack as the Docker
   engine on the Apple Silicon host.

Whisky is selected for the first track because it is free, supports Apple
Silicon, and provides a practical Wine/Game Porting Toolkit wrapper for a quick
runtime smoke test. Whisky is no longer actively maintained, so a failed Whisky
launch is not strong evidence that the Windows binary cannot run on macOS; it
only means this free compatibility layer did not validate it. OrbStack is
selected for the build track because it is already installed on this Mac,
provides the Docker CLI endpoint, and supports x86 emulation.

The two tracks intentionally produce and run different platform binaries. This
is the central trade-off: it gives the quickest evidence that the game runs and
the source builds, but does not yet prove that the locally built binary runs.

## Repository Evidence

- The supported CMake presets target Windows x64 and Linux x64; there is no
  macOS preset.
- The repository supplies `docker/steamrt4/Dockerfile` and
  `docker/steamrt4/run-build.sh` for the Linux x64 build.
- `Arma Cold War Assault Demo/PoseidonGameDemo.exe` is a Windows x86-64
  executable and the extensionless `PoseidonGameDemo` is a Linux x86-64 ELF
  executable.
- The demo directory contains the required game-data directories and an
  `OpenAL32.dll` runtime.
- Native macOS compilation is blocked by Linux-only linker flags, ELF crash
  handling, `.so` loading, `/proc` usage, Linux memory APIs, and unverified
  OpenGL 4.1 compatibility.

## Architecture and Boundaries

### Runtime validation track

Whisky owns Windows API and x86-64 translation through its Wine/GPTK stack. A
dedicated Windows bottle contains only configuration; the executable and demo
assets remain in the existing demo directory. The initial launch uses
conservative windowed settings and disables the splash screen. If normal audio
prevents startup, a second diagnostic launch disables sound rather than
changing the data set.

Success is determined from visible game behavior and the runtime log, not just
from process creation.

The launch must preserve the demo directory as the process working directory so
the executable can resolve adjacent game-data folders such as `AddOns`, `BIN`,
`DTA`, `Missions`, and `fonts`.

### Source-build track

OrbStack owns the Linux VM and Docker daemon. Docker Buildx builds the supplied
SteamRT image for `linux/amd64`. That image owns CMake, Clang, vcpkg, and
dependency installation. The source directory is bind-mounted at `/work/ofpr`,
and the repository script configures the `linux-x64-steamrt4` preset and builds
only `PoseidonGameDemo`.

The build must leave the artifact on the host under
`CWR/dist/x64-linux-steamrt4/PoseidonGameDemo`. Build caches stay under ignored
`CWR/build/` and `CWR/tmp/` paths. No source edits are part of this bootstrap.

### Optional exact-artifact runtime track

Running the new Linux artifact is a separate gate. It requires an x86-64 Linux
GUI with OpenGL 3.3, SDL display/input access, and audio. Docker-on-macOS is not
treated as a reliable game runtime because forwarding a modern OpenGL context
through a container is fragile. If an existing Linux x86-64 machine or VM with
working 3D acceleration is available, copy the built executable into a copy of
the demo-data directory and smoke-test it there. Otherwise, record this gate as
deferred rather than adding X11 or audio forwarding complexity to the initial
workflow.

## Execution Flow

1. Record host architecture, available disk space, executable formats, and
   checksums of the supplied binaries.
2. Start Whisky and create an isolated Windows bottle.
3. Launch the supplied Windows demo from its existing data directory with
   `--window --width 1280 --height 720 --no-splash`.
4. Verify main-menu rendering, mission loading, input, and audio; retain the log
   and exact launch settings.
5. Start OrbStack and verify that Docker reports a usable daemon and an
   `linux/amd64` builder.
6. Build the supplied SteamRT image for `linux/amd64`.
7. Run the image with the source bind mount and request only the
   `PoseidonGameDemo` target.
8. Verify the output is an x86-64 Linux ELF executable and that its required
   shared libraries are expected SteamRT dependencies.
9. If a suitable Linux GUI environment is already available, run the locally
   built artifact against a copy of the demo data. Otherwise stop after the
   successful artifact inspection and document the deferred runtime gate.

## Failure Handling

- If Whisky cannot launch the game, first retry with `--nosound`; then inspect
  logs for missing DLLs, OpenGL/context creation, or asset-path failures. Do not
  modify source code during this track.
- If Docker is unreachable, start OrbStack and verify the active Docker context
  before rebuilding anything.
- If Buildx lacks `linux/amd64`, bootstrap or select a builder that advertises
  that platform before starting the expensive image build.
- If the SteamRT image build cannot fetch its base image, vcpkg repository, or
  packages, classify it as a network/registry failure and retry without source
  changes.
- If CMake compilation fails, preserve the first compiler/linker error and the
  exact command. Do not mask failures by widening the target set or switching
  presets.
- If the source-built executable lacks an OpenAL runtime or another dynamic
  dependency, diagnose packaging separately from compilation.

## Verification and Success Criteria

The bootstrap is complete when all mandatory criteria hold:

- The supplied Windows demo reaches the main menu through Whisky.
- A demo mission enters gameplay in a window at 1280x720.
- Keyboard and mouse input work; audio works or a documented `--nosound`
  fallback permits gameplay.
- The unmodified source tree configures with `linux-x64-steamrt4`.
- `PoseidonGameDemo` builds successfully inside the `linux/amd64` SteamRT
  container.
- The locally produced artifact exists under `CWR/dist/x64-linux-steamrt4/` and
  `file` identifies it as an x86-64 Linux ELF executable.
- Logs, commands, and any deferred exact-artifact runtime result are recorded.

Running the locally built Linux executable is desirable but not mandatory for
this bootstrap unless an appropriate Linux GUI environment already exists.

## Non-goals

- Adding a native macOS CMake preset or producing a Mach-O executable.
- Porting Linux/ELF-specific source code to Darwin.
- Building a macOS `.app`, signing, or notarizing it.
- Adding Metal or Vulkan rendering.
- Making Docker provide a production-quality GUI/audio game runtime on macOS.
- Modifying or redistributing the separately licensed demo assets.

## Transition to a Native Port

After this bootstrap succeeds, native work should begin as a separate project.
Use `NATIVE_MACOS_PORTING_ANALYSIS.md` as discovery input, then create a focused
native-port design covering macOS CMake/vcpkg presets, Apple-specific platform
branches, OpenAL loading, crash reporting, user-data paths, and OpenGL 4.1
fallbacks. The bootstrap artifacts and runtime observations provide a known-good
behavioral baseline for that work.

## External References

- Whisky: <https://getwhisky.app/>
- Whisky repository: <https://github.com/Whisky-App/Whisky>
- OrbStack documentation: <https://docs.orbstack.dev/>
- Docker multi-platform builds:
  <https://docs.docker.com/build/building/multi-platform/>

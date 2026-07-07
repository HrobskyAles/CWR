# Native macOS Terminal Port Design

**Date:** 2026-07-07

**Repository:** `/Users/ali/Developer/OPF_Remaster/CWR`

**Demo data:** `/Users/ali/Developer/OPF_Remaster/Arma Cold War Assault Demo`

## Objective

Produce a native Apple Silicon macOS build path for the existing engine and get
`PoseidonGameDemo` far enough to launch from Terminal against the existing demo
data directory. This milestone proves the current SDL3, OpenGL, and OpenAL
architecture can become a Mach-O executable before investing in `.app`
packaging, signing, notarization, Metal, or asset redistribution.

## Decision

Use a staged terminal-launch port. Add a macOS CMake preset, fix the smallest
set of Darwin-incompatible build and runtime assumptions, then configure, build,
and smoke-launch `PoseidonGameDemo` from Terminal.

The first native target is:

- Host: macOS on Apple Silicon arm64.
- CMake preset: `macos-arm64-clang`.
- vcpkg target triplet: built-in `arm64-osx` unless a later failure proves an
  overlay triplet is required.
- Runtime shape: terminal-launched executable using the existing demo data in
  place.
- Renderer: existing SDL3 + OpenGL backend.
- Audio: existing OpenAL backend with macOS runtime-library lookup.

## Non-goals

- Building a `.app` bundle.
- Signing, hardened runtime, notarization, or installer work.
- Porting to Metal or Vulkan.
- Replacing SDL3, OpenGL, OpenAL, vcpkg, or CMake.
- Copying, repackaging, or redistributing demo assets.
- Making Intel macOS or universal binaries work in the first pass.
- Making every app/tool target fully native if `PoseidonGameDemo` can be
  isolated first.

## Repository Evidence

- `CMakePresets.json` includes Windows, Linux, and sanitizer preset files only.
- `cmake/presets/base.json` already routes dependency resolution through vcpkg.
- `vcpkg.json` is mostly portable; Linux-only `dbus` and Windows-only
  `directxtex` are already platform guarded.
- App and tool targets use GNU linker groups such as `-Wl,--start-group` and
  `-Wl,--end-group`; Apple `ld64` does not support those flags.
- `engine/Poseidon/CMakeLists.txt` links raw `pthread dl` for every non-Windows
  platform and selects POSIX paths for every non-Windows platform.
- `engine/Poseidon/Foundation/Platform/CrashHandler.cpp` treats every
  non-Windows build as Linux and uses ELF, GNU build IDs, `dl_iterate_phdr`,
  `<link.h>`, and `/proc/self/maps`.
- `engine/Poseidon/Foundation/Common/Platform.cpp` implements
  `linuxMemoryUsage()` through `/proc/<pid>/statm`.
- `engine/PoseidonOpenAL/OpenALRuntime.hpp` loads `libopenal.so.1` or
  `libopenal.so` on every non-Windows platform.
- `engine/Poseidon/Graphics/Shared/RenderDocCapture.cpp` loads
  `librenderdoc.so` on every non-Windows platform.
- `engine/Poseidon/Foundation/Common/PlatformPaths_posix.cpp` uses Linux/XDG
  paths for every non-Windows platform.
- `engine/PoseidonGL33/EngineGL33_State.cpp` calls `glClipControl` only when the
  function pointer exists, but macOS OpenGL 4.1 compatibility still needs a
  launch-time audit.

## Architecture

### Build System

Add `cmake/presets/macos.json` and include it from `CMakePresets.json`.

The new preset should inherit the existing base vcpkg setup, use Ninja, set
`CMAKE_BUILD_TYPE=Debug`, set `VCPKG_TARGET_TRIPLET=arm64-osx`, and set
`CMAKE_OSX_ARCHITECTURES=arm64`.

Do not introduce a macOS overlay triplet at the start. Add one only if the
built-in vcpkg triplet cannot express a required linkage or compiler setting.

Replace non-Windows CMake assumptions with explicit branches:

```cmake
if(WIN32)
  ...
elseif(APPLE)
  ...
elseif(UNIX)
  ...
endif()
```

Use `find_package(Threads REQUIRED)` and `Threads::Threads` where thread linkage
is needed. Use `${CMAKE_DL_LIBS}` instead of raw `dl`; it is empty or correct on
platforms such as macOS where `dlopen` is provided by libSystem.

For `PoseidonGameDemo`, link the engine/backend libraries in a normal explicit
order on Apple rather than passing GNU linker group flags. If unresolved symbols
remain because of static-library cycles, fix target dependencies or repeat the
specific libraries on Apple before using broader `-all_load` or `-force_load`.

### Platform Layer

Split Linux-only source behavior from Darwin behavior without renaming broad
engine APIs during this milestone.

`CrashHandler.cpp` should have a separate `__APPLE__` branch. The macOS branch
should install fatal signal handlers, report the signal name, fault address,
process id, version, commit, raw return addresses, and `backtrace_symbols_fd`
output. It must not include ELF headers, use GNU build IDs, call
`dl_iterate_phdr`, or read `/proc/self/maps`. Mach-O image listing through
`_dyld_image_count` and related APIs is deferred until after the first terminal
launch works.

`linuxMemoryUsage()` should compile on macOS by either returning `0` or using a
small Mach `task_info` implementation. The function name can remain unchanged
for compatibility; wider naming cleanup is not part of this milestone.

`RenderDocCapture.cpp` should keep Windows and Linux behavior unchanged and
return unavailable on Apple. RenderDoc integration is not required for the first
native launch.

### Paths

Add a macOS path provider instead of reusing XDG paths on Apple. It should keep
the same `PlatformPaths.hpp` API and map:

- config/data/support to `~/Library/Application Support/<app>`
- cache to `~/Library/Caches/<app>`
- user-visible documents/content to either `~/Documents/<app>` or the support
  directory

For this milestone, prefer `~/Library/Application Support/<app>` for both
config/data/support and content so a terminal launch does not create surprising
visible folders. The launch itself still points at the existing demo data
directory; these paths are for user config/cache behavior.

Linux tests must keep validating XDG behavior. Add Apple-gated tests for the
macOS path provider so Linux expectations do not change.

### Audio

Keep the current runtime-loaded OpenAL model. Add Apple candidates to
`OpenALRuntime.hpp`, tried before or alongside generic names:

- `@rpath/libopenal.dylib`
- `libopenal.1.dylib`
- `libopenal.dylib`

If none load, report a clear macOS-specific error. The first smoke launch may
use existing no-sound diagnostics if audio blocks startup, but a successful
terminal port should either initialize OpenAL or fail cleanly without a crash.

The existing vcpkg overlay already enables CoreAudio for Apple targets, so no
initial OpenAL source patch is planned.

### Graphics

Keep the existing `PoseidonGL33` backend and SDL3 OpenGL context path. The first
launch should test whether macOS accepts the requested core profile and whether
all used GL entry points are available.

Known first audit item:

- `glClipControl(GL_LOWER_LEFT, GL_ZERO_TO_ONE)` in
  `EngineGL33_State.cpp`.

The existing function-pointer guard may be enough to avoid a crash, but every
missing GL 4.2+ or 4.5 feature that is reached on macOS must be guarded or given
a fallback before the launch is considered successful. A renderer rewrite is
not part of this milestone.

## Runtime Flow

The smoke launch should run from Terminal with the demo data directory as the
working directory or with the engine's existing content-path controls pointed at
that directory. The initial command shape is expected to be close to:

```bash
cd "/Users/ali/Developer/OPF_Remaster/Arma Cold War Assault Demo"
/Users/ali/Developer/OPF_Remaster/CWR/build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo
```

If asset lookup requires existing flags or environment variables, use those
instead of copying data into the build tree.

Success is determined by real runtime behavior: SDL window creation, OpenGL
context initialization, OpenAL initialization or clean diagnostic failure, and
visible progress into the main menu or early UI.

## Error Handling

The port should preserve the first meaningful failure instead of masking it with
scope expansion. If configure, build, link, OpenAL load, GL context creation, or
asset discovery fails, record:

- exact command,
- failing target or subsystem,
- compiler/linker/runtime message,
- whether the failure is macOS-specific, dependency-specific, or an existing
  cross-platform issue.

Do not start `.app` packaging, Metal work, or broad refactoring to hide a
terminal-launch blocker.

## Verification

Required verification for the milestone:

```bash
cmake --preset macos-arm64-clang
cmake --build --preset macos-arm64-clang --target PoseidonGameDemo
```

If target-specific build presets are not defined, use the generated build
directory directly:

```bash
cmake --build build/macos-arm64-clang --target PoseidonGameDemo
```

Run focused tests when they compile on macOS:

- platform path tests,
- crash handler compile or unit coverage if safe,
- OpenAL runtime loader behavior if an existing test seam is available,
- any existing smoke tests that do not require Linux-only assumptions.

Then run a manual terminal smoke launch against the existing demo data
directory. A successful milestone should produce a native Mach-O executable,
launch it from Terminal, and reach the main menu or early UI. If a macOS runtime
blocker prevents that result, preserve the exact evidence and keep it inside the
implementation plan as unfinished work rather than treating the port as
complete.

## Risks

- vcpkg dependency resolution for `arm64-osx` may expose package-specific
  issues.
- Static library cycles hidden by GNU linker groups may need target dependency
  cleanup.
- Apple OpenGL tops out at 4.1, so runtime feature gaps may appear after the
  code compiles.
- Demo asset lookup may assume Windows or Linux working-directory behavior.
- OpenAL `.dylib` resolution may require rpath work before packaging exists.
- Tests may contain Linux-only `/proc/self/exe` assumptions that need gating
  before the full test suite can run.

## Success Criteria

The design is complete when the implementation plan can target this bounded
outcome:

- `macos-arm64-clang` exists and configures on Apple Silicon.
- `PoseidonGameDemo` builds as a native macOS arm64 Mach-O executable.
- Linux and Windows build behavior is preserved by explicit platform branches.
- macOS avoids Linux-only crash, memory, RenderDoc, OpenAL, and path behavior.
- The executable launches from Terminal against the existing demo data and
  reaches the main menu or early UI.
- Any blocker found during implementation is fixed within this terminal-launch
  scope or documented as the reason the milestone remains incomplete; it must
  not expand the work into packaging or renderer replacement.

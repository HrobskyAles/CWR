# Native macOS Terminal Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and smoke-launch a native Apple Silicon `PoseidonGameDemo` from Terminal using the existing demo data directory.

**Architecture:** Add a macOS CMake preset, then split Darwin behavior out of the current non-Windows/Linux branches in small, testable surfaces: platform paths, crash/memory reporting, RenderDoc detection, OpenAL runtime loading, and app linking. Keep SDL3, OpenGL, OpenAL, vcpkg, and the existing terminal executable shape.

**Tech Stack:** CMake presets, vcpkg `arm64-osx`, Clang, C++17/C++20, SDL3, OpenGL, OpenAL Soft, Catch2.

---

## File Structure

- Create `cmake/presets/macos.json`: macOS arm64 debug configure preset.
- Modify `CMakePresets.json`: include the macOS preset file.
- Modify `engine/Poseidon/CMakeLists.txt`: select the macOS path provider and use portable thread/dl linkage.
- Modify `apps/cwr/GameDemo/CMakeLists.txt`: add an Apple link branch without GNU linker groups.
- Create `engine/Poseidon/Foundation/Common/PlatformPaths_macos.cpp`: native macOS user-directory provider.
- Modify `engine/Poseidon/Foundation/Common/PlatformPaths.hpp`: document macOS path behavior.
- Modify `tests/unit/engine/Poseidon/Foundation/Common/test_platformPaths.cpp`: add Apple-gated path tests while preserving Linux XDG tests.
- Modify `engine/Poseidon/Foundation/Common/Platform.cpp`: make `linuxMemoryUsage()` compile on Apple with Mach memory reporting or a safe fallback.
- Modify `engine/Poseidon/Foundation/Platform/CrashHandler.cpp`: add a Darwin signal/backtrace branch and keep Linux ELF behavior unchanged.
- Modify `tests/unit/engine/Poseidon/Foundation/Platform/test_crash_handler.cpp`: assert `/proc/self/maps` only on Linux.
- Modify `engine/Poseidon/Graphics/Shared/RenderDocCapture.cpp`: make RenderDoc lookup Windows/Linux-only and unavailable on Apple.
- Modify `engine/PoseidonOpenAL/OpenALRuntime.hpp`: add `.dylib` and `@rpath` candidates for macOS.
- Optionally modify `engine/PoseidonGL33/EngineGL33_State.cpp`: only if the first macOS compile or launch proves an unguarded OpenGL symbol or behavior issue.

## Task 1: Add macOS Build Preset And Apple Link Branch

**Files:**
- Create: `cmake/presets/macos.json`
- Modify: `CMakePresets.json`
- Modify: `engine/Poseidon/CMakeLists.txt`
- Modify: `apps/cwr/GameDemo/CMakeLists.txt`

- [ ] **Step 1: Add failing preset expectation**

Run:

```bash
test -f cmake/presets/macos.json
```

Expected before implementation: fails with exit code `1`.

- [ ] **Step 2: Create the macOS preset file**

Add `cmake/presets/macos.json`:

```json
{
  "version": 6,
  "include": [
    "base.json"
  ],
  "configurePresets": [
    {
      "name": "macos-clang-debug",
      "hidden": true,
      "inherits": "base",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug"
      }
    },
    {
      "name": "macos-arm64-clang",
      "displayName": "macOS arm64 Clang Debug",
      "inherits": "macos-clang-debug",
      "binaryDir": "${sourceDir}/build/macos-arm64-clang",
      "cacheVariables": {
        "VCPKG_TARGET_TRIPLET": "arm64-osx",
        "CMAKE_OSX_ARCHITECTURES": "arm64"
      }
    }
  ]
}
```

- [ ] **Step 3: Include macOS presets**

Update `CMakePresets.json` so the include list contains:

```json
[
  "cmake/presets/windows.json",
  "cmake/presets/linux.json",
  "cmake/presets/sanitizers.json",
  "cmake/presets/macos.json"
]
```

- [ ] **Step 4: Make engine linkage portable**

In `engine/Poseidon/CMakeLists.txt`, add `find_package(Threads REQUIRED)` near the dependency section and replace the raw non-Windows link block with:

```cmake
find_package(Threads REQUIRED)

target_link_libraries(Poseidon PUBLIC
    spdlog::spdlog
)
if(NOT WIN32)
    target_link_libraries(Poseidon PUBLIC Threads::Threads ${CMAKE_DL_LIBS})
endif()
```

- [ ] **Step 5: Select the macOS path provider**

Replace the `PlatformPaths` generator expression in `MERGED_SUPPORT_SOURCES` with a three-way selection:

```cmake
set(POSEIDON_PLATFORM_PATHS_SOURCE
    ${CMAKE_CURRENT_SOURCE_DIR}/Foundation/Common/PlatformPaths_posix.cpp
)
if(WIN32)
    set(POSEIDON_PLATFORM_PATHS_SOURCE
        ${CMAKE_CURRENT_SOURCE_DIR}/Foundation/Common/PlatformPaths_win.cpp
    )
elseif(APPLE)
    set(POSEIDON_PLATFORM_PATHS_SOURCE
        ${CMAKE_CURRENT_SOURCE_DIR}/Foundation/Common/PlatformPaths_macos.cpp
    )
endif()
```

Then use `${POSEIDON_PLATFORM_PATHS_SOURCE}` in `MERGED_SUPPORT_SOURCES`.

- [ ] **Step 6: Link `PoseidonGameDemo` without GNU groups on Apple**

Change `apps/cwr/GameDemo/CMakeLists.txt` to:

```cmake
if(WIN32)
    target_link_libraries(PoseidonGameDemo PRIVATE
        GameBase Poseidon PoseidonGL33 PoseidonOpenAL
        winmm.lib version.lib ws2_32.lib legacy_stdio_definitions.lib
    )
elseif(APPLE)
    target_link_libraries(PoseidonGameDemo PRIVATE
        GameBase PoseidonGL33 Poseidon PoseidonOpenAL
        ${CMAKE_DL_LIBS}
    )
else()
    target_link_libraries(PoseidonGameDemo PRIVATE
        -Wl,--start-group GameBase PoseidonGL33 Poseidon PoseidonOpenAL -Wl,--end-group
        pthread dl
    )
endif()
```

- [ ] **Step 7: Verify preset text and commit**

Run:

```bash
test -f cmake/presets/macos.json
rg -n "macos-arm64-clang|cmake/presets/macos.json|elseif\\(APPLE\\)" CMakePresets.json cmake/presets/macos.json engine/Poseidon/CMakeLists.txt apps/cwr/GameDemo/CMakeLists.txt
```

Expected: all commands succeed and show the new preset and Apple branches.

Commit:

```bash
git add CMakePresets.json cmake/presets/macos.json engine/Poseidon/CMakeLists.txt apps/cwr/GameDemo/CMakeLists.txt
git commit -m "build: add macos arm64 preset"
```

## Task 2: Add Native macOS Platform Paths

**Files:**
- Create: `engine/Poseidon/Foundation/Common/PlatformPaths_macos.cpp`
- Modify: `engine/Poseidon/Foundation/Common/PlatformPaths.hpp`
- Modify: `tests/unit/engine/Poseidon/Foundation/Common/test_platformPaths.cpp`

- [ ] **Step 1: Add Apple-gated tests**

Add these cases to `test_platformPaths.cpp`:

```cpp
#ifdef __APPLE__
TEST_CASE("macOS platform paths use Library conventions", "[platformPaths][macos]")
{
    auto tmpHome = fs::temp_directory_path() / "test_macos_home";
    fs::create_directories(tmpHome);

    ScopedEnv homeEnv("HOME", tmpHome.c_str());

    std::string config = Poseidon::Foundation::getUserConfigDir("TestApp_MacPaths");
    std::string data = Poseidon::Foundation::getUserDataDir("TestApp_MacPaths");
    std::string cache = Poseidon::Foundation::getUserCacheDir("TestApp_MacPaths");
    std::string documents = Poseidon::Foundation::getUserDocumentsDir("TestApp_MacPaths");

    REQUIRE(config == (tmpHome / "Library" / "Application Support" / "TestApp_MacPaths").string());
    REQUIRE(data == config);
    REQUIRE(documents == config);
    REQUIRE(cache == (tmpHome / "Library" / "Caches" / "TestApp_MacPaths").string());
    REQUIRE(dirExists(config));
    REQUIRE(dirExists(cache));

    fs::remove_all(tmpHome);
}
#endif
```

- [ ] **Step 2: Keep XDG tests Linux-only**

Change the existing XDG test guard from:

```cpp
#ifndef _WIN32
```

to:

```cpp
#if !defined(_WIN32) && !defined(__APPLE__)
```

for the Linux XDG-specific cases.

- [ ] **Step 3: Implement macOS path provider**

Create `PlatformPaths_macos.cpp`:

```cpp
#include <Poseidon/Foundation/Common/PlatformPaths.hpp>

#include <cstdlib>
#include <string>
#include <sys/stat.h>

namespace
{
void ensureDirectory(const std::string& path)
{
    if (path.empty())
        return;
    for (size_t i = 1; i < path.size(); ++i)
    {
        if (path[i] == '/')
        {
            std::string partial = path.substr(0, i);
            mkdir(partial.c_str(), 0755);
        }
    }
    mkdir(path.c_str(), 0755);
}

std::string homeDir()
{
    const char* home = getenv("HOME");
    if (home && home[0] != '\0')
        return home;
    return "/tmp";
}

std::string appSupportDir(const char* appName)
{
    std::string dir = homeDir() + "/Library/Application Support/" + (appName ? appName : "Poseidon");
    ensureDirectory(dir);
    return dir;
}

std::string cacheDir(const char* appName)
{
    std::string dir = homeDir() + "/Library/Caches/" + (appName ? appName : "Poseidon");
    ensureDirectory(dir);
    return dir;
}
} // namespace

namespace Poseidon::Foundation
{
std::string getUserConfigDir(const char* appName)
{
    return appSupportDir(appName);
}

std::string getUserDataDir(const char* appName)
{
    return appSupportDir(appName);
}

std::string getUserCacheDir(const char* appName)
{
    return cacheDir(appName);
}

std::string getUserDocumentsDir(const char* appName)
{
    return appSupportDir(appName);
}
} // namespace Poseidon::Foundation
```

- [ ] **Step 4: Document macOS path behavior**

Update `PlatformPaths.hpp` comments to include:

```cpp
/// macOS:   ~/Library/Application Support/<appName>
```

for config/data/documents and:

```cpp
/// macOS:   ~/Library/Caches/<appName>
```

for cache.

- [ ] **Step 5: Verify path source and tests text**

Run:

```bash
rg -n "PlatformPaths_macos|Application Support|Library/Caches|defined\\(__APPLE__\\)" engine/Poseidon/Foundation/Common tests/unit/engine/Poseidon/Foundation/Common/test_platformPaths.cpp engine/Poseidon/CMakeLists.txt
```

Expected: output shows the new provider, Apple tests, and CMake source selection.

Commit:

```bash
git add engine/Poseidon/Foundation/Common/PlatformPaths_macos.cpp engine/Poseidon/Foundation/Common/PlatformPaths.hpp tests/unit/engine/Poseidon/Foundation/Common/test_platformPaths.cpp engine/Poseidon/CMakeLists.txt
git commit -m "platform: add macos user paths"
```

## Task 3: Split Darwin Crash, Memory, And RenderDoc Behavior

**Files:**
- Modify: `engine/Poseidon/Foundation/Common/Platform.cpp`
- Modify: `engine/Poseidon/Foundation/Platform/CrashHandler.cpp`
- Modify: `tests/unit/engine/Poseidon/Foundation/Platform/test_crash_handler.cpp`
- Modify: `engine/Poseidon/Graphics/Shared/RenderDocCapture.cpp`

- [ ] **Step 1: Gate Linux-specific crash test assertions**

In `test_crash_handler.cpp`, keep the test enabled for POSIX platforms, but assert `/proc/self/maps` only on Linux:

```cpp
#ifdef __linux__
    REQUIRE(report.find("/proc/self/maps:") != std::string::npos);
#else
    REQUIRE(report.find("/proc/self/maps:") == std::string::npos);
#endif
```

- [ ] **Step 2: Add macOS memory reporting branch**

In `Platform.cpp`, add Apple includes:

```cpp
#if defined(__APPLE__)
#include <mach/mach.h>
#endif
```

Then change `linuxMemoryUsage()` to:

```cpp
size_t linuxMemoryUsage()
{
#if defined(__APPLE__)
    mach_task_basic_info info{};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, reinterpret_cast<task_info_t>(&info), &count) != KERN_SUCCESS)
        return 0;
    return static_cast<size_t>(info.resident_size);
#else
    char procfn[32];
    snprintf(procfn, sizeof(procfn), "/proc/%d/statm", getpid());
    FILE* f = fopen(procfn, "rt");
    if (!f)
        return 0;
    int size = 0, resident = 0, share = 0, trs = 0, lrs = 0, drs = 0, dt = 0;
    fscanf(f, "%d %d %d %d %d %d %d", &size, &resident, &share, &trs, &lrs, &drs, &dt);
    fclose(f);
    size_t pageSize = getpagesize();
    LOG_DEBUG(Core, "Memory total: {} KB, shared: {} KB, data: {} KB", (size * pageSize) >> 10,
              (share * pageSize) >> 10, (drs * pageSize) >> 10);
    return (drs * pageSize);
#endif
}
```

- [ ] **Step 3: Split crash handler includes**

In `CrashHandler.cpp`, change the non-Windows include block so `<link.h>` is Linux-only:

```cpp
#if defined(__linux__)
#include <link.h>
#endif
```

- [ ] **Step 4: Add Darwin-safe build-id capture**

Rename the current `captureBuildId()` function to `captureLinuxBuildId()` and
guard that renamed function with `#if defined(__linux__)`. Then add this wrapper
below it:

```cpp
void captureBuildId()
{
#if defined(__linux__)
    captureLinuxBuildId();
#else
    std::snprintf(g_buildId, sizeof(g_buildId), "mach-o");
#endif
}
```

The result is that only Linux compiles the `dl_iterate_phdr`, `ElfW`, and
`NT_GNU_BUILD_ID` code, while Apple records a simple non-empty identifier in the
existing report field.

- [ ] **Step 5: Gate `/proc/self/maps` in the signal handler**

In `handler()`, wrap the maps copy:

```cpp
#if defined(__linux__)
    if (fd >= 0)
    {
        emit(fd, -1, "\n/proc/self/maps:\n");
        copyFileTo(fd, "/proc/self/maps");
    }
#endif
    if (fd >= 0)
        close(fd);
```

- [ ] **Step 6: Make RenderDoc unavailable on Apple**

In `RenderDocCapture.cpp`, include `<dlfcn.h>` only for Linux:

```cpp
#elif defined(__linux__)
#include <dlfcn.h>
#endif
```

Then move the current `dlopen("librenderdoc.so", RTLD_NOW | RTLD_NOLOAD)`
lookup into a Linux-only branch and add an unsupported-platform branch:

```cpp
#elif defined(__linux__)
    void* mod = dlopen("librenderdoc.so", RTLD_NOW | RTLD_NOLOAD);
    if (!mod)
        return false;
    auto getApi = reinterpret_cast<pRENDERDOC_GetAPI>(dlsym(mod, "RENDERDOC_GetAPI"));
    if (!getApi)
        return false;
    void* ptr = nullptr;
    if (getApi(eRENDERDOC_API_Version_1_5_0, &ptr) != 1 || !ptr)
        return false;
    s_api = static_cast<RENDERDOC_API_1_5_0*>(ptr);
    int maj = 0, min = 0, pat = 0;
    s_api->GetAPIVersion(&maj, &min, &pat);
    LOG_INFO(Graphics, "RenderDoc API attached: v{}.{}.{}", maj, min, pat);
    return true;
#else
    return false;
#endif
```

- [ ] **Step 7: Verify Linux-only symbols are gated**

Run:

```bash
rg -n "#if defined\\(__linux__\\)|#elif defined\\(__linux__\\)|mach_task_basic_info|/proc/self/maps|librenderdoc.so" engine/Poseidon/Foundation/Common/Platform.cpp engine/Poseidon/Foundation/Platform/CrashHandler.cpp engine/Poseidon/Graphics/Shared/RenderDocCapture.cpp tests/unit/engine/Poseidon/Foundation/Platform/test_crash_handler.cpp
```

Expected: Linux-only symbols appear inside Linux-gated code or Linux-gated tests.

Commit:

```bash
git add engine/Poseidon/Foundation/Common/Platform.cpp engine/Poseidon/Foundation/Platform/CrashHandler.cpp tests/unit/engine/Poseidon/Foundation/Platform/test_crash_handler.cpp engine/Poseidon/Graphics/Shared/RenderDocCapture.cpp
git commit -m "platform: split darwin runtime diagnostics"
```

## Task 4: Add macOS OpenAL Runtime Loading

**Files:**
- Modify: `engine/PoseidonOpenAL/OpenALRuntime.hpp`

- [ ] **Step 1: Add OpenAL candidate helper**

Replace the non-Windows `TryLoadModule()` body with platform-specific candidates:

```cpp
#elif defined(__APPLE__)
    const char* candidates[] = {
        "@rpath/libopenal.dylib",
        "libopenal.1.dylib",
        "libopenal.dylib",
    };
    for (const char* candidate : candidates)
    {
        ModuleHandle() = dlopen(candidate, RTLD_NOW | RTLD_LOCAL);
        if (ModuleHandle() != nullptr)
            return true;
    }
    SetError("OpenAL dylib is not available");
    return false;
#else
    ModuleHandle() = dlopen("libopenal.so.1", RTLD_NOW | RTLD_LOCAL);
    if (ModuleHandle() == nullptr)
        ModuleHandle() = dlopen("libopenal.so", RTLD_NOW | RTLD_LOCAL);
    if (ModuleHandle() == nullptr)
    {
        SetError("libopenal.so is not available");
        return false;
    }
#endif
```

- [ ] **Step 2: Verify library names**

Run:

```bash
rg -n "__APPLE__|@rpath/libopenal.dylib|libopenal.1.dylib|OpenAL dylib" engine/PoseidonOpenAL/OpenALRuntime.hpp
```

Expected: all macOS candidates and the macOS error message are present.

Commit:

```bash
git add engine/PoseidonOpenAL/OpenALRuntime.hpp
git commit -m "audio: load openal dylibs on macos"
```

## Task 5: Configure, Build, And Smoke Launch

**Files:**
- Modify only if verification exposes a concrete blocker.

- [ ] **Step 1: Check toolchain availability**

Run:

```bash
command -v cmake
command -v ninja
command -v clang
```

Expected: each prints a path. If `cmake` is missing, install or expose CMake before running configure.

- [ ] **Step 2: Parse presets**

Run:

```bash
cmake --list-presets
```

Expected: output includes `macos-arm64-clang`.

- [ ] **Step 3: Configure macOS build**

Run:

```bash
cmake --preset macos-arm64-clang
```

Expected: CMake configure succeeds. If dependency resolution fails because vcpkg must fetch packages, rerun with approved network access or install dependencies outside the sandbox.

- [ ] **Step 4: Build the terminal demo**

Run:

```bash
cmake --build build/macos-arm64-clang --target PoseidonGameDemo
```

Expected: `PoseidonGameDemo` links as a native macOS executable.

- [ ] **Step 5: Inspect executable format**

Run:

```bash
file build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo
```

Expected: output reports a Mach-O arm64 executable.

- [ ] **Step 6: Run focused unit tests if built**

Run:

```bash
ctest --test-dir build/macos-arm64-clang -R "platformPaths|crash handler" --output-on-failure
```

Expected: platform-path tests pass; crash-handler test passes or is skipped only if Catch discovery does not include it in this build.

- [ ] **Step 7: Smoke launch from Terminal**

Run:

```bash
cd "/Users/ali/Developer/OPF_Remaster/Arma Cold War Assault Demo"
/Users/ali/Developer/OPF_Remaster/CWR/.worktrees/native-macos-terminal-port/build/macos-arm64-clang/apps/cwr/GameDemo/PoseidonGameDemo
```

Expected: SDL creates a window, OpenGL initializes, and the app reaches the main menu or early UI. If launch fails, capture the exact runtime error and fix only terminal-launch blockers inside this milestone.

- [ ] **Step 8: Commit verification fixes or final status**

If verification required code changes:

```bash
git status --short
git add engine/PoseidonGL33/EngineGL33_State.cpp
git commit -m "fix: complete macos terminal launch"
```

If the verification fix changed a different file, replace the `git add` path
with the exact path shown by `git status --short`. If no further changes were
needed, do not create an empty commit.

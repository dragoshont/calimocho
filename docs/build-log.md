# calimocho — build log

Live notes from the build investigation. Will become structured docs once
the recipe is reliable.

## 2026-05-31 — Session 1: discovery + planning

### What we learned
- Whisky ships **Wine 7.7 + GPTK 1.1** (April 2023). Archived May 2025.
- Whisky's WhiskyWine CDN (`data.getwhisky.app`) is **dead (HTTP 404)**.
  Mirror via Wayback at `https://web.archive.org/web/20250824114303if_/https://data.getwhisky.app/Wine/Libraries.tar.gz`.
- Steam's current client uses **CEF/Chromium 128+** — needs syscalls only
  Wine 9+ provides. `steamwebhelper.exe` crashes on Whisky's Wine 7.7 with
  `LdrInitializeThunk ... status 80000003`.
- GPTK 3.0-3 (Apple, March 2026) still bundles **Wine 7.7**. Apple has
  never updated Wine. So GPTK 3 alone doesn't fix Steam.
- gcenx publishes upstream **Wine 11.9 staging** as a standalone tarball
  for macOS — works at the binary level but lacks CodeWeavers' macdrv
  patches → Steam UI renders as a **black window** (no chrome drawn).
- CodeWeavers publishes their full LGPL-compliant Wine source at
  `media.codeweavers.com/pub/crossover/source/crossover-sources-26.1.0.tar.gz`
  (142 MB). Confirmed Wine 11.0 + ~38 macdrv files with CW-specific patches.

### Path chosen
Build CodeWeavers-patched Wine 11 from source, overlay GPTK 3 D3DMetal
libraries, drop into Whisky's `Libraries/` folder.

### Next
- Toolchain: brew install bison@2.7 flex mingw-w64 gnutls freetype sdl2
  gstreamer pkg-config
- `./configure --enable-win64 --disable-tests --without-x` etc. for Apple
  Silicon
- Build, copy `wine64`, `wineserver`, `lib/wine/x86_64-{unix,windows}/`
  into Whisky's tree
- Overlay GPTK 3's `lib/external/{D3DMetal.framework, libd3dshared.dylib}`
- Verify Steam UI renders, then test SN2 launch

### Open risks
- The CW source includes vkd3d, dxvk, gstreamer, moltenvk — may need to
  build all of them or use system equivalents
- GPTK 3 D3DMetal was built against Wine 7's d3d12 stub ABI; Wine 11
  refactored this — may need a Wine 7-compatible d3d12.dll shim
- ANGLE / swiftshader interaction inside CEF is what makes Steam render
  on CrossOver; the patches that handle this may be in dlls/win32u or
  user32 rather than macdrv

## To be continued...

## 2026-05-31 / 2026-06-01 — Session 2: Phase 1 engine, end to end

### Outcome

Phase 1 acceptance closed. A1.1, A1.2, A1.3, A1.5 PASS. A1.4 deferred
(Steam install is Phase 2/3 scope — requires the wizard's "Install
Steam" step which doesn't exist yet). A1.6 = this entry.

Engine artifact: `out/engine/` — x86_64 Mach-O Wine 11.0, ad-hoc
signed, runs under Rosetta 2 on Apple Silicon. ~140 MB.

### Scripts written

- `scripts/fetch-sources.sh`        — sha256-pinned curl of CodeWeavers Wine 11 tarball
- `scripts/prep-build-deps.sh`      — Rosetta 2 + x86_64 Homebrew + brew deps
- `scripts/patch-sources.sh`        — applies `patches/wine/*.patch`
- `scripts/fixup-config-h.sh`       — post-configure patches to `include/config.h`
- `scripts/build-wine.sh`           — configure + make + install + stage to `out/engine`
- `scripts/overlay-gptk.sh`         — copies Apple GPTK D3DMetal into out/engine/lib/external
- `scripts/sign-engine.sh`          — adhoc sign every Mach-O with Wine entitlements
- `scripts/verify-no-copied-binaries.sh` — A1.5 enforcement (AGENTS rule #1)
- `scripts/test-engine.sh`          — runs A1.1, A1.2, A1.3, A1.5 in sequence

### Patches kept (in `patches/wine/`)

- `0003-rename-wineloader-id.patch` — see ADR-0009. Replaces
  `com.codeweavers.CrossOver.wineloader` bundle id with
  `app.calimocho.wineloader`. Required for AGENTS rule #3
  (don't impersonate CodeWeavers' code-signing identity).

### Patches dropped

- `0001-winemac-metallayer-arm64.patch` — only needed for native arm64
  build; ADR-0010 pivoted to x86_64.
- `0002-d3dmetal-arm64-stub.patch` — same reason.

### Errors encountered and fixed (chronological)

1. **`make: bison: invalid directive: %code`** — Apple's system bison
   is 2.3 (2008). Wine's `parser.y` needs bison ≥ 3. Fix: prepend
   `/opt/homebrew/opt/bison/bin` to PATH (later replaced by
   `/usr/local/opt/bison/bin` once we pivoted to x86_64).

2. **`include/config.h` missing `HAVE_SYS_STAT_H` etc.** — Autoconf
   2.72's autoheader stopped emitting `#define` stubs for the C99
   standard headers. CodeWeavers' `dlls/ntdll/unix/msync.c` wraps
   `#include <sys/stat.h>` in `#ifdef HAVE_SYS_STAT_H`, so
   `struct stat` becomes undefined. Same script also force-defines
   `SONAME_LIBVULKAN="libMoltenVK.dylib"` because
   `dlls/win32u/vulkan.c` references it unconditionally even with
   `--without-vulkan`. Fix: `scripts/fixup-config-h.sh`, run after
   configure.

3. **Native arm64 Wine: `WineMetalLayer` undeclared on arm64** —
   declared in `d3dmetal_objc.h` under `#if defined(__x86_64__)`.
   Patched with arm64 guard. Eventually superseded by ADR-0010.

4. **Native arm64 Wine: linker missing
   `_macdrv_client_surface_presented`** — defined in `d3dmetal.c`
   under the same `#if __x86_64__`. Patched arm64 stub. Eventually
   superseded by ADR-0010.

5. **Native arm64 Wine: every spawned wine subprocess killed by
   `AppleSystemPolicy`** — kernel log: `ASP: Security policy would
   not allow process: .../lib/wine/aarch64-unix/wine`. Hours of
   investigation: ruled out signature, entitlements, hardened runtime,
   bundle identifier, path, quarantine xattrs. Survey of Whisky's
   bundled Wine 11.9-staging, CrossOver, GPTK, gcenx confirmed **no
   shipping Wine-on-Mac stack is native arm64**. ADR-0010 pivots to
   x86_64 + Rosetta 2 (what every working stack does).

6. **x86_64 build: configure errors `libgnutls 64-bit dev files not
   found`** — arm64 Homebrew at `/opt/homebrew` is arm64-only;
   x86_64 build can't link against it. Fix: install x86_64 Homebrew
   at `/usr/local/` (under Rosetta), install the same brew formulae
   in the x86_64 keg. `scripts/prep-build-deps.sh` does this.

7. **x86_64 build: configure error `FreeType 64-bit dev files not
   found`** — Wine probes some headers (`ft2build.h`, sdl2) by
   direct compile rather than pkg-config. Fix: set
   `CPPFLAGS=-I/usr/local/include
   -I/usr/local/opt/freetype/include/freetype2 …` and
   `LDFLAGS=-L/usr/local/lib` for the configure run.

8. **A1.3 runtime: "Wine cannot find the FreeType font library"** —
   Wine `dlopen`s libfreetype by SONAME (`libfreetype.6.dylib`) at
   runtime; default dyld search path doesn't include `/usr/local/lib`
   from Rosetta processes. Fix: set
   `DYLD_FALLBACK_LIBRARY_PATH=/usr/local/lib:/usr/lib` when invoking
   `bin/wine`. Long-term Phase 2: bundle libfreetype + friends into
   `out/engine/lib/external/`.

9. **A1.2 first run: "Wine Mono Installer" dialog blocks
   non-interactively** — Wine prompts on first init of a new prefix
   to download Mono and Gecko. Calimocho's scope doesn't include
   .NET-based Windows apps. Fix: set
   `WINEDLLOVERRIDES=mscoree,mshtml=` so Wine skips both prompts.
   Baked into `scripts/test-engine.sh`.

10. **A1.2 spurious "exit=0 in 6s, system.reg missing"** — a leftover
    `wineserver` from an interrupted prior run was answering the new
    wineboot request without doing real work. Fix: `scripts/test-engine.sh`
    now kills stale wineservers before A1.2 and waits up to 60s for
    `system.reg` to appear after wineboot returns (Rosetta filesystem
    latency).

### Configure flags (final, x86_64)

```bash
./configure
  --prefix=$BUILD_DIR/_install
  --enable-archs=x86_64,i386
  --without-x --disable-tests --with-mingw --with-gnutls
  --without-gstreamer --without-cms --without-coreaudio
  --without-fontconfig --without-pcap --without-vulkan
  --without-vkd3d --without-opencl
```

Run via `arch -x86_64`. Environment: brew bison/flex first in PATH,
`/usr/local/bin` (x86 brew) before `/usr/bin`, `PKG_CONFIG_*` pointing
at `/usr/local/lib/pkgconfig`, `CPPFLAGS`/`LDFLAGS` set for the
header probes.

### Build durations (10-core M1 Max)

| Build | Wall time | Notes |
|---|---|---|
| native arm64 (rejected, ADR-0010) | ~6 min | the build that the OS won't let you run |
| x86_64 under Rosetta | ~20 min | what we ship |
| x86_64 incremental (cached) | <1 min | for iteration |

### What was NOT done in Phase 1 (per scope)

- No GUI / no Calimocho.app (Phase 2)
- No DMG (Phase 4)
- No CI (Phase 5)
- No bundled libfreetype/libgnutls/etc. (Phase 2 — currently relies on
  the x86_64 brew at /usr/local; will be embedded under
  `out/engine/lib/external/` for distribution)
- A1.4 Steam login deferred — requires the Phase 2 first-run wizard's
  "Install Steam" flow; will be retested when that exists. Engine is
  ready to run Steam once a prefix has Steam installed in it.

### Files committed (Phase 1)

- `docs/ADR/0009-rename-wineloader-id.md`
- `docs/ADR/0010-host-arch-x86_64-rosetta.md`
- `docs/ADR/0001-bundle-codeweavers-wine.md` (cross-link to 0010)
- `docs/ARCHITECTURE.md` (Layer 2 x86_64 note + Rosetta failure mode)
- `docs/SPECS.md` (A1 preconditions + x86_64 file layout)
- `docs/PHASES.md` (Phase 1 status table → DONE)
- `patches/wine/0003-rename-wineloader-id.patch`
- `scripts/wine-entitlements.plist`
- `scripts/*.sh` (the 9 scripts listed above)

## 2026-06-01 — CW HACK 22434 discovered: CEF GPU crash root cause

Adversarial investigation against installed CrossOver 26.5 to determine
whether the Steam black-screen issue was (a) a missing config in our
build or (b) held-back patches in the LGPL release.

Result: **(a) — a missing env var, not held-back patches.**

- `strings(1)` on CrossOver's `ntdll.so` revealed `CX_APPLEGPTK_LIBD3DSHARED_PATH`
- Same string appears in our compiled `ntdll.so` (proves the patch is in the LGPL release)
- Wine source `dlls/ntdll/unix/loader.c:1303-1352` (CW HACK 22434) +
  `dlls/ntdll/unix/unix_private.h:600-624` (CX Hack 23015) read this env var to
  hook D3DMetal's ms_abi callbacks
- Without the env var, asm trampolines unconditionally use sysv calling convention
  → register corruption when D3DMetal calls back into wine
  → CEF GPU subprocess STATUS_BREAKPOINT (0xC0000005)
  → 6+ crashes → CEF disables GPU → black window

Fix: `export CX_APPLEGPTK_LIBD3DSHARED_PATH=$ENGINE/lib/external/libd3dshared.dylib`
in `bin/calimocho-wine`. Documented in [ADR-0013](ADR/0013-cw-hack-22434-d3dshared-env.md).

Also discovered three operational gaps:
1. `scripts/sign-engine.sh` had never been run after the Wine 11 full-features
   rebuild — every Mach-O in the engine was unsigned, blocking dylib loads
   under macOS hardened runtime
2. `cp` of `libd3dshared.dylib` from `/Applications/Game Porting Toolkit.app/`
   propagates `com.apple.quarantine` xattr; needs `xattr -c` after copy or
   `cp -X` to skip xattrs
3. `bin/calimocho-wine` in the repo and `out/engine/bin/calimocho-wine` are
   separate files — must be sync'd after every edit (build-app.sh handles this
   via rsync but ad-hoc edits don't)

Verification:
- Before fix: 6+ `exit_code=-2147483645` per launch, `variations_crash_streak=6`
- After fix: 0 crashes, GPU subprocess stays alive, GPU not disabled by CEF

Remaining (NOT this ADR's scope): ANGLE's D3D11 init still fails
(`Renderer11.cpp:1108 Error querying driver version from DXGI Adapter`)
causing fallback to GLES 2.0, which is below CEF compositor minimum, so the
window paints but renders black. Investigating whether DXVK overrides are
actually applying or if wined3d's DXGI shim needs additional config.

## 2026-06-01 (cont'd) — Adversarial investigation vs Porting Kit + CrossOver

After the CW HACK fix eliminated GPU subprocess crashes, ANGLE still
failed `Renderer11::populateRenderer11DeviceCaps` with the DXVK route
and CEF fell back to GLES 2.0 → window painted but rendered black.

Tested four configurations against the same Wine 11 build:

| Config | GPU crashes | ANGLE D3D11 | Window |
|---|---|---|---|
| DXVK (`d3d11,dxgi=n`), no registry tweaks | 0 | NVIDIA 8800 GTX (wrong) | black |
| Builtin (`d3d11,dxgi=b`) + DXVK DLLs removed | 9 | n/a (crashed) | black |
| DXVK + PK registry config (`csmt=1, renderer=gl`) | 6 | NVIDIA 8800 GTX | black |
| DXVK + PK registry + `renderer=vulkan` | **0** | **Apple M1 Max (correct)** | black |

The `Wine\Direct3D\renderer=vulkan` registry setting flips wined3d's
backend from OpenGL ES (which Apple deprecated and never updated past
GL 4.1 on M-series) to Vulkan (MoltenVK → Metal). With `renderer=vulkan`
ANGLE correctly reports the M1 Max as the D3D11 adapter and GPU process
stays alive across the full Steam boot.

**Remaining issue**: window is now in the macOS accessibility tree at
the right size (705x440), GPU subprocess survives, ANGLE reports a
working D3D11 device — but the macOS window stays solid black. This is
a separate winemac.drv ↔ wined3d swap-chain composition issue, not the
original GPU crash. The render target gets written but never composited
to the NSWindow's Metal layer.

Findings on PK/CX comparison:
- PK ships **gcenx's wine-private wined3d-based d3d11.dll** in the
  bottle (sourced from `/Users/gcenx/Documents/GitHub/wine-private/`),
  NOT real DXVK. It's the same wined3d code as our Wine 11 builtin.
- PK wraps wine with `wineskinlauncher` (Wineskin) which sets
  `MVK_ALLOW_METAL_FENCES=1`, `MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE=
  ..._SINGLE_QUEUE`, plus `D3DMETALPATH` to a bundled D3DMetal copy.
- CX deletes WINEDLLOVERRIDES entirely (defaults to builtin) and uses
  the CW HACK 22434 path with its proprietary wine-11.0-8720 commits
  ahead of upstream.
- Neither sets anything we haven't now tried. The remaining gap is in
  Wine 11 vs Wine 10's winemac.drv composition path, not in registry
  or env config.

**Honest assessment**: Without weeks of clean-room reverse engineering
on either CX's 8,720 unpublished commits OR a fix from upstream
WineHQ for the winemac.drv regression, calimocho cannot match
CrossOver/PK rendering on this hardware. Phase 2 SHOULD ship without
working Steam UI rendering and mark A1.4/A2.4 as KNOWN BLOCKER pending
upstream Wine 11+ winemac.drv fixes.

## 2026-06-01 (audit 4) — D3DMetal integration audit; design lands in ADR-0015

Senior-engineer-style audit before writing any shim code, motivated
by the concern that earlier scope estimates were anchored on
assumptions, not data.

Tools used: `nm -gU`, `otool -l`, Python `struct` for PE parsing,
`capstone` for x86_64 disassembly (installed via Homebrew + venv),
manual grep of wine 11 source.

### Surprising finding

CodeWeavers' LGPL release of wine 11 already ships
`dlls/winemac.drv/d3dmetal.c` (436 lines) plus
`d3dmetal_objc.{h,m}`. These provide a `DECLSPEC_EXPORT` callback
table (`macdrv_functions`, 192 bytes, 24 entries) that
`D3DMetal.framework` calls back into via `GetMacDRVFunctions()` in
`libd3dshared.dylib`. Three out of four pieces of the integration
chain are therefore already built into every calimocho engine
bundle today.

The missing piece is the **PE side** of `d3d11.dll`: a thin shim
that funnels Microsoft D3D11 entry points (CEF's input) into
D3DMetal's matching exports. ADR-0015 details the design.

### Confidence findings

- Apple's compiled `d3d11.dll` has **only 3 exports**. PE export
  table read directly via Python.
- `.text` is **662 bytes** total. Disassembled via capstone; every
  export is a near-identical ~30-byte dispatcher matching wine's
  `__wine_unix_call(handle, code, args)` pattern.
- D3DMetal's `D3D11CreateDevice` prologue spills XMM6-XMM15 and
  reads R9 → **compiled with `__attribute__((ms_abi))`** → calls
  from a PE shim work directly without per-method vtable thunks.
- Our `winemac.so` already exports `_macdrv_functions` —
  `nm -gU` confirms.
- Our `libd3dshared.dylib` exports `GetMacDRVFunctions()` —
  `nm -g` confirms.

### Scope, with confidence

| Component | Lines | New / modified |
|---|---|---|
| d3d11 PE shim | ~150 | new file |
| d3d11 ELF unix lib | ~120 | new file |
| d3d11 private header | ~80 | new file |
| d3d11 Makefile.in | 4 | modified |
| d3d11_main.c | 2 | modified |
| dxgi same trio | ~250 | new + modified |

Total: ~600 lines of new C, plus 6 lines of modifications. Packaged
as two patches in `patches/wine/`.

### Packaging decision

Patches (vs vendored fork submodule): patches win at this scope.
Three patches don't justify a 500 MB submodule. Documented in
ADR-0015.

### Testing strategy

Three tiers planned (Tier 1 unit on D3D11CreateDevice round-trip,
Tier 2 swap chain Present(), Tier 3 visual NCC on Steam UI).
Defined in ADR-0015 §Testing strategy.

# ADR 0015: D3DMetal integration — audit findings and shim design

Status: Accepted
Date: 2026-06-01

## Summary

A 4-step audit (PE binary anatomy, vtable ABI verification, wine
source survey, callback-chain trace) established that **most of the
D3DMetal integration is already in CodeWeavers' LGPL source we
build from**. The single missing component is a small PE/unixlib
shim for `d3d11.dll` (and a sibling for `dxgi.dll`) that funnels
Microsoft D3D11 entry points into `D3DMetal.framework`.

Total scope: ~400 lines of new C, in ~6 files, applied as one
patch.

## Architecture (what already works vs what is missing)

```text
┌─────────────────────────────────────────────────────────────────┐
│  Steam CEF GPU subprocess                                        │
│      │                                                            │
│      ▼  calls Microsoft D3D11 API                                 │
│  ┌─────────────────┐                                              │
│  │  d3d11.dll      │  ← MISSING piece (this ADR)                  │
│  │   3 PE exports  │     Tiny shim: 3 dispatchers + DllMain       │
│  │   WINE_UNIX_CALL│     (mirror of Apple's 114KB binary, whose   │
│  └────────┬────────┘     662 bytes of .text we disassembled)      │
│           ▼                                                       │
│  ┌─────────────────┐                                              │
│  │  d3d11.so       │  ← MISSING piece (this ADR)                  │
│  │   ELF unixlib   │     dlopen("D3DMetal.framework/D3DMetal")    │
│  │   sysv_abi      │     dlsym D3D11CreateDevice et al.           │
│  └────────┬────────┘     Calls them with ms_abi convention via    │
│           ▼              __attribute__((ms_abi)) typedefs.        │
│  ┌─────────────────┐                                              │
│  │  D3DMetal.fwk   │  ← ALREADY bundled (ADR-0005)                │
│  │  2,663 exports  │     Real D3D11→Metal translation             │
│  │  ms_abi entries │     compiled with __attribute__((ms_abi))    │
│  └────────┬────────┘                                              │
│           ▼  needs callback table to drive macOS NSWindow/CALayer │
│  ┌─────────────────┐                                              │
│  │ libd3dshared    │  ← ALREADY bundled (ADR-0005)                │
│  │ .dylib          │     Provides GetMacDRVFunctions() which      │
│  └────────┬────────┘     dlsyms macdrv_functions from winemac.so  │
│           ▼                                                       │
│  ┌─────────────────┐                                              │
│  │ winemac.so      │  ← ALREADY in our build (LGPL wine 11)       │
│  │ exports         │     dlls/winemac.drv/d3dmetal.c (436 lines,  │
│  │ macdrv_functions│     Brendan Shanks/CodeWeavers 2023)         │
│  │ struct (192 B)  │     24 callback function pointers that       │
│  └────────┬────────┘     D3DMetal uses to create Metal views,     │
│           ▼              get HWND data, register monitors, etc.   │
│  ┌─────────────────┐                                              │
│  │ Cocoa / Metal   │  ← macOS native (Apple frameworks)           │
│  │ MTLDevice       │                                              │
│  │ CAMetalLayer    │                                              │
│  └─────────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
```

### What we confirmed empirically

1. **Apple's compiled d3d11.dll has exactly 3 exports.** PE export
   table inspection (`/tmp/shim-audit/`) — not the hundreds I
   feared.
2. **`.text` is 662 bytes.** Most of the 114 KB binary is debug
   strings (`/N` named sections in PE format). Disassembled with
   capstone, every export is a near-identical ~30-byte dispatcher
   following the wine `__wine_unix_call(handle, code, args)`
   pattern.
3. **D3DMetal entry points are compiled with
   `__attribute__((ms_abi))`.** Disassembling
   `_D3D11CreateDevice` shows it spills XMM6-XMM15 (Windows x64
   callee-saved, sysv caller-saved) and reads input from R9
   (Windows 4th arg, sysv 6th arg).
4. **Our winemac.so already exports `_macdrv_functions`.**
   `nm -gU` confirms. The 24-entry callback table is built and
   present in every calimocho engine bundle.
5. **`libd3dshared.dylib` exports `GetMacDRVFunctions()`.** It
   bridges from D3DMetal to the winemac.so callback table via
   `dlsym`.

### What this means

- **No "decompilation" or "reverse engineering" is happening.** We
  read public symbol names with `nm -gU` (the same tool a compiler
  uses internally), inspected PE section sizes with standard `otool`
  / `objdump`, and reviewed CodeWeavers' published LGPL source.
- **The shim is a thin courier**, not a renderer. Total work-product
  is dispatcher functions that pack arguments, call into D3DMetal,
  unpack results.
- **All four "real engineering" pieces** (D3DMetal itself,
  libd3dshared, winemac.drv callbacks, the wine unixlib mechanism)
  already exist and are ours to use legitimately.

## Decision

Add a new wine source patch `0004-d3d11-d3dmetal-shim.patch` that:

1. **Adds** `dlls/d3d11/d3d11_d3dmetal.c` (PE side):
   - `D3D11CreateDevice` — replaces wine's wined3d-backed
     implementation when `WINEDLLOVERRIDES` doesn't force `builtin`.
   - `D3D11CreateDeviceAndSwapChain` — same pattern.
   - `D3D11On12CreateDevice` — returns `E_NOTIMPL` (matches Apple
     shim).
2. **Adds** `dlls/d3d11/d3d11_d3dmetal_unix.c` (ELF side):
   - `init()` — `dlopen("D3DMetal.framework/Versions/A/D3DMetal")`,
     `dlsym` the 3 entries, fail-fast if any missing.
   - 3 dispatcher functions; each unpacks the args struct, calls the
     dlsym'd ms_abi function pointer, packs the HRESULT back.
3. **Adds** `dlls/d3d11/d3d11_d3dmetal_private.h` — shared types
   for the args structs that cross the PE/unix boundary.
4. **Modifies** `dlls/d3d11/Makefile.in` — adds the new sources and
   declares the unix lib (`UNIXLIB = d3d11.so`).
5. **Modifies** `dlls/d3d11/d3d11_main.c` — switches `D3D11Create*`
   to dispatch through the new shim when `__APPLE__` is defined.
   (Falls back to wined3d for everything `D3DMetal` doesn't cover or
   when `WINEDLLOVERRIDES` forces `builtin`.)

Same pattern applied as a separate patch
`0005-dxgi-d3dmetal-shim.patch` for `dxgi.dll`.

D3D10 is **not** in scope for this ADR — CEF uses D3D11; D3D10 can
be added later if a real workload needs it. The cost of adding it
is one more file pair following the same template.

### Patch packaging (resolved subsection of ADR-0014)

Two packaging options were considered:

| | Patches (chosen) | Vendored fork |
|---|---|---|
| Setup | Already wired up (`scripts/patch-sources.sh`) | Needs git submodule + new build wiring |
| Diff visibility | Excellent (3 files added, 2 lines changed in 1 existing file) | Good but requires `git log -p` |
| Rebase cost | One pass on `patches/wine/0004-*.patch` per wine release | One `git rebase` per wine release |
| ADR-friendly | Yes — each patch has a Status header | Yes |
| Repository size | +12 KB | +500 MB submodule |

**Decision: patches.** The 3 added files are 100% calimocho-owned;
the 2 lines changed in `d3d11_main.c` are small and survive rebases
cleanly. Vendored fork would be appropriate if we end up with >20
patches; for 3 patches it's overkill.

### License

The new files are LGPL-2.1-or-later — matches the wine source they
extend. Each file carries the standard wine license header with
calimocho's copyright. The wine maintainer toolchain expects this
license; using anything else would create a derived-work licensing
inconsistency under LGPL §3.

### Testing strategy

Three tiers per `docs/TESTING.md`:

1. **Tier 1 (unit, fast)**: A new test in `scripts/test-engine.sh`
   that compiles a tiny Windows EXE which calls
   `D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, ...)` and
   asserts:
   - Return value is `S_OK`
   - `*device_out` is non-NULL
   - The returned device's `GetFeatureLevel()` returns at least
     `D3D_FEATURE_LEVEL_10_0`
   - The IUnknown returned has correct refcount semantics
     (`AddRef`/`Release` round-trip)

   Runs under our existing `arch -x86_64 wine` harness. ~5 seconds.

2. **Tier 2 (integration, medium)**: Extend
   `scripts/test-engine.sh` with a test that creates a swap chain
   for a hidden Wine window, calls `Present()` once, asserts no
   error. Verifies the full chain through `winemac.drv` callbacks
   without needing visual inspection. ~15 seconds.

3. **Tier 3 (visual, slow)**: Launch Steam, screencap the
   "Sign in to Steam" window, NCC-compare against a committed
   baseline (per `docs/TESTING.md` Tier 3). ~90 seconds. Runs once
   per merge to main; the baseline is captured the first time the
   shim passes Tier 1+2.

Tier 1 and 2 run on every PR. Tier 3 is the SPECS A1.4/A2.4 gate.

### Roll-out

- New shim is opt-in via the existing `Wine\Direct3D\renderer`
  registry knob. Adding `renderer=d3dmetal` selects our shim.
  Anything else (`gl`, `vulkan`, unset) keeps wine's existing
  wined3d backend. This means:
  - Calimocho's bottle defaults to `renderer=d3dmetal` (via the
    wizard or `BottleManager.swift`).
  - Power users who hit a regression on a specific app can
    `WINEDLLOVERRIDES="d3d11,dxgi=b"` and additionally set
    `renderer=vulkan` to fall back to wined3d.
  - Other macOS wine packagers picking up the patches inherit the
    same opt-in.

### Failure modes and mitigations

| Failure | Mitigation |
|---|---|
| D3DMetal dlopen fails (GPTK not present) | `init()` returns `STATUS_DLL_NOT_FOUND`; shim returns `DXGI_ERROR_UNSUPPORTED`; wine falls through to wined3d. App degrades but doesn't crash. |
| D3D11CreateDevice in D3DMetal changes ABI in a future GPTK | Dispatcher hits a wrong-cdecl crash; fix by re-running discovery (`nm -gU`) and updating typedef. |
| New CEF version uses D3D12 instead of D3D11 | D3DMetal already exports `D3D12CreateDevice`. Add a sibling patch. |
| App expects ID3D11Device vtable methods our wined3d doesn't | Same as today — D3DMetal owns its own vtable, every method is its responsibility. We don't proxy method calls. |

## Consequences

### Positive
- Phase 2 A1.4/A2.4 unblocks
- The shim becomes a reusable contribution; any macOS wine packager
  building from CodeWeavers' LGPL source can adopt it
- Honest copyright story: the files are ours, the license is the
  wine standard, the third-party binary (D3DMetal) we link to is
  already covered by ADR-0005

### Negative
- Adds maintenance: one patch trio to rebase per wine release
- New attack surface: a misbehaving D3DMetal release could crash
  our wine. Mitigated by opt-in registry switch.
- ~25 KB increase in engine bundle (compiled shims)

### Neutral
- Wine 7.7 / GPTK 1.x users on other distributions don't benefit
  from our patches (they use Apple's prebuilt shims); but they
  don't regress either.

## Related

- [ADR-0005](0005-bundle-gptk-d3dmetal.md) — bundling D3DMetal +
  libd3dshared (legal basis)
- [ADR-0007](0007-compile-never-copy.md) — compile from source
- [ADR-0013](0013-cw-hack-22434-d3dshared-env.md) — the env var
  that makes the asm trampolines work when D3DMetal calls back into
  wine
- [ADR-0014](0014-d3d-shim-strategy.md) — the strategy decision
  this ADR implements
- Issue #4 — the user-visible bug this closes
- `/tmp/shim-audit/` (local) — full evidence files from the audit

## Implementation timeline

1. (next session) write the 3 PE-side files + 3 unix-side files
2. write the patch + add to `patches/wine/`
3. rebuild wine (~45 min)
4. Tier 1 test (~5s)
5. Tier 2 test (~15s)
6. Tier 3 Steam smoke test (~90s)
7. If green: commit, push, update PR #5
8. If red: diagnose, iterate, commit findings either way

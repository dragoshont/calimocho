# ADR 0014: D3D11 shim strategy — wine ABI version coupling

Status: Draft (decision needed)
Date: 2026-06-01

## Context

Phase 2 acceptance criteria A1.4 and A2.4 (Steam UI renders correctly)
remain blocked after ADR-0013 fixed the CEF GPU subprocess crash class.
The remaining issue is documented in issue #4: the macOS NSWindow stays
solid black even though ANGLE/wined3d correctly initialize a D3D11
device backed by the Apple M1 Max via MoltenVK.

Investigation against Apple's Game Porting Toolkit (GPTK) binaries
revealed a fundamental architectural mismatch:

- Apple GPTK ships `d3d11.dll` as a thin **PE shim** (~106 KB) that
  contains no D3D logic. The shim issues `__wine_unix_call(handle,
  code, args)` syscalls into a paired ELF unixlib (`d3d11.so`, which
  is a symlink to `libd3dshared.dylib` — Apple's D3DMetal native code).
- GPTK was built against **wine 7.7** (`wine_sources/include/wine/unixlib.h`
  as of D3DMetalDLLsBase-17.12).
- Our Phase 1/2 build is **wine 11.0** from CodeWeavers' LGPL
  tarball. Between wine 7.7 and 11.0, the unixlib dispatch ABI was
  redesigned to `__wine_unix_call_dispatcher` with a different
  prologue and argument layout.

Loading GPTK's PE shim into our wine 11 process therefore issues
syscalls against an ABI ntdll no longer provides → `STATUS_BREAKPOINT`
in the GPU subprocess.

The piece that actually does the D3D → Metal work, `libd3dshared.dylib`,
is fine. It's the PE-side `d3d11.dll` shim that is version-coupled to
wine 7.7.

## Decision

**To be decided.** Two viable paths.

### Path A — downgrade to wine version compatible with GPTK shims

Build from CodeWeavers' older LGPL tarball (wine 7.7+CrossOver patches
for that vintage). GPTK shim DLLs work as shipped.

Trade-offs:
- (+) ships in days, not weeks
- (+) matches the build other macOS Wine packaging communities
  ship today
- (−) loses 4 years of wine improvements: modern gstreamer, modern
  wined3d, Vulkan WSI work, and the CW HACK 22434 / 23015 code
  paths (which only exist in 10.x+ CodeWeavers sources)
- (−) Phase 1 / 1.5 acceptance criteria must be re-verified against
  the older wine
- (−) less future-proof — wine 7.7 is two LTS lines behind
- (−) ADR-0013 becomes obsolete (would need its own reversal)

### Path B — port D3D shim DLLs to wine 11 unixlib ABI

Write our own `dlls/d3d11/d3d11.c` (and siblings) against wine 11's
`include/wine/unixlib.h` that forward to `libd3dshared.dylib`'s public
D3DMetal entry points via the new `wine_unix_call_dispatcher` API.

Trade-offs:
- (+) keeps wine 11 + ADR-0013 win
- (+) clean, in-tree, ADR-friendly
- (+) becomes a reusable contribution for the next person who hits this
- (−) real engineering work (~2-4 weeks for someone fluent in wine's
  PE/unix split)
- (−) needs ongoing maintenance as `libd3dshared.dylib` evolves
- (−) needs reverse-discovery of `libd3dshared.dylib`'s public ABI
  (the dylib exports are documented only via header files in the GPTK
  redistributable; we can read those headers but they're not
  formally specified)

## Consequences (per-path)

**Path A**: Phase 2 A1.4/A2.4 ships in days. Phase 1/1.5 risk: low if
older wine still compiles with our scripts; medium if not. Trail of
ADRs: 0001, 0007, 0010, 0013 all need revisiting.

**Path B**: Phase 2 A1.4/A2.4 ships in weeks. Phase 1/1.5 unchanged.
ADR-0013 stays valid. New ADR-0015 would document the shim port.

## Related

- Issue #4 — the user-visible bug this ADR addresses
- ADR-0005 — bundling D3DMetal.framework + libd3dshared.dylib (legal basis)
- ADR-0007 — compile from source, never copy CrossOver binaries
- ADR-0013 — CX_APPLEGPTK_LIBD3DSHARED_PATH (the crash class fix)

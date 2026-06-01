# ADR 0018: Pivot proposal — adopt PK-style FOSS stack (DXVK + Wine 10 + MoltenVK) over D3DMetal shim

Status: Proposed
Date: 2026-06-01

## Context

ADR-0015 and ADR-0016 committed calimocho to writing PE/ELF shims
that forward `d3d11.dll` (and planned `dxgi.dll`) into Apple's
`D3DMetal.framework`. Three sessions of experiments produced:

- Tier-1 standalone test passes through the shim → D3DMetal returns
  a real FL11.x device (ADR-0015).
- Apple's full PE+ELF drop-in is **not viable** on our Wine 11:
  libd3dshared expects Wine 7.7 trampoline ABI; CEF GPU subprocess
  crashes STATUS_ACCESS_VIOLATION (ADR-0016, Alternatives Rejected).
- With our shim, Steam CEF and SN2's UE5 shipping exe **both**
  hang at `D3D11CreateDevice(adapter=non-NULL)` because D3DMetal
  can't dereference a wined3d-style `IDXGIAdapter*` (Experiment A).
- Forcing NULL adapter lets `CreateDevice` succeed but then
  `CreateSwapChain` returns `DXGI_ERROR_INVALID_CALL` because the
  swap chain is still wined3d-backed (Experiment A part 2).
- Building the dxgi shim is ADR-0016's committed direction. Audit
  estimated ~250 lines; closer inspection suggests 600–1500
  realistic, plus permanent ABI coupling to CodeWeavers' source
  drops (ADR-0014).

In this session we measured the actually-working FOSS stack on the
same M1 Max:

### PK ("Steambuild 32 64bit DXVK.app") — measured 2026-06-01

```text
Wine:                  10.0 Sikarugir (gcenx-built)
bottle d3d11.dll:      3,895,959 bytes — strings: "DXVK adapter", "DxvkCommandList"
                       = DXVK 2.x PE binaries (MIT-licensed FOSS)
bottle dxgi.dll:       237,568 bytes — DXVK companion
*d3d11 override:       native,builtin   (DXVK takes priority)
D3DMETAL env:          0                (D3DMetal DISABLED at runtime)
D3DMETAL_FORCE env:    0                (D3DMetal not forced)
MOLTENVKCX env:        1                (use bundled MoltenVK ICD)
VKD3D_CONFIG:          force_static_cbv
VKD3D_FEATURE_LEVEL:   12_2
VK_ICD_FILENAMES:      .../MoltenVK_icd.json
Wine registry:
  [Software\Wine\Direct3D]
    "csmt"=1
    "renderer"="gl"
    "VideoMemorySize"="65536"
```

PK has **no** `lib/external/D3DMetal.framework`. **No**
`libd3dshared.dylib`. **No** CW HACK 22434 env var. The whole
proprietary CrossOver/Apple D3DMetal path is absent. Yet Steam UI
renders correctly under PK on this exact hardware.

The corresponding "Steambuild 32 64bit Direct3D.app" PK variant
sets `D3DMETAL_FORCE=1` and is the D3DMetal-path version — a
different (and apparently less robust) configuration. We tested
the DXVK variant; that's the one users actually use.

### What this tells us

ADR-0015/0016's strategic direction was **based on incomplete
upstream research.** I assumed (without measuring) that the
working free macOS Wine stacks routed through Apple's D3DMetal.
The measured reality is:

1. **PK's working path is DXVK 2.x bottled into the prefix, with
   wined3d as fallback.** Pure FOSS.
2. **D3DMetal is optional, not the default.** PK ships a
   D3DMetal-forced variant but the DXVK variant is the one most
   users run.
3. **CrossOver may still use D3DMetal as one option** but we never
   verified it's the *only* one. Their `d3d11.so` could be a
   DXVK fork they've privatized. We don't know.

In short: calimocho's D3DMetal shim path was chosen because we
thought CrossOver's `d3d11.so` proved D3DMetal was the only viable
route. That premise was wrong.

## Decision (proposed, not yet accepted)

Pivot calimocho's engine architecture from "Wine 11 builtin
wined3d → D3DMetal shim" to PK's proven stack:

| Layer | Current (ADR-0015/16) | Proposed pivot |
|---|---|---|
| Wine | 11.0 CW-patched | **10.0 (gcenx wine-private or upstream)** |
| d3d11.dll | Our PE shim → D3DMetal | **DXVK 2.x bottled, `native,builtin` override** |
| dxgi.dll | Planned PE shim → D3DMetal | **DXVK 2.x bottled** |
| Vulkan ICD | MoltenVK | MoltenVK (same) |
| D3DMetal | Required, via CW HACK | **Removed entirely** |
| libd3dshared | Bundled | **Removed entirely** |
| CW HACK 22434 env | Set by launcher | **Removed entirely** |
| wined3d renderer | `vulkan` (Audit 4 attempt) | **`gl` (PK's choice)** |

The pivot would supersede:

- ADR-0013 (CW HACK 22434 env var) — irrelevant when D3DMetal isn't loaded
- ADR-0014 (shim ABI coupling) — no shim, no coupling
- ADR-0015 (d3d11 shim implementation) — removed entirely
- ADR-0016 (dxgi shim required) — never implemented

## Open questions before accepting

1. **Does PK + full SN2 recipe actually run SN2 in-game?**
   `memories/repo/calimocho-sn2-recipe.md` lists CrossOver as the
   only stack proven to fully play SN2. The recipe was developed
   on CrossOver, untested on PK. If PK + recipe (vcrun, UE4SS,
   Sentry hack, AVX, Win11) can run SN2, the pivot fully closes
   the north star. If PK + recipe can't, even with calimocho-as-
   PK-clone we won't reach SN2 in-game — and ADR-0017 known-
   blocker becomes the honest answer.

   **Next test (this session):** symlink CrossOver's existing
   SN2 install into PK's bottle, install vcrun2022 via PK's
   winetricks, attempt SN2 launch.

2. **Can DXVK 2.x be redistributed under our license?** MIT-licensed.
   Yes. Bundle as `lib/external/dxvk/` like we bundle MoltenVK.

3. **Can we use upstream Wine 10 or do we need gcenx's
   wine-private patches?** PK uses wine-private. Need to diff what
   wine-private adds vs vanilla upstream 10.0. May be small (font
   rendering, mac-specific quirks) or large (gpfx, msync variants).
   Read-only research, ~2 hours.

4. **What does this do to the 3 weeks of session-1 work?** Most
   of it survives: the toolchain scripts (`fetch-sources`,
   `prep-build-deps`, `build-wine`, `sign-engine`, `bundle-deps`)
   apply equally to Wine 10. Only Wine 11–specific patches and
   the shim work go in the bin.

   Lost work:
   - `patches/wine/0004-d3d11-d3dmetal-shim.patch` and
     `patches/wine/files/d3d11/` (the shim) — delete
   - `tests/d3d11_shim/test_d3dmetal_shim.c` — delete or repurpose
   - Wine 11 vs Wine 10 source delta — small for our purposes
     (we don't use any Wine 11–only features)
   - About 1 week of source-level investigation that didn't
     pan out — sunk cost; doesn't justify staying on a wrong path

   Kept work:
   - All Phase 1 scripts and infrastructure
   - Phase 2 menubar + wizard (engine-agnostic at the API level)
   - All ADRs 0001–0012 and 0017 (still valid)
   - ADR-0013/0014/0015/0016 become **superseded** entries (deleted
     per AGENTS.md "no Superseded by stubs" rule), with this ADR's
     Context referencing what they tried)

## Consequences

### Positive

- **FOSS path that actually works on this hardware.** Empirically
  proven on the same M1 Max running today's macOS, today's
  Steam build, today's MoltenVK.
- **Lower maintenance.** No PE/ELF shim to keep ABI-compatible with
  CodeWeavers source drops. DXVK has its own upstream release
  cadence; we pin a release sha256 in `versions.json` like any
  other dep.
- **No proprietary Apple deps.** Removes the GPTK SLA dependency
  for the engine layer (we still redistribute GPTK pieces per
  ADR-0011 for legal cover, but they become optional).
- **Aligned with ADR-0017.** A FOSS path exists; we follow it
  instead of leading.

### Negative

- **One week of d3d11 shim work discarded.** Sunk cost.
- **Wine 11 → Wine 10 downgrade.** Loses upstream Wine 11 bugfixes.
  But: those bugfixes haven't helped us anyway; PK's Wine 10 is
  what works.
- **Now downstream of two FOSS dependencies (DXVK + MoltenVK)**
  instead of one (Wine). More coordination on releases.
- **D3DMETAL=0 means D3D12-only games won't have MetalFX upscaling**
  via Apple's path. SN2 is D3D11 + UE5, so this doesn't affect the
  north star. Future Wishlist games on D3D12 might.

### Neutral

- The bottle layout doesn't change much. DXVK DLLs go in
  `system32`/`syswow64` per the standard wine convention.
- `bin/calimocho-wine` simplifies: drop CW HACK env, MOLTENVK env
  becomes the main config story.

## Related

- ADR-0013 — to be superseded if accepted
- ADR-0014 — to be superseded if accepted
- ADR-0015 — to be superseded if accepted
- ADR-0016 — to be superseded if accepted (never implemented)
- ADR-0017 — affirms "we follow when FOSS exists", which this pivot
  enacts
- [docs/build-log.md](../build-log.md) — session entries 1, 2, 3
- Issue #4 — Steam UI black; this is the proposed fix

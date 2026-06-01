# D3D12 on Apple Silicon — FOSS state of the world (research as of 2026-06-01)

> **Working document.** Edited as research progresses, not after.
>
> **Question this answers:** is there a FOSS or FOSS-adjacent path to
> running UE5 SM6 games (Subnautica 2) on M1 Max today, or is the
> project genuinely upstream-blocked?
>
> **Standard:** every claim links to a source. Inferences are marked
> `INFERRED`. Things we measured ourselves cite the build log.
>
> **Why this exists:** the maintainer's kid wants to play SN2 on a
> Mac. Maintainer wants to ship a FOSS recipe. Today we hit dead
> ends but the dead-end conclusion was based on incomplete homework.
> This doc closes that gap.

---

## TL;DR

(filled in last)

---

## Methodology

- 7 search areas (sections 1–7 below).
- Each area: read the source's own primary docs (README, release
  notes, official issues), then community signal (forums, Discord
  where linked).
- After each section, ask: did this open or close a path? Then
  decide what to look at next.
- No code suggestions or pivots in this doc. It's evidence only.
  Pivots go in ADRs.

---

## 1. DXMT — D3D11+D3D12 to Metal (3Shain)

**Repo:** https://github.com/3Shain/dxmt
**Researched:** 2026-06-01

### What it is

DXMT is an open-source Metal-based translation layer for
**D3D11 and D3D10 only**. D3D12 is explicitly out of scope.

Source: [DXMT 1.0 Release Plan #151](https://github.com/3Shain/dxmt/issues/151)
scopes D3D10/11; no D3D12 roadmap.

### D3D11 production state

[v0.80 release notes (Apr 23)](https://github.com/3Shain/dxmt/releases/tag/v0.80)
report fixes for 15+ games including Overwatch 2, Baldur's Gate 3
DX11, Shadow of the Tomb Raider. Mesh-shader support landed in
[v0.70](https://github.com/3Shain/dxmt/releases/tag/v0.70).

No UE5 games in the supported list.

### D3D12 state

**Not implemented.** When asked to run a UE5 D3D12 game (Invincible
VS), the maintainer
[closed issue #163](https://github.com/3Shain/dxmt/issues/163)
confirming DXMT doesn't support DX12. The game falls back to
vkd3d-proton, which then fails on Apple Silicon Metal.

### Wine integration

Drop-in `d3d11.dll` / `dxgi.dll` / `winemetal.so` in Wine 8+
prefixes per
[DXMT installation guide](https://github.com/3Shain/dxmt/wiki/DXMT-Installation-Guide-for-Geeks).
Requires API exposure from `winemac.drv`. All Apple Silicon Macs
supported per
[Device System Runtime Specifications](https://github.com/3Shain/dxmt/wiki/Device-System-Runtime-Specifications).

### Recent activity

Very active: latest commits June 1 2026 (8h before this doc).
Active development on shader conformance, UAV handling,
tessellation. **No D3D12 discussions or PRs.**

### Verdict for calimocho

**DXMT closes our P1 question (Steam UI), not our P2 (SN2 D3D12).**

- For **P1** (Steam UI): DXMT is potentially superior to DXVK 2.x
  on Mac because it targets Metal directly, skipping the
  MoltenVK→Metal hop. We never tested it in calimocho — worth a
  measurement when P1 becomes the focus.
- For **P2** (SN2 in-game): DXMT is out. The maintainer's explicit
  closure of #163 signals no plan to implement D3D12. SN2 needs
  D3D12 (project not configured to support D3D11).

---

## 2. vkd3d-proton — D3D12 to Vulkan (Hans-Kristian Arntzen / Valve)

**Repo:** https://github.com/HansKristian-Work/vkd3d-proton
**Researched:** 2026-06-01

### Official stance: not supported

vkd3d-proton's
[README.md drivers section](https://github.com/HansKristian-Work/vkd3d-proton/blob/master/README.md#drivers)
lists driver support for AMD (RADV), NVIDIA, Intel. **macOS /
MoltenVK is not listed.**

Core contributor K0bin stated in
[issue #1889 (closed Feb 2024)](https://github.com/HansKristian-Work/vkd3d-proton/issues/1889):

> "VKD3D-Proton doesn't work on Mac OS because MoltenVK is missing
> a lot of features that D3D12 games actually rely on. Some of the
> most problematic ones are: Bindless (proper support for
> `VK_EXT_descriptor_indexing` or `VK_EXT_descriptor_buffer` +
> `VK_EXT_mutable_descriptor_type`), Sparse resources, [and]
> Vulkan memory model."

Closed without remedy or roadmap. **This is official upstream
position from Valve's project.**

### Required Vulkan features for ANY D3D12 device exposure

Per vkd3d-proton's
[README.md drivers section](https://github.com/HansKristian-Work/vkd3d-proton/blob/master/README.md#drivers):

- Vulkan 1.3
- `VK_EXT_descriptor_indexing` with **≥1,000,000 UpdateAfterBind
  descriptors of all types**
- "Essentially all features in `VkPhysicalDeviceDescriptorIndexingFeatures`
  must be supported."

### MoltenVK actual state vs. those requirements

Per
[MoltenVK Runtime User Guide](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md):

- `VK_EXT_descriptor_indexing` supported but **Tier 1 only**:
  **96–128 textures, 16 samplers**.
- MoltenVK
  [Whats_New.md](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md)
  notes "doesn't advertise extension if mandatory features are not
  supported".

**Gap: 128 textures vs. 1,000,000 required. Three orders of
magnitude.** Not a near-miss — fundamental Metal architecture
limit. Metal's argument-buffer Tier 2 in newer macOS may help; not
yet exposed by MoltenVK.

### Higher feature levels also missing

Per vkd3d-proton's
[PROFILES.md](https://github.com/HansKristian-Work/vkd3d-proton/blob/master/profiles/PROFILES.md):

- `VK_EXT_mesh_shader` — **not in MoltenVK**; required for FL_12_2
- `VK_KHR_ray_tracing_pipeline` + `VK_KHR_acceleration_structure`
  — **not in MoltenVK**; required for FL_12_2 (UE5 SM6 + Lumen + RT)
- `VK_EXT_shader_object` — **not in MoltenVK**

### Why our measured 0x80070057 is expected

vkd3d-proton cannot enumerate any D3D12 adapter because MoltenVK's
descriptor indexing Tier 1 fails the mandatory ≥1M requirement.
Returns `E_INVALIDARG`. Not a version bump or config issue.

### Recent activity

[Commits](https://github.com/HansKristian-Work/vkd3d-proton/commits/master):
No PRs in the last 6 months adding Apple Silicon or MoltenVK
support. Issue #1889 remains closed.

### Verdict for calimocho

vkd3d-proton path is **closed for the foreseeable future**. The
project's official maintainers have explicitly said "don't bother";
the gap is not in vkd3d-proton but in MoltenVK; MoltenVK's gap is
not in MoltenVK either, but in Apple Metal's exposed feature set
not matching what bindless-style D3D12 expects.

If anything moves this needle, it'll be Apple changing what Metal
exposes, then MoltenVK wrapping it, then vkd3d-proton consuming
it. None of those are calimocho work.

---

## 3. MoltenVK Apple Silicon caps — deeper dive

**Researched:** 2026-06-01 from
[MoltenVK Whats_New.md](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md)
and
[MoltenVK_Runtime_UserGuide.md](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md)
(both current as of latest release MoltenVK 1.4.2).

### Headline finding (changes section 2's verdict)

MoltenVK
[1.2.10 (July 2024)](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md)
made significant bindless improvements:

> **Improvements to bindless resources and descriptor indexing:**
>   • Add support for Metal 3 argument buffers.
>   • Support argument buffers on all platforms, when Metal 3 is available.
>   • Use Metal argument buffers by default when they are available.
>   • Support multiplanar images in Metal argument buffers.
>   • **Update max number of bindless buffers and textures per stage to 1M**, per Apple Docs.

This was almost two years ago at time of writing. The 1M-bindless
gap vkd3d-proton's K0bin cited in [#1889](https://github.com/HansKristian-Work/vkd3d-proton/issues/1889)
(Feb 2024) was closed five months later by MoltenVK 1.2.10 — **but
the vkd3d-proton stance has not been re-evaluated publicly since.**

This means our earlier "the bindless gap is fundamental and
unbridgeable" claim in section 2 needs revisiting. The Apple Silicon
Tier 2 argument buffers (M2 and later, including M3/M4) DO expose
1M bindless. The pieces may now exist in principle.

### Remaining gaps (still real)

MoltenVK's current supported-extension list ([`MoltenVK_Runtime_UserGuide.md`](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md))
DOES include `VK_EXT_descriptor_indexing` (with the qualifier
about Tier 1 vs Tier 2 still being conditional), but does **not** include:

- `VK_EXT_mesh_shader` (UE5 SM6.5 + Nanite preferred path)
- `VK_KHR_ray_tracing_pipeline`
- `VK_KHR_acceleration_structure`
- `VK_EXT_shader_object`

MoltenVK 1.4.1 (Nov 2025) added several K_KHR_maintenance extensions
and ongoing SPIRV-Cross work for mesh-shader-in-MSL. SPIRV-Cross
**can convert mesh-shader SPIR-V to MSL** (the MSL mesh-shader API
exists), but MoltenVK itself doesn't expose the Vulkan-side extension.
Inference: the conversion path is built but the public Vulkan-side
plumbing isn't wired up. May be closer than expected.

### Caveat on our earlier "Tier 1 only" reading

The MoltenVK userguide carries this note for `VK_EXT_descriptor_indexing`:

> "Initial release limited to Metal Tier 1: 96/128 textures, 16 samplers,
> except macOS 11.0 (Big Sur) or later, or on older versions of macOS
> using an Intel GPU, and if Metal argument buffers enabled in config."

So even before the 1.2.10 1M bump, Tier 1 was an "initial release"
floor, not a permanent state. On M-Series + Sonoma+, **with
`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=ALWAYS` set**, the runtime
should expose Tier 3 limits.

PK ships MoltenVK v37 (per the SPIRV-Cross version string) which is
the version in MoltenVK 1.2.10. That means **PK has the 1M bindless
support code in its MoltenVK** — but PK doesn't pass the
`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS` flag, so it might be running
in default mode.

### Open questions to answer next

- Does PK enable Metal argument buffers in MoltenVK config?
  (`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS` env or `VK_EXT_layer_settings`)
- If the bindless limit is now 1M, why does our measured
  vkd3d-proton-on-PK still error 0x80070057? Is it still bindless,
  or is it actually mesh-shader/RT/etc.?
- Has vkd3d-proton been retested on M-series since MoltenVK 1.2.10?
- What's the actual MoltenVK extension list at runtime under PK?
  We can query this directly.

### Verdict for calimocho

**Section 2's "closed for the foreseeable future" verdict may have
been wrong.** It might be the difference of one config flag (`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS_ALWAYS=1`)
between failing and working — or it might still fail on mesh shaders
/ RT, but at least we now know the **bindless** part is no longer
the showstopper it was in 2024.

This is the highest-priority research thread to follow up on.

---

## 4. CodeWeavers public source — d3d12 keywords

(pending research)

Plan: grep `crossover-sources-26.1.0.tar.gz` (the LGPL release we
already build from) for `d3d12`, `mesh_shader`, `accel_struct`,
`Metal`, `MoltenVK`. See what's released vs what's behind their
paywall.

---

## 5. gcenx wine-private — extra patches

(pending research)

Plan: clone https://github.com/Gcenx/wine-private, diff against
upstream Wine 10.0 tag. Catalog Mac-specific patches. Find anything
d3d12-relevant.

---

## 6. Recent web — r/macgaming, GoL, Phoronix, Discord

(pending research)

Plan: search "Subnautica 2 Apple Silicon", "UE5 SM6 Mac",
"vkd3d-proton MoltenVK 2025/2026". Look for any workaround
documented by community.

---

## 7. Apple GPTK 3.x D3DMetal — what we have vs latest

(pending research)

Plan: find Apple's latest GPTK release notes. Compare D3DMetal
version we bundle (from GPTK 3.0-3, March 2026) with whatever's
current as of June 2026.

---

## Synthesis

(filled in last)

---

## Bibliography (running)

- DXMT repo — https://github.com/3Shain/dxmt
- DXMT issue #163 (D3D12 out of scope) — https://github.com/3Shain/dxmt/issues/163
- DXMT 1.0 plan #151 — https://github.com/3Shain/dxmt/issues/151
- DXMT v0.80 — https://github.com/3Shain/dxmt/releases/tag/v0.80
- DXMT v0.70 mesh shaders — https://github.com/3Shain/dxmt/releases/tag/v0.70
- DXMT install guide — https://github.com/3Shain/dxmt/wiki/DXMT-Installation-Guide-for-Geeks
- DXMT device specs — https://github.com/3Shain/dxmt/wiki/Device-System-Runtime-Specifications
- vkd3d-proton repo — https://github.com/HansKristian-Work/vkd3d-proton
- vkd3d-proton README drivers — https://github.com/HansKristian-Work/vkd3d-proton/blob/master/README.md#drivers
- vkd3d-proton PROFILES.md — https://github.com/HansKristian-Work/vkd3d-proton/blob/master/profiles/PROFILES.md
- vkd3d-proton #1889 (macOS unsupported) — https://github.com/HansKristian-Work/vkd3d-proton/issues/1889
- MoltenVK repo — https://github.com/KhronosGroup/MoltenVK
- MoltenVK Runtime User Guide — https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md
- MoltenVK Whats_New.md — https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md

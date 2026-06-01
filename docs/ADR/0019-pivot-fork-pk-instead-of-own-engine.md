# ADR 0019: Pivot — fork PK Steambuild Direct3D instead of building our own engine

Status: Proposed
Date: 2026-06-01

## Context

Phase 1–3 of calimocho built a Wine 11 engine from CodeWeavers' LGPL
source, added a D3DMetal d3d11 shim (ADR-0015), and spent a session
trying to wire d3d12 (ADR-0016). Today's research (`docs/research/d3d12-foss-status-2026-06-01.md`)
and live testing produced a clearer picture:

### What we measured today

| Stack | Steam UI renders | SN2 D3D12 init | What blocked SN2 |
|---|---|---|---|
| PK **DXVK** (Wine 10 + DXVK 2.x + vkd3d-proton) | ✅ | ❌ | `D3D12CreateDevice 0x80070057` — vkd3d-proton+MoltenVK can't expose adapter on Apple Silicon |
| PK **Direct3D** (Wine 10 + Apple D3DMetal) | ✅ | ❌ (got stopped at Steam's vcrun gate) | Steam refused to launch SN2 because VC++ 2015-2022 Redistributable missing from PK Direct3D bottle |
| Our **calimocho** (Wine 11 + our D3DMetal shim) | ❌ black | n/a | Wine 11 winemac.drv composition path doesn't render Steam UI; our shim hangs on adapter from wined3d dxgi |
| **Calimocho + DXVK injection from PK** | ❌ still black | n/a | DXVK alone doesn't make Wine 11 winemac.drv render; the full PK stack (Wine 10 + gcenx wine-private patches + DXVK + winemac.drv) is what works |

### Key insight from the maintainer

PK Direct3D is **strictly better than DXVK** for our goals:

1. Steam UI renders (same as DXVK)
2. Has the only path to D3D12 (and thus SN2): Apple D3DMetal
3. The Steam-side block is **just vcrun missing** — Steam's pre-launch
   check requires the redistributable to be marked installed in
   registry. A registry edit + the DLL files (which winetricks
   partially installed earlier) closes that gate.

We've been trying to rebuild calimocho's engine to match PK. That's
~3-5 days of work to recreate something that already exists,
already works for the maintainer, and is already redistributable
(PK's "Steambuild 32 64bit Direct3D" is built on gcenx wine-private
+ Apple GPTK + Wineskin wrapper, all FOSS or redistributable per
their respective licenses).

## Decision

**Pivot calimocho from "build our own engine" to "ship a thin
wrapper around (or derivative of) PK's Steambuild Direct3D
variant".**

The new architecture:

```text
calimocho.app (our SwiftUI front-end, ADR-0006 scope)
        │
        │ first-run wizard installs / locates
        ▼
┌─────────────────────────────────────────────┐
│ PK Steambuild 32 64bit Direct3D.app          │
│   (gcenx wine-private 10.0)                  │
│   + Wineskin wrapper                         │
│   + Apple D3DMetal (GPTK 3.0+)               │
│   + bundled Steam install                    │
│   + bottle prep (vcrun + UE4SS + Sentry hack)│
└─────────────────────────────────────────────┘
        │
        │ launches
        ▼
   Subnautica 2 (D3D12 via D3DMetal)
```

Calimocho.app becomes:
1. **Detection**: is PK Direct3D installed? If no, walk user
   through the homebrew install (`brew install --cask gcenx/wine/...`).
2. **Bottle prep**: write the SN2 recipe registry (vcrun marker, UE4SS
   override, Sentry hack, Win11, AVX).
3. **Steam launcher**: open PK's bottle's Steam.exe.
4. **Status / diagnostics**: show what's installed, what's needed.

Calimocho **stops shipping its own Wine engine**.

## What this means for existing work

### Kept (still useful)

- `Calimocho/Sources/*.swift` — SwiftUI app shell, menubar, wizard
- `docs/ADR/0001–0012` — most still apply (build-from-source ethos,
  ad-hoc signing, GPTK redistribution rules, etc.)
- `docs/ADR/0017` — the "lead only when no FOSS exists" rule that
  enabled this pivot (we follow PK because PK exists and works)
- `docs/ARCHITECTURE.md` — top-level structure
- `docs/PHASES.md` — phase model

### Superseded (work to delete or archive in this branch)

- `docs/ADR/0013` — CW HACK 22434 env var — no longer set by us
- `docs/ADR/0014` — D3D shim ABI coupling — no shim anymore
- `docs/ADR/0015` — d3d11 shim implementation — deleted, PK handles d3d11
- `docs/ADR/0016` — dxgi shim required — never implemented, no longer needed
- `docs/ADR/0018` — DXVK pivot proposal — superseded by this ADR (D3DMetal better)
- `patches/wine/0003-rename-wineloader-id.patch` — not our wine anymore
- `patches/wine/0004-d3d11-d3dmetal-shim.patch` — deleted with shim
- `patches/wine/files/d3d11/` — deleted
- `tests/d3d11_shim/` — deleted
- `scripts/build-wine.sh`, `fetch-sources.sh`, `prep-build-deps.sh`,
  `patch-sources.sh`, `fixup-config-h.sh` — wine build scripts not needed
- `out/engine/` — our compiled Wine 11 not needed (PK ships its own)

### New work (Phase 4)

- ADR-0020: how calimocho detects/installs PK
- ADR-0021: SN2 recipe to apply to PK bottle (vcrun marker, UE4SS, Sentry, AVX)
- ADR-0022: legal/attribution implications of shipping a wrapper around PK
- Code: `Calimocho/Sources/PKBottleManager.swift` (detects PK, writes recipe)
- Update README decision table: "uses gcenx PK + GPTK; install via brew"

## Consequences

### Positive

- **Drastically less engine work.** No 3-5 day Wine 10 rebuild.
- **Calimocho stops shipping a Wine binary at all.** Reduces our
  redistribution surface to just the SwiftUI app + scripts.
- **Always up-to-date with gcenx + Apple.** When gcenx updates
  wine-private, when Apple updates D3DMetal, users get it via brew
  upgrade, not a calimocho release.
- **Honest positioning per ADR-0017.** PK exists. PK works for what
  we need (Steam UI + access to D3DMetal D3D12 path). We follow,
  we don't lead.
- **One small remaining piece to write our own**: the SN2 recipe
  (vcrun marker, UE4SS, Sentry hack, AVX, Win11) on top of PK.
  That IS calimocho's contribution.

### Negative

- **Heavier dependency on PK staying maintained.** If gcenx archives
  PK like Whisky was archived, we're stuck. Mitigation: README links
  to PK + brew install + gcenx GitHub.
- **No control over PK's choices.** If PK switches Wine version or
  drops a feature we need, we adapt.
- **Users have to install PK separately** (one-time `brew install`).
  Wizard guides them.

### Neutral

- **License story simplifies.** We redistribute much less: just our
  Swift code (MIT) + the SN2-recipe scripts. PK handles its own
  redistribution.

## Open question — the vcrun gate

PK Direct3D bottle, when launching SN2 via its bundled Steam UI,
shows: **"Microsoft Visual C++ 2015-2022 Redistributable (x64)"
required**. Today we did a partial `winetricks -q vcrun2022` install
that wrote some DLLs but left the registry markers Steam reads
incomplete.

The vcrun gate fix is small: write the same registry keys CrossOver
has (we already extracted them in session 4) into PK Direct3D's
bottle. Steam will then stop blocking, SN2 will get to its D3D12
init, and we'll see whether D3DMetal can carry it.

This is the next test, and it's a 10-minute fix.

## Related

- ADR-0017 — follow when FOSS exists; PK is FOSS-or-redistributable
  upstream that exists for the exact problem we have
- ADR-0011 — GPTK redistribution rules (we redistribute less now)
- `docs/research/d3d12-foss-status-2026-06-01.md` — the research
  that pointed us here
- PK Steambuild Direct3D: brew install via gcenx/wine

# ADR-0005: Bundle Apple GPTK D3DMetal directly in release artifacts

Status: Accepted
Date: 2026-05-31

## Context

To run DX12 games (like Subnautica 2) under Wine on Apple Silicon, the
Wine build needs Apple's `D3DMetal.framework`. Two delivery options exist:

1. **Bundle D3DMetal directly** in our release tarball / DMG.
2. **Download D3DMetal at install time** from a third-party mirror
   (typically `gcenx/game-porting-toolkit` GitHub releases).

Early drafts of the plan said "never bundle, always download". That was
based on the wrong assumption that GPTK is murkily licensed for
redistribution.

Reading Apple's actual GPTK SLA from the DMG (verbatim license, not
gcenx's repack) confirms:

- §2A iii: "distribute the Apple Software solely for non-commercial
  purposes"
- §2C: "the Framework in its entirety or any part of the Redistributables
  may be distributed separately from the Apple Software"

So bundling is explicitly allowed for non-commercial use, which calimocho
is.

## Decision

calimocho **bundles** the following directly inside release artifacts:

- `D3DMetal.framework` (the Framework, per §2C)
- Components from GPTK's `/redist` directory (per §2C)
- The verbatim copy of Apple's `License.rtf` from the original GPTK DMG,
  reproduced in `THIRDPARTY/Apple-GPTK/`

We do **not** modify the D3DMetal binary in any way (Apple's §2D
prohibits modification and reverse engineering).

We do **not** ship GPTK's Wine binaries (they're 2023-era Wine 7; we
build our own Wine 11 instead).

For the source of D3DMetal, we use Apple's official GPTK 3.0 DMG
directly when available, with gcenx's repack as a fallback if Apple's
download server is intermittently slow. Either way the binary is
identical.

## Consequences

### Positive

- One download for users (no second runtime download required).
- Releases are reproducible: the exact D3DMetal version is pinned to a
  specific GPTK release in our build script.
- Offline-friendly. Install does not require an extra trip to gcenx's
  server.
- Apple's licensing covers redistribution explicitly. No legal grey area.

### Negative

- DMG size grows by ~230 MB (D3DMetal Framework is roughly that size).
  Mitigated: macOS users are used to multi-hundred-MB DMGs for creative
  apps.
- We must keep up with Apple's GPTK updates manually. Mitigated: GPTK
  ships roughly once per quarter; our monthly cadence accommodates it.
- We are responsible for verifying the D3DMetal sha256 in our build
  script, so users can verify they got the binary we tested.

### Neutral

- gcenx remains a viable fallback source. We document this in the build
  log so future-us knows the workaround if Apple's CDN is down.

## Related

- ADR-0004 (non-commercial restriction the bundle inherits)
- LICENSE
- AGENTS.md rule #1 (exception for Apple GPTK D3DMetal)

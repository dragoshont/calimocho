# ADR-0001: Bundle CodeWeavers Wine 11, built from source

Status: Accepted
Date: 2026-05-31

## Context

We need a Wine runtime on macOS Apple Silicon that can:

- Run the current Steam client without rendering as a black window
- Run modern DX12 games via Apple's GPTK D3DMetal layer
- Stay maintained as upstream Wine and Apple's tooling evolve

Options surveyed:

1. **Upstream Wine 11 from gcenx** (free, public): proven binary, but the
   Cocoa-side rendering paths cannot draw Steam's embedded Chromium UI
   correctly without CodeWeavers' macdrv patches. Confirmed black-window
   in our own testing.
2. **Apple Game Porting Toolkit's bundled Wine** (free): GPTK 3.0-3
   bundles Wine 7.7 from 2023, which the current Steam client refuses to
   run on. Apple has never updated their bundled Wine.
3. **Whisky's bundled Wine** (free, archived): Wine 7.7. Same problem as
   GPTK's bundled Wine, plus Whisky has been in maintenance mode since
   May 2025.
4. **CrossOver binaries** (paid product): work perfectly. License does not
   permit redistribution outside CrossOver.app.
5. **CodeWeavers' LGPL Wine source** (free, public): same patches as in
   the paid CrossOver product, published per their LGPL compliance at
   https://media.codeweavers.com/pub/crossover/source/. We can build from
   source and ship the result.

## Decision

We build Wine 11.0 from CodeWeavers' published LGPL source tarball
(`crossover-sources-26.1.0.tar.gz`) and bundle the result as the Wine
runtime in calimocho.

The bundled artifacts include:
- `wine` (unified 64-bit binary)
- `wineserver`
- All winemac.drv and wined3d compiled libraries
- The Wine prefix template

## Consequences

### Positive

- We get the macdrv, wined3d, and CEF compatibility patches CrossOver users
  enjoy, without paying $74/yr per machine.
- LGPL means we can legally redistribute the result, modify it, and so on.
- CodeWeavers publishes new source within days of each CrossOver release,
  so we can track their work.

### Negative

- Build time is 30-45 minutes on M1 Max per release. Mitigated by GitHub
  Actions caching.
- We inherit any CodeWeavers bug. We do not have their internal test suite
  or support team.
- Build setup requires brewing several toolchain dependencies (bison, flex,
  mingw-w64, gnutls). One-time cost per machine.
- The first build hit an `EXEEXT` autoconf substitution issue on Apple
  clang 21. We will document the fix as part of Phase 1.

### Neutral

- We do not contribute patches upstream to either Wine or CodeWeavers
  (out of scope, see AGENTS.md).
- Our build is downstream of CodeWeavers. Their work is the value.

## Related

- AGENTS.md rule #1 (we compile from source)
- ADR-0007 (we never copy binaries)
- docs/PHASES.md Phase 1

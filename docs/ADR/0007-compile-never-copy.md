# ADR-0007: We compile from source. We never copy CrossOver binaries.

Status: Accepted
Date: 2026-05-31

## Context

When Phase 1 build hit an autoconf issue (`EXEEXT` undefined in the
generated `config.h`), the fast workaround would have been to copy
CrossOver's pre-built Wine binaries from
`/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/`
into Whisky's `Libraries/Wine/` and call it done. This is the same Wine
calimocho intends to build, after all.

That shortcut would have technically worked. It also would have
fundamentally broken the project.

## Decision

calimocho compiles Wine from source. Always. No exceptions for
"just this once" or "for testing".

The single exception is **Apple's GPTK D3DMetal.framework**, which is a
proprietary binary we redistribute under Apple's explicit GPTK SLA
permission. We never modify it.

## Consequences

### Positive

- We stay legally clean. CrossOver's binaries are licensed under their
  CrossOver EULA, which prohibits redistribution outside CrossOver.app.
- We can publish releases without fear of takedown.
- The project's purpose is intact: "build it yourself from source the
  upstream maintainers published".
- gcenx's stance is respected: he draws the line at not bundling
  CW-Wine + GPTK in a single drop-in. We cross his line, but only by
  doing the build ourselves from CodeWeavers' published source. Not by
  appropriating his work or CrossOver's binaries.

### Negative

- We have to actually fight through autoconf / build-system issues
  ourselves. The first one (`EXEEXT`) cost an hour. There will be more.
- Documented in `docs/build-log.md` so each fix is recorded once.
- CI build time is real: 30-45 min per release on M-series.

### Neutral

- Build failures are honest signal that the underlying source has a
  quirk worth understanding, not a bug to bypass.
- Future-us will be tempted to take the shortcut again. AGENTS.md rule #1
  exists to prevent that.

## Related

- AGENTS.md rule #1 (we compile from source, never copy binaries)
- ADR-0001 (bundle CodeWeavers Wine, built from source)
- ADR-0005 (bundle Apple GPTK D3DMetal, the one binary exception)
- docs/build-log.md (where we record each fix)

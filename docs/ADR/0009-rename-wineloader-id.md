# ADR-0009: Replace CrossOver wineloader bundle identifier

## Status
Accepted

## Date
2026-05-31

## Context

CodeWeavers' Wine source ships `loader/wine_info.plist.in` with three
identifiers (CrossOver Hack 10913) that hard-code CrossOver's branding
into every built `wine`:

- `CFBundleExecutable` = `wineloader`
- `CFBundleIdentifier` = `com.codeweavers.CrossOver.wineloader`
- `CFBundleName`       = `CrossOver-Hosted Application`

On macOS 26 (Tahoe), `AppleSystemPolicy` enforces a binding between
bundle identifiers under `com.codeweavers.*` and CodeWeavers' Developer
ID Team ID. An ad-hoc-signed Mach-O claiming
`com.codeweavers.CrossOver.wineloader` is killed at exec with no error
visible to the spawning process — only the kernel log records:

> ASP: Security policy would not allow process: .../wine

This affects every spawned Wine subprocess (the unix-side
`lib/wine/aarch64-unix/wine`). The CLI wrappers (`bin/wine --version`,
`--help`) survive because they exit before re-execing.

We hit this during Phase 1 A1.2 verification.

Independent of the technical kill, AGENTS rule #3 says we treat
CodeWeavers as an upstream we respect. Signing our own binary with
their bundle identifier is identity impersonation under the macOS code
signing model. Whether or not it boots, we shouldn't ship it.

## Decision

Rename the three identifiers in `loader/wine_info.plist.in` from the
`CrossOver / CodeWeavers` branding to calimocho-owned values:

- `CFBundleExecutable` = `wineloader` → `calimocho-wineloader`
- `CFBundleIdentifier` = `com.codeweavers.CrossOver.wineloader` →
  `app.calimocho.wineloader`
- `CFBundleName`       = `CrossOver-Hosted Application` →
  `Calimocho-Hosted Application`

The rename is delivered as `patches/wine/0003-rename-wineloader-id.patch`
and applied by `scripts/patch-sources.sh` (idempotent).

## Consequences

### Positive
- Wine subprocesses actually launch on macOS 26.
- We stop signing binaries with CodeWeavers' bundle identifier.
- The string `Calimocho-Hosted Application` will appear in
  `ps`/Activity Monitor instead of the misleading
  `CrossOver-Hosted Application`.

### Negative
- One more line of divergence from upstream to maintain at each
  CodeWeavers source drop. Cost is negligible: the plist template
  changes ~once per year.
- If any CrossOver-specific runtime code checks
  `CFBundleIdentifier == com.codeweavers.CrossOver.wineloader`, it will
  not match. None found in the Wine 11 / CrossOver 26.1 source tree
  at the time of writing. If one surfaces, write a reverse-ADR.

### Neutral
- The patch lives in `patches/wine/`, not in our repo's source tree.
  Our build output is still derived from CodeWeavers' published LGPL
  source plus a small named patch — AGENTS rule #1 holds.

## Related

- AGENTS.md rules #1 (compile from source) and #3 (respect upstream)
- ADR-0007 (compile, never copy)
- docs/build-log.md Phase 1 entry recording the symptom and fix

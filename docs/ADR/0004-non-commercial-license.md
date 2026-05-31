# ADR-0004: Non-commercial license for the distribution as a whole

Status: Accepted
Date: 2026-05-31

## Context

calimocho's own scripts and documentation could be released under any
license. However, the bundled artifacts in a release tarball include:

- Wine 11 with CodeWeavers patches: LGPL-2.1+
- vkd3d: LGPL-2.1+
- MoltenVK: Apache 2.0
- Apple GPTK D3DMetal.framework: Apple GPTK SLA, **non-commercial only**

The Apple GPTK license (§2A iii + §2C) explicitly allows redistribution
of the Framework, but only for non-commercial purposes (verified by
reading Apple's License.rtf in the GPTK 3.0 DMG).

This means any release tarball that bundles D3DMetal inherits the
non-commercial constraint. If we tried to commercialize, we would have
to either pay Apple for a separate commercial license (not available to
us) or strip D3DMetal from the release (which removes the DX12 path that
makes SN2 work).

## Decision

- The calimocho **scripts and documentation** are licensed under
  **LGPL-2.1-or-later**, matching Wine.
- The **distribution as a whole** (any release tarball, DMG, or app
  bundle that contains D3DMetal) inherits Apple's non-commercial
  restriction.
- The LICENSE file in the repo and a per-release `THIRDPARTY/` directory
  reproduce all upstream license texts, including Apple's GPTK SLA
  verbatim.
- For users who want to commercialize, README documents an escape hatch:
  build a calimocho variant without D3DMetal (use vkd3d-proton + DXVK +
  MoltenVK instead). DX12 perf is lower but the resulting bundle is
  fully permissive.

## Consequences

### Positive

- Legally clean. We are exercising rights explicitly granted by Apple's
  GPTK license and Wine's LGPL.
- The constraint matches our intent (we never wanted to commercialize
  anyway, per AGENTS.md rule #2).
- Anyone who wants a commercial path has a documented one (drop
  D3DMetal).

### Negative

- We can never sell calimocho or build a paid product on top of it.
- We cannot accept paid support contracts.
- We cannot include calimocho in any paid app, SaaS, or hosted service.
- Some donation platforms might raise eyebrows; we mitigate by directing
  donations to WineHQ and CrossOver instead of accepting them ourselves.

### Neutral

- Forks may exist under the same license. They inherit the same
  non-commercial constraint as long as they include D3DMetal.

## Related

- LICENSE file
- AGENTS.md rule #2 (non-commercial forever)
- ADR-0005 (bundle GPTK D3DMetal)

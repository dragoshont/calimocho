# ADR-0012 — LGPL compliance via written offer + reproducible source

## Status
Accepted

## Date
2026-06-01

## Context

calimocho ships binaries built from **Wine 11.0** (LGPL-2.1-or-later)
plus a small set of in-tree patches. LGPL §6 requires that any
recipient of the combined binary be able to obtain the **corresponding
source code** for the LGPL portion under the same license terms.

Three compliance models are available:

1. **Bundle source in the DMG.** Inflates the artifact by ~120 MB of
   tarball, half of which is generated parser output we'd have to
   ship anyway. Conflicts with A4.9 (250 MB DMG budget) and
   contributes nothing the next model doesn't already provide.
2. **Written offer + accessible source.** LGPL §6(b) explicitly
   permits offering the source separately, valid for ≥ 3 years from
   the binary release. Standard practice (Debian, Fedora, every
   commercial Wine distributor including CodeWeavers itself).
3. **Source on the same network server as the binary.** LGPL §6(d).
   Works for software-only distribution but unusual for desktop apps.

We pick **model #2** (written offer) with model #3's advantages
folded in (the source is always one click away on GitHub).

## Decision

Every calimocho binary release ships with a `NOTICE` file (in the
DMG and in the About box) that:

1. Identifies Wine 11.0 as the LGPL-2.1-or-later component
2. Names CodeWeavers as the upstream and links to their LGPL source
   distribution page
3. Pins the exact upstream tarball URL and sha256 we built from
   (these live in `versions.json` already)
4. Points at the calimocho git tag matching this release for the
   in-tree patches (`scripts/patches/*.patch`)
5. Provides a written offer good for 3 years to mail a USB stick
   with the corresponding source to anyone who asks at the email
   address in `LICENSE`

The combined inputs — upstream tarball (sha256-verified) +
`scripts/patches/` at the matching git tag — fully reproduce the
shipped Wine binaries. This satisfies "corresponding source" per
the LGPL FAQ.

We never modify upstream source files in-tree. All modifications
live as `.patch` files under `scripts/patches/`, applied by
`scripts/patch-sources.sh` at build time. This keeps the
"corresponding source" boundary unambiguous: original tarball +
patches = our binary, with no third location to audit.

## Consequences

### Positive
- DMG stays under 250 MB (A4.9 honored).
- Compliance is the same model CodeWeavers and Debian use — well
  understood and uncontroversial.
- Patches under `scripts/patches/` are reviewable in the GitHub UI,
  searchable, and diff against upstream cleanly.
- Each release tag (`vX.Y.Z`) immutably pins the exact patches that
  produced that release. Git's content-addressed history is the
  archive.

### Negative
- A user with no internet at all (rare for a Mac user installing
  Wine to play a Steam game) cannot trivially extract source from
  the DMG. The written offer covers this edge case at the cost of
  a USB stick.
- We commit to maintaining the upstream tarball URL working for
  3 years post-release. CodeWeavers has kept their `media.codeweavers.com`
  source URLs stable since at least 2019, but if a URL ever 404s
  we must mirror to a calimocho-controlled GitHub release.

### Neutral
- Adds `THIRDPARTY/Wine/NOTICE` (this file's payload) to the repo.
- Adds A4.10 to SPECS: the DMG must embed `NOTICE` at a
  user-visible path, and the About box must show or link to it.
- Phase 5 (`release.yml`) verifies `NOTICE` is present in the DMG
  before publishing.

## Related

- [ADR-0001](0001-bundle-codeweavers-wine.md) — why CodeWeavers source
- [ADR-0007](0007-compile-never-copy.md) — why we compile, never copy
- [docs/SPECS.md A4.10](../SPECS.md) — DMG NOTICE embedding criterion

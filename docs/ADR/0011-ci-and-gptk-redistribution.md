# ADR-0011: CI brought forward; calimocho re-hosts the GPTK Redistributables

## Status
Accepted

## Date
2026-06-01

## Context

PHASES.md originally scoped GitHub Actions CI to Phase 5. PR #1 (Phase
1 engine) closed with no CI; CodeRabbit and Copilot review found 13
issues that would have been caught deterministically by even a minimal
CI pipeline (path normalization, missing patches, broken
idempotency checks). Continuing without CI past Phase 1 puts AGENTS
rule #7 ("we test before we ship") in a single-point-of-trust state:
only the maintainer running `scripts/test-engine.sh` locally enforces
A1.x.

Independently, the existing pipeline assumed Apple's GPTK DMG
(`Game_Porting_Toolkit_3.0.dmg`, ~250 MB) would be present locally —
which is true for the maintainer but false for CI runners and for
external contributors. Apple gates the DMG behind an Apple ID login,
so we cannot `curl` it from CI.

**Re-reading the Apple GPTK SLA verbatim** (License.rtf mounted from
the DMG):

- §2A(iii): *"distribute the Apple Software solely for non-commercial
  purposes and in accordance with this Agreement, including Section
  2C."*
- §2C: *"all distribution of the Apple Software, including the
  Framework in its entirety and any individual Redistributables, are
  subject to the non-commercial restriction in Section 2(A)(iii). [...]
  the Framework in its entirety or any part of the Redistributables
  may be distributed separately from the Apple Software."*

The contents of `/redist/lib/external/` (`D3DMetal.framework` +
`libd3dshared.dylib`) are exactly "Redistributables" as defined in
§1.21. Apple explicitly grants the right to distribute them separately
for non-commercial purposes, which is what calimocho is.

So the GPTK-in-CI problem and the "calimocho needs to be installable
without a local DMG" problem have the same answer.

## Decision

### 1. Bring CI forward from Phase 5 to Phase 1.5 (pre-PR merge)

Add `.github/workflows/build.yml`:
- Runs on push to any branch and on every PR opened against main
- Single job on `macos-15` (Apple Silicon) runner
- Steps: prep-build-deps → fetch-sources → patch-sources → build-wine
  → overlay-gptk → sign-engine → test-engine
- Caches: `~/Downloads/cxwine-build/cx-sources.tar.gz` keyed on
  `versions.json` sha; brew formulae; `build/wine/` (after the first
  successful configure)
- Wall time target: ≤ 60 min cold, ≤ 15 min cached
- Fails the PR on any A1.x FAIL

PHASES.md updated: CI deliverables move from Phase 5 to a new
"Phase 1.5" sub-section. Phase 5 still owns auto-update (Sparkle),
release.yml, the visual regression baseline, and the multi-OS test
matrix — those genuinely belong with packaging.

### 2. Re-host the GPTK Redistributables on calimocho's GitHub Releases

`scripts/package-gptk-redist.sh` (new, maintainer-only) builds a
`gptk-redist-3.0-1.tar.zst` from the mounted DMG containing:
- `redist/D3DMetal.framework/` (verbatim, per §2A copyright clause)
- `redist/libd3dshared.dylib`  (verbatim)
- `redist/License.rtf`         (Apple GPTK SLA, verbatim per §2A)
- `redist/README.md`           (calimocho repack metadata, license
  attribution, repack version)

The tarball is uploaded as an asset on a GitHub Release tagged
`gptk-redist-<gptk-version>-<repack>`. `versions.json` holds the URL
and sha256 (single source of truth).

`scripts/fetch-sources.sh` downloads the tarball with sha256
verification, identical to how it handles `cx-sources.tar.gz`.

`scripts/overlay-gptk.sh` checks for the tarball first; falls back to
the mounted DMG only if the tarball is absent (maintainer iteration
path).

### 3. THIRDPARTY/ tree

`overlay-gptk.sh` copies `License.rtf` into `THIRDPARTY/Apple-GPTK/`
on every overlay run, so the calimocho repo's working tree always
contains the verbatim Apple GPTK SLA next to the redistributed
binaries. Required by §2A: *"reproduce on each copy of the Apple
Software or portion thereof, all copyright or other proprietary
notices contained on the original."*

### 4. Upstream watch CI

`.github/workflows/upstream-watch.yml` runs weekly (Mondays 09:00
UTC) + on-demand `workflow_dispatch`. Checks three sources:

- **CodeWeavers Wine source** — scrapes
  `https://www.codeweavers.com/crossover/source`, regex-matches the
  current tarball filename pattern `crossover-sources-X.Y.Z.tar.gz`,
  compares against `versions.json:.cx_sources.crossover_release`.
  CodeWeavers has no public API, no RSS feed, and their tarball
  directory listing returns 403; this page is the only stable
  surface they provide. If the regex stops matching, an
  `upstream-watch-broken` Issue is opened.
- **Apple GPTK** — queries `Gcenx/game-porting-toolkit` GitHub
  Releases API for the latest tag, compares against
  `versions.json:.gptk_redist.gcenx_upstream_tag`. gcenx repacks each
  Apple GPTK release within days; his tag is the most reliable signal
  of a new Apple drop. (Calimocho still uses Apple's own DMG as the
  D3DMetal source; gcenx is the notification signal only.)
- **Whisky** — queries the `Whisky-App/Whisky` repo `archived` field
  via API. AGENTS rule #3 says if Whisky resumes active development
  (`archived: false`), we reposition or archive calimocho. Pinned
  expected state is `archived: true` in `versions.json:.whisky.expected_archived`.

When a new version is detected the workflow opens a GitHub Issue
with a recipe ("how to adopt this version"). Idempotent: searches by
exact Issue title (open OR closed) and skips if it already exists, so
the maintainer can close an Issue and not have it re-spam every
Monday.

## Consequences

### Positive
- CI catches Phase 1.x-style script bugs deterministically. Future
  PRs run the full pipeline before merge.
- CI can build end-to-end on a fresh runner (no manual GPTK DMG step).
- External contributors can build calimocho without an Apple Developer
  ID just to download GPTK. The tarball is on the calimocho repo's
  Releases, public and permissionless.
- One-line `versions.json` bump rotates pinned upstream versions
  cleanly. Single source of truth across `fetch-sources.sh`,
  `package-gptk-redist.sh`, CI cache keys, and `upstream-watch.yml`.
- Upstream-watch removes the maintainer's burden of subscribing to
  RSS feeds, polling Apple's developer page, and remembering to
  check Whisky's archive status. New CodeWeavers/GPTK drops surface
  as Issues within ~1 week of release.
- AGENTS rule #3 (respect upstream) strengthened: the verbatim
  `License.rtf` ships next to every D3DMetal binary, both in the
  redist tarball and in the calimocho working tree
  (`THIRDPARTY/Apple-GPTK/`).

### Negative
- New maintainer responsibility: when Apple ships GPTK 3.1 (or any
  update), the maintainer must (a) download the new DMG, (b) run
  `package-gptk-redist.sh`, (c) upload to a new GitHub Release, (d)
  bump `versions.json`. Estimated ~10 minutes per Apple release;
  Apple's GPTK release cadence is ~yearly.
- GitHub Actions macOS arm64 minutes are free on public repos
  (calimocho is public) but have a quota. Build is ~20 min cold,
  ~5 min cached. Acceptable for the PR cadence we expect (rare).
- If Apple ever asks calimocho to stop redistributing the
  Redistributables — even though §2A(iii) and §2C permit it — we
  comply within days (AGENTS rule #3 "respect upstream").

### Neutral
- Adds four new files: `versions.json`, `scripts/package-gptk-redist.sh`,
  `.github/workflows/build.yml`, `.github/workflows/upstream-watch.yml`.
  Modifies `scripts/fetch-sources.sh` and `scripts/overlay-gptk.sh` to
  use `versions.json` as the source of truth.
- `scripts/overlay-gptk.sh` retains the local-DMG path as a fallback
  for the maintainer when iterating on `package-gptk-redist.sh`
  itself — important to avoid a chicken-and-egg loop.
- Upstream-watch scrapes HTML from codeweavers.com. If CodeWeavers
  changes their source page template, the regex breaks and we get an
  `upstream-watch-broken` Issue rather than silently missing releases.
  Acceptable tradeoff given that CodeWeavers has no machine-readable
  alternative.

## Related

- [ADR-0005](0005-bundle-gptk-d3dmetal.md) — bundle GPTK D3DMetal.
  This ADR makes ADR-0005 concrete by specifying the distribution
  channel (calimocho-hosted tarball vs maintainer-local DMG).
- [ADR-0007](0007-compile-never-copy.md) — we still compile Wine from
  source. The GPTK Redistributables are the one binary we redistribute
  unmodified, per §2A's explicit grant.
- [AGENTS.md rule #1](../../AGENTS.md) — "EXCEPTION: Apple's GPTK
  D3DMetal.framework is a binary we redistribute per Apple's explicit
  GPTK SLA permission (§2A iii + §2C, non-commercial)." This ADR
  operationalizes that exception.
- [PHASES.md](../PHASES.md) — Phase 1.5 added; Phase 5 narrowed.

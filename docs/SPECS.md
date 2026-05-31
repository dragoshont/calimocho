# calimocho SPECS

> What every component promises to do, including CLI surface, install
> layout, file paths, error codes, and per-phase acceptance criteria.
>
> Source of truth for "what does each part promise". Architecture (the
> "how") is in ARCHITECTURE.md.

## Glossary

- **Engine**: the bundled Wine 11 + GPTK D3DMetal + MoltenVK runtime
- **Bottle**: a Wine prefix (a directory simulating a Windows C: drive)
- **Host GUI**: the Mac-side app that wraps the engine
  - Phase 1+2: Whisky.app (third party)
  - Phase 3+: Calimocho.app (ours)

---

## Phase 1 specs: Steam works

### Phase 1 acceptance criteria (gates the Phase 1 → Phase 2 transition)

A1.1. `wine` binary in `Libraries/Wine/bin/` reports version `wine-11.0`
when invoked with `--version`
A1.2. `wineboot --update` against an existing Whisky bottle prefix
exits 0 and the prefix's `system.reg` has `wineVersion.major = 11`
A1.3. Steam.exe launches under the engine and produces at least one
visible window (not solid black) within 60 seconds
A1.4. User can type Steam credentials and see the Library view
A1.5. Subnautica 2 begins downloading from Steam (Steam shows
"Downloading" with a progress bar that advances)
A1.6. No file in `~/Library/Application Support/com.isaacmarovitz.Whisky/
Libraries/Wine/` was copied from `/Applications/CrossOver.app/`
(enforced by inspection: `find ... | xargs file` reports only Mach-O
binaries we compiled, identified by sha256 matching our build output)

### Phase 1 deliverables

- `bin/calimocho install` command that performs:
  1. Detects Whisky.app installed at `/Applications/Whisky.app`
  2. Backs up existing `~/Library/Application Support/
     com.isaacmarovitz.Whisky/Libraries/` to a timestamped backup
  3. Lays down our built Wine + GPTK D3DMetal as the new Libraries/
  4. Optionally runs `wineboot --update` on an existing bottle named
     `STEAM`
- `bin/calimocho rollback` command that restores the most recent backup
- Updated `docs/build-log.md` with build duration, configure flags,
  errors hit + fixes applied
- A working STEAM bottle the maintainer logs into

### Phase 1 CLI surface

```
calimocho install              # install engine into Whisky's Libraries
calimocho install --skip-wineboot
calimocho rollback             # restore most recent backup
calimocho status               # show installed engine version + bottle list
calimocho version              # print calimocho version
calimocho help                 # print usage
```

Exit codes:

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | general failure (see stderr) |
| 2 | usage error (bad flag, missing required arg) |
| 3 | Whisky.app not installed |
| 4 | Engine not built yet (run `calimocho build` first) |
| 5 | Backup creation failed (disk full, permission denied) |
| 6 | Wineboot failed |
| 7 | User aborted |
| 64-78 | Reserved (sysexits) |

### Phase 1 install file layout

```
~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/   ← our payload lives here
├── Wine/
│   ├── bin/
│   │   ├── wine          (calimocho-built, ad-hoc signed)
│   │   ├── wine64        (symlink → wine)
│   │   ├── wineserver
│   │   ├── wineserver64  (symlink → wineserver)
│   │   ├── wineboot      (symlink → wine)
│   │   └── ... (other tools, symlinks)
│   ├── lib/
│   │   ├── wine/
│   │   │   ├── i386-windows/
│   │   │   ├── x86_64-unix/
│   │   │   ├── x86_64-windows/
│   │   │   └── x86_32on64-unix/
│   │   └── external/                ← GPTK D3DMetal overlay
│   │       ├── D3DMetal.framework/
│   │       ├── libd3dshared.dylib
│   │       └── ... (other Apple redist)
│   └── share/
├── WhiskyWineVersion.plist          ← we write our calimocho version here
├── winetricks                       ← preserved from previous Whisky install
├── verbs.txt
└── DXVK/                            ← preserved
```

Backup format:

```
~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries.bak-YYYYMMDD-HHMMSS/
```

The most recent backup is symlinked at `Libraries.bak-latest` for
`rollback` discoverability.

---

## Phase 2 specs: SN2 works

### Phase 2 acceptance criteria

A2.1. Subnautica 2 finishes downloading from Steam (15 GB)
A2.2. SN2 reaches the main menu within 60 seconds of clicking Play
A2.3. The bottle's `d3d12.dll` is the GPTK D3DMetal one
(verified by `file` reporting larger size + Mach-O references to
D3DMetal.framework, not the wined3d stub)
A2.4. Gameplay sustains at least 30 FPS at 1080p Medium on M1 Max for
30 consecutive minutes
A2.5. Save data persists across game restarts
A2.6. UE4SS console (Ctrl+F2) opens in-game and accepts a test command
(`god` then off)
A2.7. Restarting the maintainer's Mac and re-launching SN2 still works
without re-configuration

### Phase 2 deliverables

- Documented bottle config:
  - Windows version: 10 (or 8.1 if needed for any client compatibility)
  - Enhanced Sync: ESync
  - D3DMetal: on
  - DXVK: off
  - AVX: on
- DLL overrides committed to bottle: `xinput1_3` = native,builtin (for
  UE4SS hook)
- SN2 game files migration script: if Subnautica2 is installed in the
  CrossOver bottle, calimocho v0.2 can copy or symlink the game into the
  STEAM bottle to avoid re-downloading 15 GB
- UE4SS + Console Commands mod installer script (the same recipe we used
  for CrossOver earlier today)
- Game-specific config snippets in `bottles/sn2/` directory in the repo

### Phase 2 CLI surface additions

```
calimocho bottle list          # show bottles
calimocho bottle config STEAM  # print bottle config
calimocho game install sn2     # install SN2 game files + mods + config into bottle
calimocho game launch sn2      # launch SN2 (kicks Steam + game)
```

---

## Phase 3 specs: Reproducible

### Phase 3 acceptance criteria

A3.1. A clean Apple Silicon Mac running macOS 15+ can download
`Calimocho-vX.Y.Z.dmg` from GitHub Releases, drag the .app to
/Applications, open it, complete the first-run wizard, install Steam,
log in, install SN2, and reach gameplay, following only README
instructions
A3.2. The DMG file is structurally valid (`hdiutil verify` exits 0)
A3.3. The Calimocho.app inside is ad-hoc signed (`codesign --verify`
exits 0 with no warnings about missing identifier)
A3.4. Every release artifact has a Sigstore signature uploaded alongside
(`cosign verify-blob --certificate-identity ...` exits 0)
A3.5. `.github/workflows/build.yml` runs successfully on every push to
main and produces a DMG as a workflow artifact
A3.6. `.github/workflows/release.yml` runs on every tag matching `v*`
and creates a GitHub Release with: DMG, sha256, Sigstore sig, source
tarball, release notes pulled from CHANGELOG.md
A3.7. The DMG size is between 400 MB and 800 MB (sanity bounds; outside
this range we investigate)
A3.8. Build is reproducible: building the same git ref twice produces
binaries with identical sha256 (modulo embedded timestamps; we set
`SOURCE_DATE_EPOCH` to commit time)

### Phase 3 deliverables

- `Calimocho.app` SwiftUI app (see APP-DESIGN.md)
- DMG installer (see USER-JOURNEY.md)
- `.github/workflows/build.yml` (lint + build + smoke test, runs on every push)
- `.github/workflows/release.yml` (tag-triggered: signed release + upload)
- `.github/workflows/test-matrix.yml` (weekly: build against
  macos-15 + macos-26 runners)
- Sigstore signature script
- Sparkle EdDSA-signed appcast at a public URL (initially a raw GitHub
  URL since we have no domain)
- README updated with the v1.0 install flow (download DMG, drag, open, wizard)
- Optional: Homebrew tap at `dragoshont/homebrew-calimocho` with one cask
  definition that downloads the DMG

### Phase 3 CLI surface additions

```
calimocho update               # check for new version, prompt install
calimocho selftest             # run smoke tests on installed engine
calimocho diagnose             # collect logs + write a redacted bundle for issues
calimocho uninstall            # remove engine, restore previous Libraries, optionally remove Calimocho.app
```

GUI surface (Calimocho.app menubar):

```
🍷 Calimocho v1.0.0

▶ Open Steam for Windows
─────────────────────────
About Calimocho
Quit Calimocho
```

Option-click (held when clicking menubar icon):

```
🍷 Calimocho v1.0.0

▶ Open Steam for Windows
─────────────────────────
⚙ Open Calimocho folder
⚙ View logs
⚙ Reinstall engine
⚙ Reset Steam bottle
⚙ Check for updates
─────────────────────────
About / Quit
```

---

## Cross-phase invariants

### Versioning

- Semantic versioning: `MAJOR.MINOR.PATCH`
- `0.x.y` until Phase 3 acceptance is met everywhere
- `1.0.0` when Phase 3 is fully shipped on a tagged release
- Tags are immutable; releases are GitHub Releases tied to tags

### File hashes published per release

- DMG sha256
- Tarball sha256
- Wine binary sha256 (allows users to verify their installed copy)
- D3DMetal binary sha256 (allows users to verify they got the same Apple
  binary we tested against)

### Logging

- All logs go under `~/Library/Logs/Calimocho/`
- Filename format: `calimocho-YYYYMMDD.log`
- One file per day, rotated
- `calimocho diagnose` collects the last 7 days + relevant Wine logs
  from the bottle into a single redacted zip

### Configuration

- User config in `~/Library/Application Support/Calimocho/config.json`
- Pinned versions in repo's `versions.json` (Wine source URL + sha256,
  GPTK source URL + sha256, MoltenVK version)
- No env-var-only configuration; everything has a documented config-file
  key

### Error messages

All user-visible error messages follow this template:

```
calimocho: ERROR <short title>
  Reason: <what happened, plain English>
  Fix:    <what to try>
  Docs:   https://github.com/dragoshont/calimocho/docs/troubleshooting.md
```

CLI errors go to stderr; GUI errors go to a dialog with the same fields.

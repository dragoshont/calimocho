# calimocho — Phase-Based Roadmap

> Locked 2026-05-31. This supersedes the ETA timeline in PLAN.md §12.
> Three phases, each with explicit success criteria.

## Overall philosophy

Three phases, each independently shippable. We do not start a phase until
the previous one meets its success criteria. We do not gold-plate; we
move on.

| Phase | Goal | Target completion |
|---|---|---|
| **Phase 1: Make Steam work** | The maintainer can launch Steam through a calimocho stack and log in. | Tonight, before sleep. |
| **Phase 2: Make the game work** | Subnautica 2 installs from Steam, launches, reaches gameplay. | Within days. |
| **Phase 3: Make it reproducible** | Anyone with a fresh M-series Mac can install from a DMG and reach gameplay. CI builds the DMG from scratch on push to main. | Within weeks. |

---

## Phase 1: Make Steam work

### Success criteria

- [ ] CodeWeavers Wine 11.0 builds successfully from their published LGPL source on the maintainer's M1 Max
- [ ] The built `wine64` binary runs and reports `wine-11.0`
- [ ] A Wine prefix initializes against the new binary without crashing
- [ ] Steam.exe launches under the new binary
- [ ] **Steam UI renders correctly (no black-window bug)**
- [ ] User can type credentials, log in, and see their Library
- [ ] Subnautica 2 install begins (15 GB download starts)

If the build fails or Steam UI still renders black, the fallback for tonight
is to stay on CrossOver and try again tomorrow. The maintainer is not
blocked from playing in either case (CrossOver trial is still active).

### Phase 1 deliverables

- `wine64` binary built from CW source, installed at
  `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/`
- A working `Steam` Whisky bottle that the maintainer can sign in to
- A short note in `docs/build-log.md` recording: build duration, configure
  flags used, any compile errors hit and how they were resolved, whether
  the Steam UI rendered correctly

### Phase 1 NOT in scope

- Any GUI work (Calimocho.app does not exist yet)
- Any DMG packaging
- Any CI work
- Any second-game testing
- Any signing beyond ad-hoc
- Documentation polishing

---

## Phase 2: Make the game work

### Success criteria

- [ ] Subnautica 2 finishes downloading from Steam (~15 GB)
- [ ] SN2 launches from the Steam Library and reaches the main menu
- [ ] D3DMetal is confirmed active (not falling back to wined3d)
- [ ] At least 30 minutes of gameplay possible without a Wine-side crash
  (intro crashes attributable to the game itself in Early Access do not count)
- [ ] FPS at least 30 on Medium settings, 1080p
- [ ] Save data persists between launches
- [ ] UE4SS / cheat mods installed in calimocho bottle (same recipe as we did
  for CrossOver earlier today) and Ctrl+F2 console works

### Phase 2 deliverables

- Documented bottle config for SN2 (Windows version, sync mode, DLL overrides)
- The CrossOver-installed SN2 game files reused (15 GB rsync into calimocho
  bottle, avoid second download)
- UE4SS + Console Commands mod installed with `xinput1_3.dll` proxy +
  registry override + Ctrl+F2 rebind, same way we did for CrossOver
- Phase 2 retro added to `docs/build-log.md`

### Phase 2 NOT in scope

- Anything beyond SN2 working
- DMG packaging
- CI

---

## Phase 3: Make it reproducible

### Success criteria

- [ ] A single GitHub Actions workflow runs on push to `main`
- [ ] The workflow checks out the repo, runs the build, produces a DMG
- [ ] The DMG passes basic structural validation (codesign --verify with ad-hoc check)
- [ ] The DMG is uploaded as a workflow artifact AND attached to GitHub Releases on tag
- [ ] A clean M-series Mac (Apple Silicon, macOS 15+) can download the DMG,
  open Calimocho.app, install Steam, launch Steam, see the Library
- [ ] Documentation explains the right-click → Open Gatekeeper bypass

### Phase 3 deliverables

- `Calimocho.app` SwiftUI menubar app (see APP-DESIGN.md)
- DMG installer with the engine bundled
- `.github/workflows/build.yml`
- `.github/workflows/release.yml`
- Sigstore signature on every release artifact
- Updated README with the user-facing install flow
- Cleaned-up `bin/calimocho` CLI for power users and the build script

### Phase 3 NOT in scope

- Apple notarization (no Developer ID)
- App Store distribution (not allowed for Wine apps)
- Heroic integration
- Phase 2+ games (they remain wishlist)

---

## Phase order is strict

Phase 1 must complete before Phase 2 starts.
Phase 2 must complete before Phase 3 starts.

If Phase 1 fails tonight, Phase 2 stays in CrossOver and Phase 1 retries
tomorrow with different approach (Wine 10 instead of 11, or specific CW
patches isolated, or alternative compile flags).

## Cross-phase invariants

- All work respects the positioning rules in `docs/PLAN.md §14`
- All artifacts respect the license terms in `LICENSE`
- All commits go to the public repo with honest commit messages
- All known issues go in `docs/build-log.md` so future-us understands the
  reasoning

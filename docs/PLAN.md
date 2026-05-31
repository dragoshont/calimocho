# calimocho — Product & Engineering Plan

> Living document. Edit freely as we learn. Version 0.1 — 2026-05-31.

## 1. Vision

**One sentence**: A free, open-source, self-installing Wine runtime for Apple Silicon
Macs that runs Steam + DX12 games as well as CrossOver does — built from CodeWeavers'
LGPL-published source, packaged respectfully, and reproducible by anyone with a
GitHub Action runner.

**Three audiences**:
1. **Power users** who already use Whisky and want a working engine.
2. **Casual gamers** who'd download a DMG, drag-and-drop, and play.
3. **Mac gaming ecosystem maintainers** (Heroic, Lutris-Mac, gcenx, etc.) who
   could consume our build as a dependency.

**Non-goals (v1)**:
- Not a CrossOver replacement on enterprise-grade game compatibility.
- Not a fork of Wine — we're a *distribution* layered on upstream + CW patches.
- Not building our own GUI from scratch (Whisky already has a good one).

## 2. Architecture (4 layers)

```
┌──────────────────────────────────────────────────────────────────┐
│ Layer 4 — UI                                                     │
│   • Phase 1: reuse Whisky.app GUI (we drop into its Libraries/)  │
│   • Phase 2: optional thin SwiftUI launcher (Calimocho.app)      │
│   • Phase 3 (stretch): Electron-based cross-tool launcher        │
├──────────────────────────────────────────────────────────────────┤
│ Layer 3 — Distribution                                           │
│   • Tarball release on GH Releases (~600 MB)                     │
│   • Notarized DMG with drag-to-Whisky-Libraries installer        │
│   • Homebrew tap: `brew install dragoshont/calimocho/calimocho`  │
│   • Optional: SparkleUpdater feed for auto-updates               │
├──────────────────────────────────────────────────────────────────┤
│ Layer 2 — Runtime payload (what's in the tarball)                │
│   • Wine 11.0 with CW patches  (the main thing)                  │
│   • vkd3d-proton (DX12 → Vulkan)                                 │
│   • DXVK (DX9/10/11 → Vulkan)                                    │
│   • MoltenVK (Vulkan → Metal)                                    │
│   • Apple GPTK D3DMetal.framework + libd3dshared.dylib           │
│   • Optional calimocho-specific patches (ours)                   │
├──────────────────────────────────────────────────────────────────┤
│ Layer 1 — Build pipeline                                         │
│   • Sources: CW + gcenx + Apple GPTK + upstream Wine             │
│   • Builders: GitHub Actions on macos-14 / macos-15 arm runners  │
│   • Output: signed + notarized tarball/DMG, release notes        │
└──────────────────────────────────────────────────────────────────┘
```

## 3. Build pipeline (GitHub Actions)

### Runners we have access to
GitHub-hosted **arm64 macOS** runners: `macos-14`, `macos-15` (Sequoia), `macos-26`
(once GA). Free tier: 50 min/month for arm64; **paid tier on your generous license:
~3000 min/month**. We need ~50 min per full build → comfortable budget for ~50
builds/month.

### Workflow surface

```yaml
.github/workflows/
  build.yml       # PR + main: build CW Wine + bundle deps + run smoke tests
  release.yml     # tag v* : sign + notarize + upload tarball + DMG
  lint.yml        # shellcheck + markdownlint + actionlint
  test-matrix.yml # nightly: test against multiple macOS versions
  refresh.yml     # weekly cron: pull new CW source + rebuild + open PR if diff
```

### Build job structure

```
build → cache CW source tarball (sha256)
      → cache brew bottles
      → cache configure result
      → make -j$(sysctl -n hw.ncpu)  (~40 min on M3)
      → assemble Libraries/ tree
      → overlay GPTK D3DMetal libs (downloaded from gcenx)
      → produce calimocho-libraries-v0.x.y-arm64.tar.zst
      → sha256 + sign tarball
      → upload as workflow artifact
```

### Caching strategy
- **CodeWeavers source tarball** (~150 MB): hash-keyed cache, swap on new release.
- **Brew bottles**: cached via `actions/cache` on `Brewfile.lock.json` hash.
- **Wine `./configure` output**: cached by `configure.ac` hash; saves ~3 min per run.
- **Built Wine objects**: cached by source-tarball-hash; full build only on source change.

End state: an unchanged-source rerun finishes in ~5 minutes from cache.

## 4. Bringing our own patches

The repo has a **`patches/`** directory layered on top of CW's source:

```
patches/
  0001-fix-broken-thing.patch
  0002-our-tweak.patch
  ...
  README.md  # what each patch does and why
  apply.sh   # idempotent applier
```

Patch flow:
1. Build script extracts CW tarball into `build/sources/`.
2. `patches/apply.sh` runs `patch -p1 -i ...` for each in order.
3. Any patch failure → fail the workflow (caught in PR review).

Initial patch candidates (from today's findings):
- Maybe none for v0.1 (start with vanilla CW + see if it Just Works)
- If Steam still has issues: investigate macdrv input/clipping patches
- If SN2 needs help: targeted DX12-to-Metal shader hooks

## 5. Testing strategy

### Tiers

| Tier | What | Where | Frequency |
|---|---|---|---|
| **Tier 0 — Lint** | shellcheck, actionlint, markdownlint, basic YAML validation | Every push | ~30s |
| **Tier 1 — Build sanity** | `wine64 --version`, `wineboot` smoke test, prefix creation | Every PR | ~45 min |
| **Tier 2 — Application smoke** | Launch `notepad.exe`, `cmd.exe`, headless screenshot to confirm window draws | Every PR | ~5 min added |
| **Tier 3 — Steam UI** | Launch Steam.exe + verify login window pixels (compare against baseline screenshot) | Every PR | ~10 min added |
| **Tier 4 — Game launch** | Launch a free DX11 + DX12 game, verify reach main menu (free titles: e.g. War Thunder DX11, Beneath the Waves demo for DX12) | Nightly cron | ~30 min |
| **Tier 5 — Regression suite** | Snapshot test full Libraries/ tree (hash-by-file) so any unintentional change shows up in PR review | Every PR | ~30s |

### Test infra notes
- Use macOS arm64 GH Actions runners (`macos-15` and `macos-26`).
- Steam needs a logged-in account — use a dedicated **calimocho-ci@** Steam account (free, no games purchased, exists only to verify login UI renders).
- Visual regression: `screencapture` → ImageMagick pixel diff against committed baseline. Tolerance for anti-aliasing.
- Headless game launch: use `Xvfb`-style virtual display... wait, macOS doesn't have that. Use **real but offscreen** Metal layer.

### Manual test matrix
Doc in `docs/manual-test-matrix.md` tracking which games are confirmed working
across releases. Community PR-able.

## 6. UI strategy (phased)

### Phase 1 (v0.1) — CLI + Whisky
Just `calimocho install` / `rollback`. Users continue to use Whisky.app for
bottle management. **This is enough for our family use case.**

### Phase 2 (v0.5) — Optional native shell
Tiny SwiftUI menubar app (`Calimocho.app`) that:
- Detects whether calimocho is installed in Whisky's Libraries/
- Shows current version + update available indicator
- One-click "Install / Update / Rollback"
- "Open Whisky" button

~300 lines of Swift. Distribute alongside main DMG.

### Phase 3 (v1.0+ stretch) — Electron unified launcher
If we ever feel ambitious: an Electron app combining bottle management, game
library, mod manager. This is **Heroic Games Launcher** territory and probably
not worth competing with. Better to **contribute calimocho engine support to
Heroic** so they can use us as a backend.

**Verdict**: Phase 1 ships. Phase 2 if it's fun. Phase 3 = collaboration with
existing launchers.

## 7. Distribution

### v0.1 channels
1. **GitHub Releases tarball** — primary. `tar -xzf` into Whisky's Libraries/.
2. **One-shot install script** — `curl -fsSL https://calimocho.dev/install | sh` (we don't own the domain yet; use raw GH URL initially).
3. **Manual download from README** — for paranoid users.

### v0.5 channels
4. **DMG** — drag-to-Applications model. The DMG mounts an installer app that
   does the Libraries/ swap and shows a progress bar.
5. **Homebrew cask** — `brew install --cask dragoshont/tap/calimocho`. Maintained
   in our own tap initially; **don't** PR to homebrew-cask until we have ~500 stars
   + 6 months of stable releases (homebrew-cask is picky).

### v1.0+ channels
6. **Sparkle auto-updater** built into the optional menubar app.
7. **Apple-notarized DMG** distributed without scary "unidentified developer" warnings.

## 8. Signing & notarization

**The honest situation:**
- Self-signing with ad-hoc certs: free, works locally, triggers Gatekeeper warning.
- Apple Developer ID (~$99/year): clean, no warnings, can notarize.
- Certificate revocation: Apple *can* revoke if they decide our binary is malicious.
  Wine-on-Mac has historically been safe in this regard (Whisky, CrossOver, Wineskin
  all run notarized for years).

### Recommendation
- **v0.1**: ad-hoc signed, document the "first-launch right-click → Open" workaround.
- **v0.5**: spend the $99 for an Apple Developer ID if user count exceeds ~50/month.
- **v1.0**: full notarization via `notarytool` in the release.yml workflow.

Apple Developer ID is **separate from publishing to App Store** — we don't need to
submit to App Store (we couldn't anyway since Wine ships its own JIT compiler which
violates App Store rules).

## 9. Quality bars per phase

### v0.1 — "It works for me"
- Steam UI renders without black-window bug
- One DX11 game runs (e.g. War Thunder, free)
- One DX12 game runs (Subnautica 2, our north star)
- Install + rollback both work, both idempotent
- README is honest about limitations
- LGPL-compliant attribution
- Tagged release with `.tar.gz` artifact

### v0.5 — "It works for friends"
- 5+ games confirmed working (community PR'd)
- Visual regression CI green
- Auto-update banner in menubar app
- Notarized DMG
- ~100 GitHub stars / actual users

### v1.0 — "It works for strangers"
- 30+ games confirmed working
- Tier 4 nightly game tests passing for 30 days straight
- Homebrew cask accepted upstream
- Apple notarization automated
- Documented contributor guide so others can submit patches
- ~1000 stars / Hacker News post / mentioned in macOS gaming guides

## 10. Risks & mitigations

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| CW changes their source license / withdraws publication | Very low | Catastrophic | Mirror tarballs in our own GH releases as evidence-of-state under fair use |
| Apple revokes Developer ID | Low | High | Have ad-hoc signing as fallback always documented |
| GPTK 3 D3DMetal license changes | Low | Catastrophic for DX12 | Document a Vulkan-only fallback (slower but works) |
| Build breaks on macOS 27 (next year) | Medium | Medium | macOS-version-matrixed CI catches it before users see it |
| Steam keeps breaking with new CEF versions | Medium | Medium | Pin to a known-good Wine, document the upgrade dance |
| Anti-cheat games still won't work | Certain | Low (not in scope) | Document loudly in README that competitive multiplayer is out of scope |
| We get a cease-and-desist from someone | Very low | Medium | We're squeaky clean LGPL; if it happens, comply + document |
| Burnout — me — solo maintainer | High | High | Keep scope tight, accept community PRs early, never promise SLA |

## 11. Repo structure (target)

```
calimocho/
  README.md                  # the pitch
  LICENSE                    # LGPL 2.1+
  CONTRIBUTING.md            # how to send patches/PRs
  CODE_OF_CONDUCT.md         # standard contributor covenant
  SECURITY.md                # how to report vulnerabilities

  bin/
    calimocho                # main CLI (install/rollback/build/package)

  scripts/
    fetch-sources.sh         # download CW tarball + GPTK + verify hashes
    apply-patches.sh         # patch -p1 -i patches/*.patch
    build-wine.sh            # ./configure && make
    assemble-libraries.sh    # tar the result for distribution
    release.sh               # tag + create GH release with assets
    install-local.sh         # one-shot for end users (the curl|sh target)
    rollback.sh              # restore most recent Libraries.bak

  patches/
    README.md                # what each patch does
    0001-*.patch ...
    apply.sh

  tests/
    smoke/
      wine-version.sh
      wineboot.sh
      notepad-launch.sh
    visual/
      baseline/
        steam-login-window.png
        ...
      compare.py
    games/
      war-thunder.sh
      subnautica2.sh

  .github/
    workflows/
      build.yml
      release.yml
      lint.yml
      test-matrix.yml
      refresh.yml
    ISSUE_TEMPLATE/
      bug.yml
      game-compat-report.yml

  docs/
    build-log.md             # what we did this session
    architecture.md          # the diagram from §2
    contributing-patches.md
    game-compatibility.md
    manual-test-matrix.md
    troubleshooting.md

  ui/                        # phase 2: SwiftUI menubar app
  electron/                  # phase 3: never, probably

  Brewfile                   # build deps
  Brewfile.lock.json         # version pins
```

## 12. Roadmap milestones

| Milestone | Scope | ETA |
|---|---|---|
| **v0.0.1** | Repo scaffold (done today) | 2026-05-31 ✅ |
| **v0.1.0** | First working local build, manual install via tarball | 2026-06 |
| **v0.2.0** | GitHub Actions builds + uploads tarball on release | 2026-06 |
| **v0.3.0** | DMG installer, ad-hoc signed | 2026-07 |
| **v0.4.0** | Visual regression CI for Steam UI | 2026-07 |
| **v0.5.0** | Menubar app, basic notarization | 2026-09 |
| **v1.0.0** | Stable, notarized, 30+ games confirmed, Homebrew cask | 2026-12 |

## 13. Open questions for you

1. **Apple Developer ID** — willing to spend $99/year if calimocho takes off?
2. **Domain** — want `calimocho.app`? It's $30/year. Optional, raw GH URL works.
3. **Scope creep** — happy to draw the line at "Whisky engine swap" forever, or
   do you want to grow toward full launcher / multi-tool?
4. **Maintenance cadence** — daily? Weekly? "When I feel like it"? Worth setting
   expectations in README upfront.
5. **Visibility plan** — silent launch (just for family + GH stargazers) or
   active promotion (Mac Reddit / HN / blog post)?

## 14. Today's next concrete step

Kick off the local build of CW Wine 11. Workstream:

```bash
cd ~/Downloads/cxwine-build/sources/wine
brew bundle --file=- <<EOF
brew "bison"
brew "flex"
brew "mingw-w64"
brew "gnutls"
brew "freetype"
brew "sdl2"
brew "gstreamer"
brew "pkg-config"
brew "cmake"
EOF
./configure --prefix=$HOME/Repo/calimocho/build/wine-prefix \
            --enable-archs=x86_64,i386 \
            --without-x \
            --disable-tests \
            --with-mingw 2>&1 | tee /tmp/cx-configure.log | tail -30
```

If configure exits clean → `make -j10` (~40 min).
If configure complains → install missing dep, rerun.

Once we have a `wine64` that runs, do steps 3-17 from §3 of this plan, copy
findings into `docs/build-log.md`, commit, push.

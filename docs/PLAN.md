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
| **Tier 4 — Game launch** | Launch a free DX11 + DX12 game, verify reach main menu (free titles: e.g. War Thunder DX11, Beneath the Waves demo for DX12) | **Weekly** cron (not nightly — keep CI minutes low) | ~30 min |
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
4. **DMG** — drag-to-Applications model. **Ad-hoc signed only** (`codesign --sign -`).
   Document the right-click→Open Gatekeeper workaround.
5. **Homebrew cask (in our own tap)** — `brew install --cask dragoshont/tap/calimocho`.
   **Never** PR to homebrew-cask upstream (would require notarization we can't afford).

### v1.0+ channels
6. **Sparkle auto-updater** built into the optional menubar app.
   (Works fine with ad-hoc signing as long as we use EdDSA signatures for the
   appcast — Sparkle's signature mechanism is independent of Apple's.)
7. **Sigstore/cosign provenance** for every release artifact, so security-minded
   users can verify the binary came from our GitHub Actions runner.
8. *Skipped intentionally*: full Apple notarization (would require Developer ID).

## 8. Signing & provenance

**Locked decision: ad-hoc signing only, forever.** ($99/yr Apple Developer ID is
out of budget; Azure Code Signing doesn't apply to macOS.)

### What we ship
- All Mach-O binaries inside the tarball/DMG are **ad-hoc signed** via
  `codesign --force --deep --sign - --options runtime <path>` so they at least
  satisfy the strictest Gatekeeper check (TCC, library validation, etc.).
- The DMG itself is **not** notarized — first-launch users see Gatekeeper's
  "unidentified developer" dialog. We document the **right-click → Open** workaround
  (or `xattr -d com.apple.quarantine`) prominently in README.
- Every release tarball/DMG has a **sigstore/cosign signature** generated by
  GitHub Actions' OIDC token, uploaded as `.sig` next to the artifact. Users can
  `cosign verify-blob --certificate-identity ... calimocho-v0.x.y.tar.gz` to
  confirm provenance without trusting our PGP keys (we don't have any).

### What we don't ship
- ❌ Notarization (no Developer ID)
- ❌ App Store distribution (Wine's JIT violates App Store rules anyway)
- ❌ Custom CA signing schemes (Gatekeeper would ignore them — no point)

### Honest user impact
First install is slightly more friction than CrossOver. Once a binary is allowed
once, macOS remembers it. Auto-updates via Sparkle work fine with ad-hoc signed
update bundles as long as the appcast itself is EdDSA-signed (Sparkle's own
signature, independent of Apple's chain).

## 9. Quality bars per phase

### v0.1 — "It works for me"
- Steam UI renders without black-window bug
- One DX12 game runs (Subnautica 2, our north star)
- Install + rollback both work, both idempotent
- README is honest about limitations
- LGPL-compliant attribution
- Tagged release with `.tar.gz` artifact
- **Out of scope for v0.1**: DXVK, vkd3d-proton, DXMT, BattleNet, GStreamer.
  Minimum payload only.

### v0.5 — "It works for friends"
- 5+ games confirmed working (community PR'd)
- Visual regression CI green
- Auto-update banner in menubar app
- Notarized DMG
- ~100 GitHub stars / actual users
- **DXMT and vkd3d-proton optional add-ons available** as alternative DX paths
  (open-source insurance for the day Apple changes GPTK terms).

### v1.0 — "It works for strangers"
- 30+ games confirmed working
- Tier 4 weekly game tests passing for 60 days straight
- Own Homebrew tap (not upstream)
- Sigstore provenance on every release
- Documented contributor guide so others can submit patches
- **Decision point**: do we build our own full launcher GUI, or focus on
  contributing calimocho-engine support upstream to Heroic Games Launcher?
- Silent launch — no HN/Reddit promotion; growth purely organic / word-of-mouth.

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
| **v0.1.0** | First working local build, manual install via tarball, **ad-hoc signed** | 2026-06 |
| **v0.2.0** | GitHub Actions builds + uploads tarball on release, **Sigstore signatures** | 2026-06 |
| **v0.3.0** | DMG installer (ad-hoc signed, documented Gatekeeper bypass) | 2026-07 |
| **v0.4.0** | Visual regression CI for Steam UI | 2026-08 |
| **v0.5.0** | SwiftUI menubar app, Sparkle auto-updater (EdDSA-signed appcast) | 2026-10 |
| **v0.6.0** | Own Homebrew tap (not upstream homebrew-cask) | 2026-11 |
| **v1.0.0** | Stable, 30+ games confirmed, decision on Heroic integration vs own launcher | 2027-Q1 |

**Cadence**: ~monthly releases tracking CodeWeavers source updates. No SLA.

## 13. Product decisions (locked 2026-05-31)

1. **Apple Developer ID** — ❌ no ($99/yr not in budget).
   - **Signing approach**: ad-hoc only (`codesign --sign -`).
   - **Cryptographic provenance**: GitHub OIDC + Sigstore/cosign signatures alongside,
     for users who want to verify build provenance independently of Gatekeeper.
   - Note: Azure Code Signing only covers Windows Authenticode — does *nothing*
     for macOS Gatekeeper. There is no free Apple-trusted CA path. Document the
     "right-click → Open" workaround prominently in README.
2. **Domain** — ❌ no. Use raw GitHub URLs for everything
   (`raw.githubusercontent.com/dragoshont/calimocho/main/...`).
3. **Scope** — ✅ **full launcher** is in scope, but phased.
   - v0.1–v0.4: engine swap only (CLI + Whisky.app GUI).
   - v0.5+: native menubar app for install/update/rollback.
   - v1.0+: investigate whether to build our own bottle/library manager or
     contribute calimocho-engine support to Heroic Games Launcher.
   - Decision review at v1.0: ship our own or partner.
4. **Maintenance cadence** — **monthly**. README should say:
   > Releases follow a roughly monthly cadence (CodeWeavers ships ~1-2 source
   > updates / month, we rebuild on top). No SLA, best-effort, may pause for
   > weeks if life happens.
5. **Visibility** — **silent**. No active promotion. Just exists on GitHub for
   anyone who finds it. No HN post, no Reddit thread, no blog. If a community
   forms organically, great; if not, also great.

### Implications for the plan
- **Reduce CI cost**: no need for nightly game tests at full scale; weekly is fine.
- **No notarization workflow**: skip Apple `notarytool` integration; replace with
  Sigstore signature workflow.
- **No domain**: all links in README use `github.com/dragoshont/calimocho`.
- **Roadmap shift**: v0.5 "menubar app" stays, v1.0 "Homebrew cask" downgraded
  to optional, never publish to homebrew-cask upstream (low maintenance burden).
- **README tone**: explicitly low-key. "Use at your own risk, no support, family
  project shared in public."

## 14. Ecosystem positioning

calimocho exists in a small, friendly ecosystem of macOS Wine projects. Being a
good neighbor matters more than market share. Specifically:

### License landscape (verified from actual EULAs, 2026-05-31)

| Component | License | Distribution permitted? |
|---|---|---|
| **Wine 11.0 (upstream)** | LGPL 2.1+ | ✅ Yes, any use including modification |
| **CodeWeavers Wine patches** | LGPL 2.1+ (CW's LGPL compliance source) | ✅ Yes, any use including modification |
| **vkd3d / DXVK / MoltenVK** | LGPL / zlib / Apache 2.0 | ✅ Yes |
| **Apple GPTK 3.0 D3DMetal.framework** | Apple GPTK Software License Agreement | ✅ **Non-commercial distribution allowed** per §2A(iii) + §2C |
| **Apple GPTK /redist components** | Same | ✅ Same — individual Redistributables can be distributed |
| **gcenx repacks** | Pass-through (no extra license added) | ✅ They're exercising the underlying upstream rights |

**Key takeaway for calimocho**: All components we want to ship are **legally
redistributable for non-commercial use**. The single hard constraint is
the **non-commercial** clause on Apple's GPTK — it forecloses any commercial
product (paid SaaS, paid app, paid support contract) but does NOT prevent
free open-source distribution, GitHub Sponsors funding, or community use.

**Why CrossOver can charge $74/yr and we can't**: CodeWeavers has a private
commercial agreement with Apple (they're a named partner on Apple's GPTK
page). The public GPTK license is non-commercial only; CodeWeavers operates
under a separate paper.

### Who's already in this space

| Project | Maintainer | Scope | Status |
|---|---|---|---|
| **CrossOver** | CodeWeavers, Inc. | Commercial product, polished GUI + curated profiles + support | Active, paid ($74/yr) |
| **Whisky** | Isaac Marovitz | Free SwiftUI GUI over Wine 7 + GPTK 1 | **Archived May 2025** |
| **Heroic Games Launcher** | Flavio Lima et al. | Multi-store (Epic/GOG/Amazon) game launcher; delegates engine to gcenx | Active |
| **Wineskin / Kegworks** | Gcenx | App-bundle wrappers around community Wine builds | Active |
| **gcenx/macOS_Wine_builds** | gcenx | Tarballs of upstream Wine 11.x for macOS | Active, key dependency |
| **gcenx/game-porting-toolkit** | gcenx | Repacks of Apple's GPTK D3DMetal as redistributable tarballs | Active, key dependency |
| **gcenx/winecx** (now deleted) | gcenx | *Used to* host wine-crossover builds | **Stopped at CW 23.0.1 (Nov 2023)** |
| **DXMT** | 3Shain | Open-source DX10/11 → Metal translator (no Vulkan layer) | Active, used by Heroic |
| **DXVK** | doitsujin | DX9/10/11 → Vulkan, cross-platform | Active, mature |
| **vkd3d-proton** | Valve / Hans-Kristian Arntzen | DX12 → Vulkan, mature on Linux, OK on Mac via MoltenVK | Active |
| **MoltenVK** | KhronosGroup | Vulkan → Metal | Active, baseline tech |

### The gap calimocho fills

gcenx explicitly declined to bundle CrossOver-patched Wine **together with** GPTK
D3DMetal in a single drop-in package (see
[Heroic issue #3372](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/3372)).
His stated reason: he doesn't want to undercut CodeWeavers' paid product, since
for casual users a free "CW-Wine + GPTK" bundle would functionally equal
CrossOver minus the polish/support.

calimocho **does** bundle them, on the principle that:
- The components are individually free + LGPL/redistributable
- Users who want polish + support should still buy CrossOver
- The gap should exist for users who can't afford CrossOver and don't have
  the time to manually assemble the pieces from 4 different repos

### Positioning rules

1. **Always credit gcenx upfront.** Every release note, every README section,
   the install script's banner — acknowledge that calimocho depends on
   his builds and would not exist without them. He's the unsung hero of
   macOS Wine.
2. **Always credit CodeWeavers + link to CrossOver purchase page.** Anywhere
   we mention Wine 11 source, mention it came from CW. README has a "please
   buy CrossOver if you can afford it" callout (already done).
3. **Never advertise as "free CrossOver alternative".** Frame as "Whisky's
   missing engine update." That's a much smaller, more honest niche.
4. **Bundle GPTK D3DMetal in our release tarballs** with Apple's License.rtf
   alongside. Apple's GPTK 3.0 license (§2A iii + §2C) explicitly permits
   non-commercial redistribution of the Framework and Redistributables. We're
   non-commercial → we're allowed. (Earlier drafts of this plan said to download
   from gcenx at install time "to be safe" — that was over-cautious. Direct
   bundling is simpler and more reliable.)
5. **Never PR "please add calimocho as engine option" to Heroic.** They
   delegated the engine to gcenx; injecting ourselves between them would
   create awkward dynamics. If Heroic users want calimocho, they can
   install it manually — we're upstream of Heroic's concerns.
6. **Never disparage gcenx's decision to stop at CW 23.** His reasons are
   ethical and we respect them; we just made a different call.
7. **Never claim to fix DXMT/DXVK/Wine bugs that should go upstream.** If
   we find a real bug, file it with the right project + link from our patch.
8. **Quietly mirror the build recipes, never the binaries** — except for our
   own ad-hoc-signed Wine build, which is the actual *value-add* of calimocho.

### How we'd react if any maintainer asks us to change something

- **gcenx says "please stop"** → We comply. The whole project is downstream of
  his work; we have no leverage to push back, and frankly we shouldn't want any.
- **CodeWeavers files a complaint** → Very unlikely (we're squeaky LGPL),
  but if they do: comply, talk it through, adjust.
- **Whisky maintainer comes back from hiatus and revives the project** →
  We immediately update README to point to Whisky as the preferred path,
  and reposition calimocho as a temporary stopgap or shut down entirely.
- **Heroic adds first-class CW-Wine+GPTK support themselves** → We point
  users there and archive calimocho.

The project exists because of a gap; if the gap closes, calimocho's job is done.

### How we minimize harm to CodeWeavers (8 levers)

We **cannot** fully avoid undercutting CrossOver — any free alternative will
convert *some* potential buyers into non-buyers. But we can minimize harm and
actively redirect goodwill upstream. Eight concrete levers we commit to:

1. **Be visibly worse on purpose (by honesty, not sabotage).** README states
   we lack support, per-game profiles, anti-cheat, notarization, day-of
   patches, polish. Users who need those things self-select to CrossOver.
2. **Pre-purchase funnel.** README has a decision table; for most rows the
   answer is "buy CrossOver." calimocho is the answer only for narrow
   non-commercial cases.
3. **Co-promotion in release notes.** Every GH release tagline includes
   "if this saves you time, please support CodeWeavers."
4. **Donate up the chain.** README's only donate links go to WineHQ +
   CrossOver purchase page. No calimocho donations accepted.
5. **Intentional release lag.** Wait 1–2 weeks after each CrossOver release
   before publishing our rebuild. Paying users always get the fresh bits first.
6. **No commercial features ever.** No Pro tier. No SaaS. No paid Discord.
   No support contracts. License-required and ethics-required.
7. **Active referral on hard cases.** When something breaks in calimocho,
   our error message recommends the CrossOver 14-day trial before opening
   an issue with us.
8. **Public non-competition statement.** `docs/relationship-with-codeweavers.md`
   exists so CodeWeavers staff Googling us see the honest position.

### Cross-linking obligations (LGPL + good manners)

Every release contains:
- `THIRDPARTY/CodeWeavers/` — LICENSE + a NOTICE pointing to
  `https://www.codeweavers.com/crossover` and the source we built
- `THIRDPARTY/gcenx/` — attribution + links to the upstream repos
- `THIRDPARTY/Apple-GPTK/` — EULA text + Apple's developer page link
- `THIRDPARTY/Wine/` — upstream Wine project credits + LGPL text
- `THIRDPARTY/MoltenVK/` — Apache 2.0 license + KhronosGroup link
- `THIRDPARTY/README.md` — a single document explaining "who made what, why
  you should thank them, and where to send money/love"

### Communications hygiene

- README explicitly tagged "experimental, no support, no SLA"
- Issues template tells users to file game bugs with **the game developer**,
  Wine bugs with **upstream Wine**, GPTK issues with **Apple**, calimocho
  bugs with us (and only the last category).
- No Discord server (until/unless we want to commit to running one).
- No social media presence beyond the GitHub repo.
- If anyone writes about us (blog, video), respond politely, don't promote,
  don't ask for stars.

## 15. Today's next concrete step

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

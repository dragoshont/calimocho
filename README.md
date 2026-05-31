# calimocho

> A personal recipe for running the Windows games I miss on my Mac.
>
> Currently: **Subnautica 2**. That is the whole list.
>
> Built on Wine 11 patches from
> [CodeWeavers](https://www.codeweavers.com/crossover), the Game Porting
> Toolkit D3DMetal from [Apple](https://developer.apple.com/games/game-porting-toolkit/),
> and the macOS Wine packaging work of [gcenx](https://github.com/Gcenx).
> Wrapped in a small SwiftUI menubar app, `Calimocho.app`.

[![License: LGPL 2.1+](https://img.shields.io/badge/License-LGPL_2.1+-blue.svg)](LICENSE)
[![Use: Non-commercial only](https://img.shields.io/badge/Use-Non--commercial%20only-orange.svg)](LICENSE)
![Platform: macOS arm64](https://img.shields.io/badge/Platform-macOS%20arm64-lightgrey)
![Status: experimental](https://img.shields.io/badge/Status-experimental-orange)

> ⚠️ **Non-commercial use only.** calimocho bundles Apple's Game Porting
> Toolkit `D3DMetal.framework`, whose license (Apple GPTK SLA §2A iii and §2C)
> explicitly allows redistribution but only for non-commercial purposes.
> Personal use, family use, free distribution, donations are all fine.
> Selling it, charging support for it, or including it in any paid product
> is not. If you want a commercially licensed and supported product,
> please [buy CrossOver from CodeWeavers](https://www.codeweavers.com/crossover).
> Their separate commercial agreement with Apple covers what this license
> does not.

---

## Should you use this?

**Short answer**: probably not, unless your situation is very specific.

| If you... | Answer |
|---|---|
| Want to play Subnautica 2 on your Mac, you cannot afford CrossOver, and you accept that this might not work for you | Try calimocho |
| Anything else | [Buy CrossOver](https://www.codeweavers.com/crossover) |

CrossOver costs $74 per year. It is the polished, supported, commercially
licensed version of what we are hacking together here. If you can afford
it, please buy it. CodeWeavers funds the Wine engine patches that this
whole project depends on. Without them, calimocho does not exist.

## Why this exists

Unknown Worlds shipped native Mac builds for
[Subnautica](https://store.steampowered.com/app/264710/Subnautica/) (2018) and
[Subnautica: Below Zero](https://store.steampowered.com/app/848450/Subnautica_Below_Zero/)
(2021). My family bought both. We played them together on our Mac.

When [Subnautica 2](https://store.steampowered.com/app/2864380/Subnautica_2/)
launched in Early Access on May 14, 2026, it was Windows only. So this
project exists as a stopgap, until Unknown Worlds ships a native Mac
build of SN2 too. When that happens, calimocho will be archived.

For the longer version of this story, see [docs/why-this-exists.md](docs/why-this-exists.md).

## What it does technically

calimocho takes three open or freely redistributable things, builds them
on your Mac, and wraps the result in a small SwiftUI menubar app
(`Calimocho.app`):

1. **Wine 11.0 with CodeWeavers' patches** (LGPL source, fetched from
   [CodeWeavers' public source mirror](https://media.codeweavers.com/pub/crossover/source/)
   and rebuilt locally).
2. **Apple Game Porting Toolkit 3 D3DMetal framework** (the DirectX 12 to
   Metal translator, redistributable per Apple's GPTK license, repacked by
   [gcenx](https://github.com/Gcenx/game-porting-toolkit)).
3. **MoltenVK** (Vulkan to Metal, Apache 2.0, bundled with GPTK).

The app exposes one user-visible action ("Open Steam for Windows") plus
a first-run wizard that installs Steam into a Calimocho-owned bottle.
Power-user actions are hidden behind Option-click. No bottle picker,
no Winetricks UI, no DLL override panel.

## Standing on the shoulders of these giants

calimocho is 99% other people's work. The shell script that glues it
together is the easy part. Everything below is the actual project.

### The Wine project
[winehq.org](https://www.winehq.org)
30 years of reverse engineering the Windows API by volunteers and
CodeWeavers staff. Without them, none of this exists. Not calimocho, not
CrossOver, not Whisky, not Heroic. **Please donate even a little to Wine
directly**: [winehq.org/donate](https://www.winehq.org/donate).

### CodeWeavers
[codeweavers.com](https://www.codeweavers.com/crossover)
The company that funds most of the upstream Wine work that benefits
macOS. Their CrossOver product ($74 per year) is the polished, supported,
commercially licensed version of this stack. They publish all their Wine
patches as LGPL source, which is the only reason calimocho is legal at
all. **If you can afford CrossOver, please buy it**, even if calimocho
works for you. They earn it.

### Apple Game Porting Toolkit team
For shipping `D3DMetal.framework` as a redistributable component with
explicit non-commercial permission in the GPTK license. This is the only
practical way DirectX 12 games render on Apple Silicon outside of Apple's
own first-party apps.

### gcenx
[github.com/Gcenx](https://github.com/Gcenx)
The single-person volunteer who maintains the macOS Wine packaging
ecosystem. He repacks upstream Wine and the Apple GPTK into drop-in
tarballs that Whisky, Heroic, Wineskin, Kegworks, and calimocho all
depend on. **Star [his repos](https://github.com/Gcenx?tab=repositories).**
The whole free macOS Wine world rests on his unpaid work.

### Isaac Marovitz and the Whisky community
[github.com/Whisky-App/Whisky](https://github.com/Whisky-App/Whisky)
For proving that a friendly SwiftUI front-end to Wine on macOS is
possible, and for the years of work that went into Whisky before it was
archived in May 2025. Calimocho's app shape borrows ideas from Whisky
but does not depend on it. Star the repo.

### Unknown Worlds Entertainment
For shipping Subnautica 1 and Subnautica: Below Zero natively on Mac. We
are still here, hoping for the third.

### KhronosGroup
[github.com/KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK)
For MoltenVK, the Vulkan-to-Metal translator that makes our DX11 path
possible.

---

This list is the project. The 50 lines of shell we add are the easy part.
Everything that actually makes your Mac play Windows games came from the
people and projects above.

## What this is NOT

- **Not a CrossOver alternative.** CrossOver has support, per-game profiles,
  anti-cheat workarounds, day-of patches, notarization, polish, a
  commercial license, and a team of paid engineers. calimocho has none of
  those. CrossOver wins on every one of these dimensions. If any of them
  matter to you, **buy CrossOver**.
- **Not a product.** It is a config recipe.
- **Not a support channel.** Game bugs go to the game publisher. Wine bugs
  go to [winehq.org](https://www.winehq.org). GPTK bugs go to Apple.
  Only calimocho-specific bugs go here.
- **Not promoted.** No HackerNews post, no Reddit thread, no blog. If you
  found this, it was by chance or word of mouth.
- **Not for sale, ever.** No Pro tier, no paid Discord, no support
  contracts, no commercial sublicensing. The Apple GPTK non-commercial
  clause means it cannot be sold, and we agree with that anyway.
- **Not a long-term project.** The plan is to archive when Unknown Worlds
  ships a native Mac build of Subnautica 2.

## Where to send money or thanks

Please do **not** donate to calimocho. Send it up the chain instead:

- **Buy CrossOver**: [codeweavers.com/crossover](https://www.codeweavers.com/crossover)
- **Donate to Wine**: [winehq.org/donate](https://www.winehq.org/donate)
- **Star gcenx's repos**: [github.com/Gcenx](https://github.com/Gcenx?tab=repositories)
- **Star Whisky**: [github.com/Whisky-App/Whisky](https://github.com/Whisky-App/Whisky)

## Game compatibility

See [docs/games-i-miss-on-my-mac.md](docs/games-i-miss-on-my-mac.md). It is
a one-row table. That is the whole supported list.

## Quick start (planned, not yet ready)

v1.0 will ship a DMG:

1. Download `Calimocho-vX.Y.Z.dmg` from GitHub Releases.
2. Open the DMG, drag `Calimocho.app` to `/Applications`.
3. Right-click `Calimocho.app` → Open (one-time Gatekeeper bypass for
   ad-hoc-signed apps; see [troubleshooting.md](docs/troubleshooting.md)).
4. Follow the first-run wizard: it installs Steam into a
   Calimocho-owned bottle.
5. Sign in to Steam, install Subnautica 2, play.

**Status**: not shipped yet. Track progress in
[docs/PHASES.md](docs/PHASES.md) and [docs/build-log.md](docs/build-log.md).

## Build the engine from source (Phase 1, available today)

Phase 1 ships the bare engine — Wine 11 + GPTK D3DMetal, no SwiftUI app
yet. You invoke `out/engine/bin/wine` directly from a terminal.

Prerequisites: Apple Silicon Mac, macOS 15 or later, Xcode Command Line
Tools, native arm64 Homebrew at `/opt/homebrew/`. The build is x86_64
under Rosetta 2 — see [ADR-0010](docs/ADR/0010-host-arch-x86_64-rosetta.md).

```bash
git clone https://github.com/dragoshont/calimocho.git
cd calimocho
scripts/prep-build-deps.sh        # Rosetta 2 + x86_64 Homebrew + Wine deps
scripts/fetch-sources.sh          # CodeWeavers Wine 11 tarball (sha256 pinned)
scripts/patch-sources.sh          # apply calimocho patches (see patches/wine/)
scripts/build-wine.sh             # configure + make + install (~20 min)
scripts/overlay-gptk.sh           # copy Apple GPTK D3DMetal into out/engine/
scripts/sign-engine.sh            # ad-hoc sign every Mach-O with Wine entitlements
scripts/test-engine.sh            # verify A1.1, A1.2, A1.3, A1.5
out/engine/bin/wine notepad.exe   # try it
```

Build artifacts live under `out/engine/` (gitignored). All A1.x acceptance
criteria are documented in [docs/SPECS.md](docs/SPECS.md).

## Roadmap

Six phases, fully described in [docs/PHASES.md](docs/PHASES.md):

| Phase | What it delivers |
|---|---|
| 0 | Repo, docs, license, build deps (done) |
| 1 | Wine 11 engine built from CodeWeavers source, CLI smoke tests pass |
| 2 | `Calimocho.app` menubar app + first-run wizard, manually installed |
| 3 | Subnautica 2 plays from inside Calimocho.app, with UE4SS console mod |
| 4 | DMG installer, ad-hoc signed, Sigstore-provenanced |
| 5 | GitHub Actions CI, Sparkle auto-update, visual regression tests |
| 6+ | Optional wishlist games, one at a time |
| ∞ | **Archive when Unknown Worlds ships a native macOS build of Subnautica 2.** |

Full plan in [docs/PLAN.md](docs/PLAN.md).

## Trademarks

"CrossOver" and "CodeWeavers" are trademarks of CodeWeavers, Inc.
"Apple", "macOS", "Apple Silicon", "Game Porting Toolkit", and "D3DMetal"
are trademarks of Apple Inc.
"Wine" is a trademark of the Wine project.
"Steam" is a trademark of Valve Corporation.
"Subnautica" is a trademark of Unknown Worlds Entertainment.

calimocho is not affiliated with, endorsed by, or sponsored by any of the
above. References are nominative fair use.

## License

LGPL 2.1 or later for our own scripts. Non-commercial use only for the
overall distribution because of the bundled Apple GPTK component. See
[LICENSE](LICENSE) and [docs/relationship-with-codeweavers.md](docs/relationship-with-codeweavers.md)
for the full breakdown.

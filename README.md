# calimocho

> **Fortified Wine for Apple Silicon Macs.**
> A free, open-source build of [CodeWeavers'](https://www.codeweavers.com/crossover) patched Wine 11 +
> [Apple's Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) D3DMetal +
> [MoltenVK](https://github.com/KhronosGroup/MoltenVK), packaged as a drop-in replacement
> for the (archived) [Whisky](https://github.com/Whisky-App/Whisky) runtime.

[![License: LGPL 2.1+](https://img.shields.io/badge/License-LGPL_2.1+-blue.svg)](LICENSE)
![Platform: macOS arm64](https://img.shields.io/badge/Platform-macOS%20arm64-lightgrey)
![Status: experimental](https://img.shields.io/badge/Status-experimental-orange)

## Why?

[Whisky](https://github.com/Whisky-App/Whisky) — the popular free Mac Wine GUI — was put into permanent
maintenance mode in May 2025. It still ships **Wine 7.7** (April 2023), which can no longer run the
current Steam client (the embedded Chromium "steamwebhelper" needs syscalls only Wine 9+ implements).

The polished alternative is [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers
(USD $74 / year). It ships Wine 11 with CodeWeavers' own patches plus Apple's GPTK D3DMetal,
and it Just Works for modern DX12 games like Subnautica 2 — but it costs money some families can't justify.

**calimocho** bridges the gap by **building CodeWeavers' published Wine source from scratch**
(LGPL 2.1+ — they're legally required to publish it), combining it with the publicly-distributed
GPTK D3DMetal libraries from [@gcenx](https://github.com/Gcenx)'s repacks, and dropping the result
into Whisky's `Libraries/` folder so the existing Whisky GUI keeps working.

You get:

- Wine 11.0 with the **same macdrv / wined3d / vkd3d patches** CrossOver ships
- **D3DMetal** for DX12 → Metal on Apple Silicon
- **MoltenVK** for DX11/Vulkan → Metal
- Whisky's bottle manager UI on top
- One install script, idempotent, with `--rollback`

## What this is *not*

- **Not** affiliated with or endorsed by CodeWeavers, Apple, Valve, or the Wine project.
- **Not** a redistribution of CrossOver's binaries. We build from their published LGPL source.
- **Not** a support channel for game-specific issues — those go to upstream Wine / CrossOver /
  game developer.
- **Not** a replacement for CrossOver if you want polish, per-app profiles, official support,
  or to support CodeWeavers' work. **Please consider buying CrossOver** if it works for you.

## Quick start

```bash
# 1. Install Whisky (provides the GUI we're using as a host)
brew install --cask whisky

# 2. Run calimocho to build + install the engine
git clone https://github.com/dragoshont/calimocho.git
cd calimocho
./bin/calimocho install            # builds + installs into Whisky's Libraries/

# 3. Open Whisky, create a bottle as usual.
```

To revert to stock Whisky:

```bash
./bin/calimocho rollback           # restores the most recent Libraries.bak
```

## Build requirements

- Apple Silicon Mac (`arm64`)
- macOS 14+ (Sequoia 15+ recommended for AVX-via-Rosetta)
- Xcode Command Line Tools (`xcode-select --install`)
- Homebrew
- ~3 GB free disk for the build, ~600 MB for the installed result
- ~30-45 min on M1 / 15-20 min on M3 Max for a from-source build

The install script handles all `brew` dependencies automatically (`mingw-w64`, `bison`, `flex`,
`gnutls`, `freetype`, `gstreamer`, etc.).

## How it works

```
┌─ Whisky.app (UI, unchanged) ────────────────────────┐
│                                                     │
│   ~/Library/Application Support/                    │
│       com.isaacmarovitz.Whisky/Libraries/           │
│       └── Wine/                ◄── calimocho writes │
│           ├── bin/wine64       ◄── CodeWeavers Wine │
│           └── lib/external/    ◄── GPTK D3DMetal    │
│                                    + MoltenVK       │
└─────────────────────────────────────────────────────┘
```

Whisky has no idea the runtime was swapped — it still launches `bin/wine64` against a bottle prefix
exactly the same way. All UI features (bottle creation, config toggles, Winetricks, DXVK toggle)
keep working.

## License & attribution

calimocho's own scripts: **LGPL 2.1+** (same as Wine).

This project would not exist without the work of:

- **The Wine project** — https://www.winehq.org — for 30+ years of Win32 reverse-engineering. The
  thing we're packaging is 99% theirs.
- **CodeWeavers** — https://www.codeweavers.com — for the macdrv + wined3d + vkd3d patches that
  make Steam, Chromium, and modern DX12 games actually work on macOS. Their CrossOver product is
  the reason the entire macOS Wine ecosystem exists. **If this script makes Mac gaming work for
  you and you can afford it, please [buy CrossOver](https://www.codeweavers.com/crossover) — it's
  one of the cleanest examples of a company funding upstream open-source work.**
- **Apple** — for the Game Porting Toolkit D3DMetal libraries that translate DirectX 12 to Metal
  on Apple Silicon. Closed-source but freely redistributable, included via @gcenx's repacks.
- **MoltenVK contributors** — https://github.com/KhronosGroup/MoltenVK — for Vulkan→Metal,
  used for the DX11 path.
- **[@gcenx](https://github.com/Gcenx)** — for tirelessly maintaining the
  [macOS Wine builds](https://github.com/Gcenx/macOS_Wine_builds) and
  [GPTK repacks](https://github.com/Gcenx/game-porting-toolkit) that this script depends on.
- **[Isaac Marovitz](https://github.com/IsaacMarovitz)** — for building Whisky, which made
  free Wine-on-Mac approachable for thousands of people. We're standing on Whisky's shoulders.

## Status

🟠 **Experimental — work in progress.**

- [x] Reverse-engineer Whisky's `Libraries/` layout
- [x] Validate Wine-11-via-gcenx swap works at the binary level
- [x] Identify the Wine-7 → Wine-11 syscall gap that breaks current Steam
- [x] Download CrossOver published source (Wine 11.0)
- [ ] Build CodeWeavers-patched Wine 11 from source on Apple Silicon
- [ ] Verify the build's macdrv renders Steam's CEF UI correctly (the Whisky-stock issue)
- [ ] Overlay GPTK 3 D3DMetal libraries
- [ ] End-to-end test with Subnautica 2 (DX12 / UE5)
- [ ] Polish `calimocho install` script
- [ ] Optional: Homebrew tap (`brew install dragoshont/calimocho/calimocho`)

Track progress in [docs/build-log.md](docs/build-log.md).

## Trademarks

"CrossOver", "CodeWeavers" are trademarks of CodeWeavers, Inc.
"Apple", "macOS", "Apple Silicon" are trademarks of Apple Inc.
"Wine" is a trademark of the Wine project.
"Steam" is a trademark of Valve Corporation.

calimocho is not affiliated with any of the above. This project simply combines their
freely-licensed and publicly-distributed work into one convenient package for personal use.

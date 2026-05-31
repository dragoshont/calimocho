# calimocho ARCHITECTURE

> The technical design. Every component, every file path, every interface
> boundary, every data flow.
>
> Source of truth for "what does calimocho actually do, byte by byte".
> Promises ("what does each part do") are in SPECS.md.

## Four-layer overview

```
┌─ Layer 4 — Host GUI ────────────────────────────────────────────┐
│   Phase 1+2: Whisky.app                                         │
│   Phase 3+:  Calimocho.app (SwiftUI menubar app)                │
│   Calls:     wine binary in Layer 2                             │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3 — Distribution                                          │
│   - Calimocho-vX.Y.Z.dmg  (build output of Phase 3 CI)          │
│     ├── Calimocho.app/                                          │
│     │   └── Contents/Resources/Engine/   ← bundled Layer 2      │
│     └── Drag-here-to-install symlink                            │
│   - Homebrew tap (cask wrapping the DMG)                        │
│   - Sigstore signature alongside each release artifact          │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2 — Runtime payload (the engine, what we ship)            │
│   - wine 11.0 (built from CodeWeavers LGPL source)              │
│   - wineserver, wineboot, winecfg (symlinks → wine)             │
│   - lib/wine/{i386-windows, x86_64-windows, x86_64-unix}/       │
│   - lib/external/D3DMetal.framework + libd3dshared.dylib        │
│   - lib/external/MoltenVK.dylib (Apple GPTK bundle)             │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1 — Build pipeline                                        │
│   - Sources: CodeWeavers LGPL + Apple GPTK 3 DMG                │
│   - Builders: GitHub Actions arm64 macos-15 runners             │
│   - Output:  Layer 2 + DMG containing Calimocho.app             │
└─────────────────────────────────────────────────────────────────┘
```

## Layer 1: Build pipeline

### Inputs (pinned in `versions.json`)

```json
{
  "wine_source": {
    "url": "https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.1.0.tar.gz",
    "sha256": "<computed at first pin>",
    "wine_version": "11.0"
  },
  "gptk": {
    "url": "https://download.developer.apple.com/<...>/Game_Porting_Toolkit_3.0.dmg",
    "sha256": "<computed at first pin>",
    "version": "3.0"
  },
  "fallback_gptk": {
    "url": "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz",
    "sha256": "<computed at first pin>"
  }
}
```

### Build steps (run by `scripts/build.sh`)

1. **fetch-sources** (5 min)
   - Download Wine source tarball, verify sha256
   - Download/mount GPTK DMG, verify sha256 (fallback to gcenx if needed)
2. **prep-build-deps** (one-time per machine, otherwise cached)
   - `brew install bison flex mingw-w64 gnutls freetype sdl2 pkg-config`
   - Detect Apple CLT compiler version
3. **configure** (2 min)
   - Run `~/cxwine-build/sources/wine/configure` with:
     ```
     --prefix=$BUILD_DIR/_install
     --enable-archs=x86_64,i386
     --without-x --disable-tests --with-mingw --with-gnutls
     --without-coreaudio --without-fontconfig --without-pcap
     --without-vulkan
     ```
   - Brew bison + flex first in PATH (Apple's are too old/incompatible)
   - Verify `config.h` has `EXEEXT` and `PACKAGE_VERSION` defined
     (autoconf substitution must complete; patch script in
     `scripts/fixup-config-h.sh` if needed)
4. **make** (30-45 min on M1 Max, 15-20 min on M3 Max)
   - `make -j$(sysctl -n hw.ncpu)`
   - Errors get captured in build-log
5. **stage-engine** (1 min)
   - Copy `_install/` tree into `out/Engine/`
   - Symlink `wine64 → wine`, `wineserver64 → wineserver`
6. **overlay-d3dmetal** (30 sec)
   - Copy `D3DMetal.framework` from mounted GPTK DMG into
     `out/Engine/lib/external/`
   - Copy `/redist/*` from GPTK into `out/Engine/lib/external/redist/`
   - Reproduce Apple's `License.rtf` into `out/THIRDPARTY/Apple-GPTK/`
7. **codesign** (10 sec)
   - `codesign --force --deep --sign - --options runtime out/Engine/`
   - Same for Calimocho.app (Phase 3+)
8. **package** (30 sec)
   - Phase 1+2: tar engine into `calimocho-engine-vX.Y.Z-arm64.tar.zst`
   - Phase 3+: build Calimocho.app, embed Engine, wrap in DMG via
     `create-dmg` or `hdiutil create`
9. **sign-provenance** (10 sec)
   - `cosign sign-blob --bundle out/<artifact>.bundle out/<artifact>`
   - Sigstore uses GitHub Actions OIDC token, no key management needed
10. **upload** (Phase 3 release.yml only)
    - GitHub Releases upload via `gh release create`

### Build caching strategy

- `actions/cache@v4` keyed on `versions.json` hash
- Cache layers:
  - Wine source tarball (~150 MB)
  - Brew bottles
  - Wine `./configure` output
  - Wine compiled object files
- Cache hit: rebuild is ~5 min instead of ~45 min

## Layer 2: Runtime payload

### Disk layout when installed (Phase 1+2)

Lives inside Whisky's existing dir:

```
~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/
├── Wine/              ← OURS (calimocho-built)
├── DXVK/              ← PRESERVED from prior Whisky
├── WhiskyWineVersion.plist  ← OUR version metadata, plist format Whisky reads
├── winetricks         ← PRESERVED
└── verbs.txt          ← PRESERVED
```

### Disk layout when installed (Phase 3+)

Bundled inside Calimocho.app:

```
/Applications/Calimocho.app/
├── Contents/
│   ├── Info.plist         (bundle id: com.dragoshont.calimocho)
│   ├── MacOS/Calimocho    (the SwiftUI launcher)
│   ├── Frameworks/Sparkle.framework
│   ├── Resources/
│   │   ├── Engine/        ← THE WINE + GPTK PAYLOAD
│   │   │   ├── bin/wine
│   │   │   ├── lib/wine/
│   │   │   └── lib/external/D3DMetal.framework
│   │   ├── Assets.car
│   │   └── THIRDPARTY/
│   └── _CodeSignature/
└── ...
```

The Engine inside Calimocho.app is **the same payload** as what gets
dropped into Whisky's Libraries/ in Phase 1+2. Calimocho.app just owns
its own copy instead of depending on Whisky's installation.

### Wine prefix layout (the user's "bottle")

Phase 1+2 (Whisky-owned):

```
~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<UUID>/
├── system.reg          ← Wine 11 schema (migrated by wineboot --update)
├── user.reg
├── drive_c/            ← Windows C: drive
│   ├── windows/system32/
│   ├── Program Files (x86)/Steam/
│   │   └── steam.exe
│   └── ...
└── Metadata.plist      ← Whisky bottle config (Win version, sync mode, etc.)
```

Phase 3+ (Calimocho-owned):

```
~/Library/Application Support/Calimocho/Bottles/STEAM/
├── system.reg
├── user.reg
├── drive_c/
│   └── (same as above)
└── config.json         ← OUR bottle config (Win version, sync mode, DLL overrides, args)
```

Bottle data is **never inside Calimocho.app**. The app stays clean for
uninstall; bottle data persists in app-support across reinstalls.

## Layer 3: Distribution

### DMG structure (Phase 3+)

```
Calimocho-v1.0.0.dmg (read-only mounted volume)
├── Calimocho.app/                  ← drag this to /Applications
├── Applications -> /Applications   ← symlink, makes the drag obvious
├── README.txt                      ← brief, "drag Calimocho to Applications"
└── .background/                    ← background image positioning the icons
```

### Sigstore artifact bundle

Every release on GitHub Releases has, alongside `Calimocho-v1.0.0.dmg`:

- `Calimocho-v1.0.0.dmg.sig` (cosign bundle)
- `Calimocho-v1.0.0.dmg.sha256` (text)
- `SOURCE_DATE_EPOCH` recorded in release body

Verification by paranoid user:

```bash
cosign verify-blob \
  --bundle Calimocho-v1.0.0.dmg.sig \
  --certificate-identity "https://github.com/dragoshont/calimocho/.github/workflows/release.yml@refs/tags/v1.0.0" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  Calimocho-v1.0.0.dmg
```

### Sparkle update flow

- Calimocho.app polls `https://raw.githubusercontent.com/dragoshont/calimocho/main/appcast.xml`
  daily (configurable)
- `appcast.xml` is a Sparkle 2 manifest with EdDSA signatures over each release
- Sparkle downloads new DMG → verifies EdDSA → mounts → replaces app
- User sees a small "Update available" toast in menubar

## Layer 4: Host GUI

### Phase 1+2: Whisky.app

We do not modify Whisky.app. We only drop our payload into the Libraries
folder it reads from. Whisky's UI is unchanged.

### Phase 3+: Calimocho.app

SwiftUI app, single window-less menubar item. Components:

```
Calimocho.app
├── MenuBarController       (NSStatusItem + menu population)
├── FirstRunWizardWindow    (only shown if no bottle exists)
├── SteamLauncher           (wraps spawning steam.exe via our wine)
├── BottleManager           (creates/destroys/configures bottles in
│                            ~/Library/Application Support/Calimocho/Bottles/)
├── EngineInstaller         (copies bundled Engine/ to a known location,
│                            or re-uses the bundled copy in place)
├── SparkleUpdater          (delegate, presents update UI)
├── LogViewerWindow         (Option-click → View logs)
└── Diagnostics             (Option-click → Diagnose, writes a redacted zip)
```

See `docs/ux/APP-DESIGN.md` for the UX details.

## Data flows

### "User launches Steam" (Phase 3 path)

```
User clicks "Open Steam for Windows" in menubar
  → MenuBarController.openSteam()
    → SteamLauncher.launch()
      → BottleManager.findOrCreateSteamBottle()
        → returns prefix path
      → spawn /Applications/Calimocho.app/Contents/Resources/Engine/bin/wine
        with WINEPREFIX=<prefix>
        argv=["C:\\Program Files (x86)\\Steam\\steam.exe", "-cef-disable-gpu", ...]
        env={WINEESYNC=1, WINEDEBUG=-all}
      → fork+exec; wine spawns:
        - wineserver (background)
        - winedevice.exe (background)
        - steam.exe (foreground; spawns its own steamwebhelper children)
      → Steam window appears
  → User interacts with Steam
  → User quits Steam → wineserver exits → bottle is idle
```

### "User clicks Install Steam in first-run wizard"

```
FirstRunWizard.tapInstall()
  → SteamInstaller.fetch()
    → curl https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe
    → save to /tmp/SteamSetup.exe
  → SteamInstaller.runInBottle()
    → BottleManager.createSteamBottle() (if not exists)
    → spawn wine /tmp/SteamSetup.exe /S (silent install)
    → poll bottle's Program Files (x86)/Steam/steam.exe for existence
  → FirstRunWizard.markDone()
    → returns to main menu
```

## Failure modes and their handling

| Failure | Detection | Handling |
|---|---|---|
| Brew dep missing during build | `./configure` fails with explicit error | Build script prints "missing dep" hint; CI runs `brew bundle` first |
| Wine source download corrupted | sha256 mismatch | Re-download once, then fail with clear message |
| GPTK DMG checksum wrong | sha256 mismatch | Fallback to gcenx repack, sha256 check that too |
| `EXEEXT` undefined in config.h | First make target fails | `scripts/fixup-config-h.sh` patches `include/config.h`; logged in build-log |
| Steam UI black window | Detected at Phase 1 acceptance test (visual diff vs baseline screenshot) | Phase 1 fails; do not advance to Phase 2; document in build-log |
| Bottle migration fails | wineboot exits non-zero | Roll back to prior Libraries, surface error in `calimocho status` |
| User quits during Steam install | Wine processes orphaned | `calimocho diagnose` includes cleanup script suggestion |
| Sparkle update fails | Sparkle's own error handling | Falls back to manual download path documented in README |

## Boundaries we do not cross

- We do not call private macOS APIs in Calimocho.app
- We do not link statically against Apple's frameworks beyond what Wine
  needs (CoreAudio, AppKit, etc.)
- We do not write outside the documented paths
  (`~/Library/Application Support/Calimocho/`,
  `~/Library/Logs/Calimocho/`, `/Applications/Calimocho.app`)
- We do not modify GPTK's D3DMetal binary in any way
- We do not patch Wine in our build (we may add patches under
  `patches/` later but none exist at v0.1)

## Open questions

- Should we provide an option to use the bundle's Engine vs. a
  user-installed one (e.g., from Homebrew)? Default: bundle. Override:
  not in v1.0.
- Should we honor `XDG_DATA_HOME` for app-support paths? Default: no,
  macOS convention is `~/Library/Application Support/`.
- Should we add telemetry? Default: never. No analytics. AGENTS.md
  rule #6 (silent project) extends to runtime behavior.

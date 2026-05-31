# UX: User journey

> What a real Mac user sees, step by step, from "I downloaded the DMG"
> through "I'm playing the game". Plus Day 2 (normal launch), Update Day
> (Sparkle update), and error states.
>
> All flows are Phase 3+ (the Calimocho.app world). Phase 1+2 users
> interact with Whisky.app's GUI instead; see the README quick-start.

## Day 1: First install (Phase 3)

### Step 1. Download

User lands on `https://github.com/dragoshont/calimocho`.

The README says, near the top:

> Download Calimocho-vX.Y.Z.dmg from
> [the latest release](https://github.com/dragoshont/calimocho/releases/latest)

User clicks. ~600 MB DMG downloads to ~/Downloads.

### Step 2. Mount and drag

User double-clicks `Calimocho-vX.Y.Z.dmg`. macOS mounts it.

A window opens showing:

```
   ╭─────────────────────────────────────────╮
   │                                         │
   │      🍷                          📁      │
   │   Calimocho.app           Applications   │
   │                                         │
   │   Drag Calimocho to Applications       │
   │                                         │
   ╰─────────────────────────────────────────╯
```

User drags `Calimocho.app` onto `Applications`. Standard Mac install
flow. Takes 5 seconds.

### Step 3. First launch (one-time Gatekeeper bypass)

User opens /Applications/, double-clicks Calimocho.

macOS shows:

```
   "Calimocho" can't be opened because Apple cannot check it for
   malicious software.

   [Move to Trash]   [OK]
```

This is expected for ad-hoc signed apps.

User follows the README's screenshot instructions:

1. Open System Settings → Privacy & Security
2. Scroll to bottom, find "Calimocho was blocked from use..."
3. Click "Open Anyway"
4. Confirm

Or the simpler workaround: right-click Calimocho.app in /Applications,
choose Open, confirm in the dialog. macOS remembers, no future warnings.

(In v1.0+ Calimocho.app's first DMG window will include screenshots of
this workflow.)

### Step 4. First-run wizard

Calimocho.app opens for the first time. It shows a one-window wizard:

```
   ╭────────────────────────────────────────────────────────╮
   │                                                        │
   │   🍷  Welcome to Calimocho                             │
   │                                                        │
   │   Calimocho lets you run Steam for Windows on your    │
   │   Mac. We'll install Steam now (about 300 MB download │
   │   from steampowered.com).                             │
   │                                                        │
   │   You'll need:                                         │
   │   • Your Steam account                                 │
   │   • About 20 GB free for Subnautica 2                 │
   │   • About 5 minutes                                    │
   │                                                        │
   │   ⓘ Why am I doing this?                              │
   │   Subnautica 2 doesn't have a Mac version yet.        │
   │   This is a stopgap while we wait for the official    │
   │   port.                                                │
   │                                                        │
   │             [Skip for Now]   [Install Steam]          │
   │                                                        │
   ╰────────────────────────────────────────────────────────╯
```

User clicks "Install Steam".

Wizard shows progress:

```
   Step 1 of 3: Setting up Wine bottle...   [████░░░░░░] 40%
   Step 2 of 3: Downloading Steam (3 MB)... waiting
   Step 3 of 3: Installing Steam in bottle... waiting
```

Each step takes 20-60 seconds. User waits.

When done:

```
   ✓ Steam is installed.

   Click below to launch Steam and sign in. You'll only see this
   wizard once.

                     [Launch Steam]
```

### Step 5. First Steam launch

User clicks. Steam window opens (this is the moment that depends on our
CW-Wine + GPTK build working correctly — the black-window risk from
Phase 1 must be solved before Phase 3 ships).

User signs in. Two-factor on phone. Library appears.

User searches "Subnautica 2", clicks Install.

Steam downloads 15 GB. User can close the Calimocho wizard; Steam keeps
downloading in the background.

### Step 6. Play

After 15-30 minutes (depending on internet speed), download finishes.
User clicks Play in Steam. Subnautica 2 launches.

Notification at top of macOS screen: "Calimocho is running Steam in the
background."

User plays.

### Step 7. Exit

User quits SN2 (in-game menu). Steam window remains.

User quits Steam (Steam menu → Exit Steam, or just close window then
Cmd+Q the dock icon).

Calimocho menubar icon remains visible. No prompts.

## Day 2: Normal launch

User wants to play SN2 again. Three equally valid paths:

### Path A: menubar

User clicks 🍷 in menubar. Click "Open Steam for Windows". Steam opens.
Click Play in Steam. Game launches.

Time from click to game: about 30 seconds (Steam launch + the game's own
loading).

### Path B: Calimocho.app from Dock/Spotlight

User Cmd+Space, types "Calimocho", hits enter. Same as Path A from there.

### Path C: pinning Steam to the Dock

After first launch, Steam's dock icon (which is Wine's wrapper for
steam.exe) can be right-clicked → Options → Keep in Dock. From then on,
user can click that icon directly. Calimocho's menubar still has to be
running (because it owns the wineserver process tree).

### Across reboots

Calimocho is **not** added to login items by default. User can opt in
via menubar → "Launch Calimocho at login" toggle. We do not auto-add to
avoid being intrusive.

## Update day

Calimocho polls Sparkle's appcast daily. When a new release is published:

A subtle notification appears in the menubar:

```
   🍷 (1)   ← small badge dot indicating update available
```

Click → dropdown shows:

```
   🍷 Calimocho v1.0.0   (1.0.1 available)

   ▶ Open Steam for Windows
   ────────────────────────
   ⬇ Update available: v1.0.1
   ────────────────────────
   About / Quit
```

Click "Update available". Sparkle dialog:

```
   ╭────────────────────────────────────────────────╮
   │  A new version of Calimocho is available!      │
   │                                                │
   │  Version 1.0.1 — released June 2026            │
   │  Size: ~600 MB                                 │
   │                                                │
   │  What's new:                                   │
   │  • Updated Wine to CrossOver 26.2 source       │
   │  • Updated GPTK to 3.0-4                       │
   │  • Fixes for Steam's June client update        │
   │                                                │
   │  Bottle data, Steam install, and saved games  │
   │  are preserved. No re-download required.       │
   │                                                │
   │       [Remind Me Later]   [Install and Relaunch] │
   ╰────────────────────────────────────────────────╯
```

User clicks Install. Sparkle:

1. Downloads new DMG in background
2. Verifies EdDSA signature
3. Quits Calimocho.app
4. Replaces /Applications/Calimocho.app with new version
5. Relaunches Calimocho.app
6. New menubar item appears (now at v1.0.1)

Steam bottle, game install, saves: all untouched. User clicks Open Steam
for Windows, picks up where they left off.

## Error states

### "I clicked Open Steam and nothing happened"

User clicks 🍷 → Open Steam for Windows. Nothing visible after 30
seconds.

Calimocho shows a non-blocking notification:

```
   🍷 Steam is taking longer than usual to start.
   This sometimes happens after a macOS update.
   [View logs]   [Force restart]   [Dismiss]
```

Behind the scenes Calimocho's `SteamLauncher` timed out waiting for
steam.exe to register a window. The user has two clear actions.

### "I got the Steamwebhelper not responding dialog"

If we still see the dialog after our build improvements, Calimocho's
launcher intercepts it. Instead of letting it appear, we:

1. Log it to `~/Library/Logs/Calimocho/`
2. Show our own dialog:

```
   🍷 Steam's UI process isn't responding.

   This is a known issue with Wine on macOS. Calimocho can:
   • Restart Steam with extra compatibility flags
   • Reset Steam's UI cache
   • Open the Calimocho diagnose bundle for support

   [Restart Steam]   [Reset Cache]   [Diagnose]
```

The user gets actionable choices, not the cryptic Steam dialog.

### "Calimocho stopped working after macOS update"

This will happen. macOS Sequoia → Tahoe → whatever brings ABI changes.

When Calimocho.app fails to spawn wine (signal 4, signal 11, etc.), the
app falls back to:

```
   ╭────────────────────────────────────────────────╮
   │  🍷 Calimocho can't start the Wine engine.    │
   │                                                │
   │  This usually means a macOS update broke      │
   │  compatibility with the bundled Wine version. │
   │                                                │
   │  Possible fixes:                               │
   │  1. Update Calimocho                          │
   │     [Check for Updates]                       │
   │                                                │
   │  2. Try CrossOver (the paid version) which   │
   │     gets faster updates                       │
   │     [Open codeweavers.com]                    │
   │                                                │
   │  3. File an issue with diagnostic info        │
   │     [Generate Diagnostic Bundle]              │
   ╰────────────────────────────────────────────────╯
```

We name CrossOver explicitly as the fallback. That's the entire ethos.

### "How do I uninstall?"

Two paths documented in README:

**Quick path** (keeps bottle data):
1. Drag /Applications/Calimocho.app to Trash.
2. Done. Bottle data stays in ~/Library/Application Support/Calimocho/
   in case you reinstall.

**Full path** (also removes bottles):
1. Open Calimocho menubar → Option-click → "Uninstall Calimocho..."
2. Confirm. App removes itself + all bottle data.

Alternatively `~/Applications/Calimocho.app/Contents/Resources/calimocho uninstall --full`
from terminal.

## What the user does NOT see

- Wine itself. Never. No mention of "bottle", "prefix", "wined3d",
  "winetricks" anywhere in the GUI.
- D3DMetal. They don't know it exists.
- CodeWeavers (in the GUI, only in About box and README).
- Any DLL override config.
- The first-run wizard, after the first run.
- Update notifications more than once per available version.

This is deliberate. Wine is plumbing. Calimocho is "click 🍷 to play".

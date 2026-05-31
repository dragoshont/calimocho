# ADR-0003: Host on Whisky's GUI in Phase 1-2, ship own .app in Phase 3

Status: Accepted
Date: 2026-05-31

## Context

calimocho needs a Mac-native way for users to interact with Wine bottles.
Three options exist:

1. **Require users to install Whisky.app separately** and drop our Wine
   build into Whisky's `Libraries/` folder.
2. **Build our own SwiftUI app** from scratch covering bottle management,
   Wine launch, settings, etc.
3. **Hybrid**: use Whisky during early phases (Phase 1 + 2) because it
   already works for the maintainer, then build our own thin app in Phase 3
   focused only on what's needed for the SN2 use case.

The full Whisky GUI is overkill for our SN2 stopgap (bottle manager,
Winetricks integration, DXVK toggle, etc. are unused). A minimal app that
just says "Open Steam for Windows" is what the maintainer actually wants.

## Decision

- **Phase 1**: Drop the built Wine into Whisky's existing
  `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/`.
  No new GUI. The maintainer uses Whisky.app's existing UI.
- **Phase 2**: Same setup. SN2 plays via Whisky's bottle launcher.
- **Phase 3**: Ship `Calimocho.app`, a small SwiftUI app that:
  - Bundles the Wine engine + GPTK + MoltenVK internally (does not depend
    on Whisky being installed)
  - Exposes a menubar item with one user-visible action: "Open Steam for
    Windows"
  - Hides power-user actions behind Option-click (reinstall engine, view
    logs, reset bottle, check for updates)
  - Uses Sparkle for auto-update with EdDSA-signed appcast
  - Distributed as a DMG that drags into /Applications

We do not require Whisky.app for Phase 3 users. We do credit Whisky in
the About box and link to the Whisky repo from our README.

## Consequences

### Positive

- Phase 1+2 ship in days, not weeks, because we don't have to write any
  GUI code yet.
- Phase 3 GUI is small (one menubar item + one wizard) and ownable by one
  maintainer.
- Users in Phase 3 don't need to install two apps.
- The "we're a stopgap until SN2 ships native" framing matches having a
  minimal app that disappears after one click.

### Negative

- Phase 1+2 users must install Whisky.app first. Documented in PHASES.md
  Phase 1 prereqs.
- Phase 3 requires writing SwiftUI + signing a launcher app + bundling
  the engine. Roughly 300 lines of Swift + DMG packaging.
- Splitting the GUI investment across phases means Phase 3 work cannot
  start until Phase 1 and Phase 2 prove the engine works.

### Neutral

- We do not fork Whisky. We ship parallel to it.
- If Whisky is un-archived and revived, our Phase 3 app becomes
  redundant and we can archive Calimocho.app while keeping the engine
  drop-in usable in Whisky.

## Related

- AGENTS.md rule #4 (visibly worse than CrossOver on purpose)
- docs/ux/APP-DESIGN.md (Phase 3 UI details)
- docs/PHASES.md

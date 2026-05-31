# ADR-0008: Own app from Phase 2; no Whisky.app dependency

Status: Accepted
Date: 2026-05-31

## Context

calimocho needs a Mac-native way for users to interact with Wine
bottles. The product's user never sees Whisky.app: v1.0 ships a DMG
containing Calimocho.app. Whisky is not in the install flow, not in
the troubleshooting docs, and not a runtime dependency.

If Whisky is not part of the product surface, building any phase on
top of it creates accidental complexity, ties calimocho's behavior to
Whisky's release schedule and `Libraries/` folder format, and forces a
later rewrite when we cut the dependency.

## Decision

- **Phase 1**: Build the engine. Validate with CLI-only smoke tests
  (`wine notepad.exe`, `wine steam.exe`). No GUI. No Whisky.
  Engine lives at `out/engine/` in the repo's working tree.
- **Phase 2**: Build `Calimocho.app`. SwiftUI menubar app + first-run
  wizard. The .app bundles the Phase 1 engine in
  `Contents/Resources/Engine/`. Manually installed by dragging to
  `/Applications/` (no DMG yet; that's Phase 4).
- **Phase 3+**: As documented in PHASES.md.
- **Whisky.app**: Not a runtime dependency. Not a build dependency.
  Not mentioned in the install flow. Credited only in the About box
  and in attribution sections of README and AGENTS.md.

The maintainer may install Whisky on a dev box as a personal sanity
check that their Wine build runs in another host. That is a
developer-convenience choice, not a project requirement, and is not
part of the documented build instructions.

## Consequences

### Positive

- The DMG, README, troubleshooting, and code all tell the same story
  from day one.
- Calimocho.app's release cadence is independent of Whisky's.
- AGENTS.md rule #3 (respect upstream) is satisfied by attribution
  without entangling runtimes.
- The first-run wizard, menubar interactions, log layout, and Sparkle
  hookup all live in our codebase from the start. No half-built state.

### Negative

- Phase 2 now requires writing SwiftUI code before any user-facing UI
  exists. Phase 1 has no GUI demo; the only Phase 1 demo is the
  maintainer at a terminal seeing `wine steam.exe` render correctly.
- We give up the "use Whisky's bottle picker UI for free" shortcut.

### Neutral

- The maintainer keeps using CrossOver to play SN2 with their family
  during Phases 1 and 2. Calimocho does not block anyone.

## Related

- [PHASES.md](../PHASES.md) (the 6-phase split this ADR enables)
- AGENTS.md rule #3 (respect upstream)
- AGENTS.md rule #4 (visibly worse than CrossOver on purpose)
- [ux/APP-DESIGN.md](../ux/APP-DESIGN.md) (Calimocho.app UX)

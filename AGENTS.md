# AGENTS.md — Operating rules for calimocho contributors

> Read this before changing anything. Applies to humans and AI agents.
> If a rule conflicts with what feels expedient, the rule wins.

## North star

calimocho exists to let the maintainer (and people in the same situation) run
Windows-only games they miss, on their Apple Silicon Mac, **without paying for
CrossOver**. The project is a stopgap until Unknown Worlds ships a native Mac
build of Subnautica 2.

Everything below serves that north star. If something doesn't, drop it.

---

## Hard rules (never break)

### 1. We compile from source. We never ship someone else's binary.
- ✅ Build Wine 11 from CodeWeavers' published LGPL source tarball
- ✅ Build vkd3d / DXVK / MoltenVK from source if we ship them
- ❌ Do NOT copy CrossOver's pre-built binaries from
  `/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/`
  into calimocho, ever, even for "just a quick test"
- ❌ Do NOT copy Whisky's bundled Wine 7.7 binaries either
- ✅ EXCEPTION: Apple's GPTK D3DMetal.framework is a binary we redistribute
  per Apple's explicit GPTK SLA permission (§2A iii + §2C, non-commercial).
  That is the one binary we ship unmodified.

**Why this rule exists**: CrossOver's EULA does not grant redistribution
rights for their compiled binaries. CodeWeavers' source is LGPL and freely
buildable. The whole legal premise of calimocho is "build from source you're
allowed to build". Touching their .dylib files violates that premise and
puts us in EULA grey area.

### 2. We are non-commercial. Forever.
- ❌ No paid tier
- ❌ No paid support contracts
- ❌ No paid SaaS or hosted-gaming offering
- ❌ No reselling the project as part of a paid product
- ❌ No bundling in any paid app
- ✅ GitHub Sponsors / Patreon donations to maintain the project are fine
  (FOSS convention), but we point them at WineHQ and CrossOver instead
- ✅ Free for any non-commercial use including community redistribution

**Why this rule exists**: Apple's GPTK license requires non-commercial.
Going commercial would also actively undercut CodeWeavers and break the
positioning everything else is built on.

### 3. We respect upstream.
- Every release credits Wine, CodeWeavers, Apple GPTK team, gcenx, Whisky,
  KhronosGroup. Names visible in README, release notes, and CLI banner.
- Donations point to WineHQ and CrossOver, not to us.
- If gcenx or CodeWeavers asks us to change something, we comply within days.
- If Whisky comes back to active development, we point users there and
  reposition (or archive).

### 4. We are visibly worse than CrossOver, on purpose.
- No support channel
- No per-game compatibility profiles
- No anti-cheat workarounds
- No notarization
- No day-of game patches
- No fancy native UI polish
- Anyone who needs those things should buy CrossOver, and we say so loudly
  in the README's decision table.

**Why this rule exists**: Free alternatives to paid products are an
ecosystem hazard. We minimize harm by being honestly less polished, so
the only users who pick us are those who would not have paid anyway.

### 5. We are SN2-scoped.
- Subnautica 2 is the only "Working" entry in the compat table.
- Other games may appear as "Wishlist" if the maintainer personally wants
  to play them.
- We do not accept "please add support for X" feature requests.
- We do not promise any game keeps working across calimocho releases except
  SN2.
- The project archives when Unknown Worlds ships a native Mac build of SN2.

### 6. We are silent.
- No HackerNews post, no Reddit thread, no blog
- No social media presence beyond the GitHub repo itself
- No promotion of any kind
- Growth is purely organic, by word of mouth or chance
- If someone writes about us externally, we respond politely but do not
  amplify

### 7. We test before we ship.
- Phase 1 acceptance: Steam logs in + library shows
- Phase 2 acceptance: SN2 reaches gameplay, FPS ≥ 30 medium 1080p
- Phase 3 acceptance: CI builds DMG from scratch on push to main; a clean
  M-series Mac reaches gameplay following only README instructions
- No release without the relevant phase acceptance test green

### 8. We use ad-hoc signing only.
- No Apple Developer ID ($99/yr) — not in budget
- All Mach-O binaries `codesign --force --deep --sign - --options runtime`
- DMG is not notarized
- README documents the right-click → Open Gatekeeper bypass clearly
- Sigstore signatures via GH OIDC for provenance (separate from Gatekeeper)

---

## Soft rules (break only with explicit, documented reason)

### Decisions are documented in ADRs
- Any decision that affects more than one file goes in `docs/ADR/NNNN-*.md`
- Use Michael Nygard's Context / Decision / Consequences format
- New ADRs do not require approval; reverse-ADRs do (write 0007 to revert 0003)

### Commit messages explain "why"
- Subject line is "what" (≤72 chars, present tense, no period)
- Body explains "why" in plain English (no em dashes)
- Reference the ADR or PHASE doc that motivated the change
- Co-authored-by trailers when work was done with an AI agent

### Documentation is in plain English
- Aimed at non-native English speakers
- No em dashes (use "—" alternatives: parentheses, colons, or just shorter
  sentences)
- No jargon without explanation
- ASCII art diagrams are fine; complicated graphics are not

### Phase order is strict
- Phase 1 must complete before Phase 2 starts
- Phase 2 must complete before Phase 3 starts
- Do not gold-plate within a phase; ship and iterate

### Build deps are pinned
- Brewfile.lock.json is committed
- Wine source is fetched from a specific CodeWeavers release URL with sha256
- GPTK is downloaded from a pinned gcenx release with sha256
- No "latest" anywhere in CI

### Failure is OK; silent failure is not
- If something doesn't work, document why in `docs/build-log.md`
- If a path is abandoned, write a brief reverse-ADR explaining
- "It didn't work and we moved on" is acceptable history; "we hid the
  evidence" is not

---

## Rules of engagement for AI agents

If you are an AI agent reading this to help with the project:

- You may not bypass any rule above
- You may suggest rule changes only by proposing a new ADR
- If asked to do something that violates a rule, push back politely once,
  then refuse if the user insists. The user can still override by editing
  this file and explaining why
- Prefer fewer, larger, well-documented commits over many tiny ones
- Always run `git status` before committing to catch surprise changes
- Always check `docs/PHASES.md` before starting work to make sure the
  current phase scope matches the task
- Update the todo list when scope shifts mid-session
- When in doubt, write a question to the user rather than guessing

---

## How to add a new rule

1. Open an issue or just a draft ADR
2. Wait for the maintainer to think about it (24+ hours, not chat-speed)
3. Write the ADR
4. Add the rule here once accepted

## How to remove a rule

Same process. Write a reverse-ADR explaining why the rule no longer fits
the north star.

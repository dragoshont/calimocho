# calimocho's relationship with CodeWeavers and CrossOver

> A public, unambiguous statement of where we stand. Written so that if anyone
> at CodeWeavers ever Googles "calimocho", this is what they find.

## What we are

calimocho is a free, open-source, non-commercial Wine runtime
distribution for Apple Silicon Macs, packaged as a tiny SwiftUI
menubar app (`Calimocho.app`). It exists to fill exactly one gap:
users who want to play Subnautica 2 on a Mac, cannot or will not pay
for CrossOver, and accept that this might not work for them.

## What we are not

- **Not a CrossOver alternative for commercial use.** Our license explicitly
  prohibits it. CrossOver is the only legal commercial option.
- **Not a CrossOver alternative for users who want polish, support, per-game
  profiles, anti-cheat compatibility, or notarization.** CrossOver wins on
  every one of those, and we tell users so loudly in the README.
- **Not a competitor.** We're downstream of CodeWeavers' work in every way
  that matters. They publish the source, we recompile it.

## What we owe CodeWeavers

CodeWeavers funds the salaries of the people who write the Wine patches that
make modern Steam, Chromium, DirectX 12, and macOS gaming work at all. Without
that funding, the upstream Wine project would not have CrossOver's patches,
gcenx would have nothing to repack, Whisky never would have shipped, and this
project would not exist.

We owe them visible, repeated acknowledgement:

1. Every README mentions CodeWeavers within the first 10 lines.
2. Every release notes header includes "If this saves you time, please support
   CodeWeavers."
3. Every install script banner mentions buying CrossOver.
4. Every "what is calimocho not" list includes "not a substitute for the
   support and polish CrossOver provides."

## What we will and won't do

### Will
- ✅ Always build from CodeWeavers' published LGPL source (no binary repacking)
- ✅ Always credit CodeWeavers publicly in attribution
- ✅ Promote CrossOver as the recommended path in our own README
- ✅ Decline donations directly to us — point users at WineHQ donations and
  CrossOver purchases instead
- ✅ Pause our releases for 1-2 weeks after a CrossOver release so paying users
  get the new bits first
- ✅ Refuse all commercial deployments (technical: our license forbids it;
  ethical: it would directly undercut CodeWeavers' commercial agreement)
- ✅ Promptly comply if CodeWeavers ever asks us to change something

### Won't
- ❌ Market calimocho as a "free CrossOver" or "CrossOver alternative"
- ❌ Promote on r/macgaming or compete in CrossOver's organic search results
- ❌ Build a paid version, ever
- ❌ Charge for support contracts
- ❌ Bundle calimocho into any paid hosted-gaming, cloud-gaming, or service offering
- ❌ Disparage CodeWeavers or CrossOver in any communication
- ❌ Ship anything CrossOver hasn't shipped first (we follow, we don't lead)

## How we'd react if CodeWeavers reached out

- **"We'd prefer you didn't do this"** → We would seriously consider archiving
  the project. The community-license argument is technically sound, but if the
  people doing the underlying work feel undercut, that matters more.
- **"Please change X"** → Done, within days.
- **"Could you contribute Y back to upstream Wine?"** → Yes, gladly.
- **"Would you like a commercial license to also distribute commercially?"** →
  We would politely decline. The point of calimocho is to be the non-commercial
  option. If we became commercial, we'd duplicate what CrossOver already does
  better.

## Why this project exists at all if we feel this way

The honest answer: there's a meaningful population of users — students, families
with tight budgets, hobbyists, people in countries where $74/yr in USD is two
weeks of grocery money — for whom CrossOver simply isn't an option. The choice
for them isn't "calimocho vs CrossOver", it's "calimocho vs nothing". gcenx
deliberately declined to fill this gap; we made a different call, with our eyes
open about the trade-offs, and with maximum respect for the people whose work
we're standing on.

If you're a developer at CodeWeavers reading this and disagree with our call,
please open a GitHub issue. We'd rather have the conversation than have you
silently resent the project.

— calimocho maintainer (@dragoshont), 2026-05-31

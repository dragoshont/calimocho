# Why this project exists

A short, honest story.

## The Subnautica trilogy

In 2018, Unknown Worlds Entertainment released **Subnautica** for Mac, alongside
Windows. It worked natively. No Wine, no compatibility layer, no fuss.

In 2021, they released **Subnautica: Below Zero**, also with a native Mac build.

Both games are still on Steam today. Both still run on modern Apple Silicon
Macs natively, in Apple's own Metal graphics API.

My family bought both. We played them together. They were a big deal in our
house.

## Then Subnautica 2 happened

On May 14, 2026, Unknown Worlds launched **Subnautica 2** into Early Access.
Windows only. No Mac build at launch.

I understand why. Early Access games change shape every week. Building and
testing a separate Mac client on top of that is expensive. The studio is
small. Priorities have to be made.

But for Mac families who bought the first two games and were waiting for the
third, the message felt different. We had the hardware. We had the money.
We had the years of loyalty. And we could not click "play".

## What I tried before building this

I tried [Whisky](https://github.com/Whisky-App/Whisky) first. It used to be the
free path for Mac users in this exact situation. But Whisky was put into
permanent maintenance in May 2025, and the Wine version it ships (Wine 7.7
from April 2023) is no longer new enough to run the current Steam client at
all. So Whisky was a dead end for SN2.

I tried [CrossOver](https://www.codeweavers.com/crossover) next. It worked.
SN2 ran. That was the polished, supported, paid answer. And it is genuinely
worth the money for many people. But $74 per year is real money in our
budget. For a family that already paid for three Steam games, paying a
subscription fee just to run the third one felt like a tax on being a Mac
user.

I tried to build a Whisky engine swap myself, using upstream Wine 11 from
[gcenx's macOS builds](https://github.com/Gcenx/macOS_Wine_builds). It got
Steam launching, but the UI rendered as a black window. Wine on macOS without
CodeWeavers' specific patches cannot draw Steam's embedded Chromium UI
correctly. That is the gap CrossOver fills.

## What this project does

calimocho builds CodeWeavers' Wine patches **from their published LGPL
source**, combines it with Apple's Game Porting Toolkit D3DMetal Framework
(which Apple licenses for non-commercial redistribution), and drops the result
into Whisky's `Libraries/` folder so the existing Whisky GUI keeps working.

It is the recipe I wish someone had handed me when SN2 launched.

## What I am hoping for

I am hoping Unknown Worlds ports Subnautica 2 natively to Mac, the way they
did with the first two games.

Their track record says they will. Once Early Access stabilizes, once the
gameplay shape settles, once they have time, a Mac client is plausible.
Apple has been investing heavily in Mac gaming. The platform is more
plausible as a target every year.

When that happens, **calimocho's reason to exist disappears**. I will archive
the project, point everyone at the official Mac build, and that will be the
right ending.

Until then, this is a stopgap. Built so my kid can dive into the depths with
me, on the same Mac we played the first two games on.

## Who I am grateful to

Everyone whose work this project rides on. They are listed in
[README.md](../README.md#standing-on-the-shoulders-of-these-giants) and in
[docs/relationship-with-codeweavers.md](relationship-with-codeweavers.md). If
calimocho ever helps you, please thank them first.

A specific thank-you to Unknown Worlds: thank you for the first two games.
We are still here, hoping for the third.

---
title: "I Put My Son in a Swamp"
description: "I modeled my newborn as a typed resource with a sync method and a stack of reports. It's the newest of five ways I track one baby, and somewhere in the absurdity there's a real reason two exhausted people instrument everything."
date: 2026-07-11T00:45:00-04:00
draft: false
categories: ['automation', 'homelab']
tags: ['swamp', 'babybuddy', 'parenting', 'home-assistant', 'mcp', 'pebble', 'devops']
---

My son is a typed resource now. He has a `sync` method that pulls the last seven
days of his life into a versioned snapshot, a stack of reports that summarize how
he slept and ate, and — I did think about this — a delete that's careful to be
idempotent, because deleting the same diaper twice shouldn't be an error.

I did not set out to put a baby in a swamp. It followed, the way these things do,
from having already put everything else in one.

## What "in a swamp" means

[swamp](https://github.com/swamp-club/swamp) models real resources as typed
objects with methods, and records every run as versioned data other models can
read. You write extensions in TypeScript. I used it [last week to automate my home
certificate authority]({{< ref "the-wifi-cert-that-didnt-exist-an-hour-ago" >}}),
and the whole time I kept thinking about the thing I actually spend all night
dealing with, which is not a certificate.

We run [Baby Buddy](https://github.com/babybuddy/babybuddy) at home — a small,
self-hosted app for tracking a newborn's feedings, diapers, sleep, pumping, meds.
It has a clean REST API. A clean REST API, at 2am, to a certain kind of brain, is
a dare.

So I wrote `@kneel/babybuddy`: one model that reads the whole instance into a
snapshot and writes new entries back, with a stack of reports that run over the
snapshot. Log a feeding, fix a mis-logged one, patch a bad timestamp, then ask it
questions.

## The reports tell on you

Summarizing a week of a newborn produces numbers that are, on their own, a little
unhinged. In the last seven days: ninety-six feedings. Sixty-five separate sleep
sessions. His longest unbroken stretch was four hours and forty-six minutes,
which I know to the minute because there's a report called `sleep-longest-stretch`
and I run it the way other people check the weather.

The one that got me was the medication report. I built it to answer "are we giving
the vitamin D on schedule," and it answered a question I hadn't asked, which is
"when does Neil actually remember the vitamin D." Not on schedule, it turns out.
It's a little cluster of timestamps at midnight, 2am, 3am — whenever I surfaced
enough to think of it. The schedule in my head and the schedule in the database
were not the same schedule, and only one of them keeps records.

That's the actual value of instrumenting anything: some night the dashboard hands
you back a picture of yourself you weren't planning to volunteer.

## This isn't the first interface. It's the fifth.

Here's the genuinely stupid part, and I say that with affection for the man who
did it: the swamp extension is the *newest* way I have to track this kid, not the
only one, and not by a wide margin.

There's a **mobile app** — a Capacitor wrapper around Baby Buddy with the sharp
edges filed down. Biometric lock, so a phone left on the couch doesn't show the
whole night's log. Log-a-diaper you can say out loud, because your hands are full,
because your hands are always full. A running feed timer on the lock screen next
to the elapsed time you're trying not to look at. iOS and Android, because of
course iOS and Android.

There's a **Pebble watchapp**, because the best possible interface for logging a
feed at 3am is a physical button on your wrist that emits about four photons.
Start a timer, stop it, pick the amount, done, without the wake-your-whole-nervous-
system glare of a phone. I'll admit the watchapp is currently ahead of my
hardware — I don't have the watch yet. There's a ring interface too. I don't have
the ring yet either. I wrote software for two devices I'm still waiting on, which
tells you roughly everything about the state of mind here.

There's a **conversational server** — an MCP that lets me, or Claude, or the voice
assistant it hangs off of, just *say* what happened. "He ate ninety at eleven." It
writes the same feeding record the app would, the same one the watch would, the
same one the swamp model syncs back out.

And there's **Home Assistant**, the layer that nags. At 10:30 it reminds whoever's
still upright to make the overnight bottle. At 11 it reminds us the vitamin D goes
in it. If nobody acknowledges, it asks again. It's a very polite robot with a
clipboard, and right now it has a better memory than either of us.

None of these sit on a stock Baby Buddy, either — the one underneath isn't stock
anymore. Somewhere in here I ended up bolting push notifications onto it via FCM,
adding per-record audit fields so I can see who logged what, soft-deleting timers
so a fat-fingered stop doesn't just vanish, and writing a handful of new reports.
"Track the baby" quietly became "re-platform the baby tracker," which is a
sentence I'd be embarrassed by if I'd slept.

Five interfaces. One baby. Every one of them a different door into the same little
REST API.

## Why though

You could read all of this as a man building toys instead of sleeping and you
wouldn't be all the way wrong. But there's a real thing underneath it, and it's
the least technical part of the post.

A newborn is a 24-hour operation run by two people getting maybe five hours each,
in shifts. The hardest part isn't any single feeding. It's the handoff — the 1am
moment where one of us goes horizontal and the other picks up the watch, and that
only works if we're both looking at the same set of facts. When did he last eat.
How much. Is he due. Did the vitamin D happen or did I dream it.

All the tracking — app, watch, voice, nags, swamp — isn't quantified-self stuff.
It's a shared source of truth for two very tired adults trying to hold one
continuous story between them across a shift change, in the dark, without waking
each other up to ask. The baby is just where the data comes from.

## The bit worth keeping

If one engineering lesson survived contact with a real newborn, it's the same one
from the [certificate post]({{< ref "the-wifi-cert-that-didnt-exist-an-hour-ago" >}})
wearing a smaller hat: data that claims to be complete when it isn't is worse than
no data.

When I wrote the `sync` method it capped each query at some number of records. A
sensible default — until you picture a parent syncing a long window, quietly
dropping the oldest entries, and getting a summary that looks whole. So the
snapshot carries a `truncated` flag now, an honest "there was more than this," and
the summary says so out loud instead of lying with a tidy little table.

Same instinct is why the timers soft-delete instead of actually deleting, and why
stop-timer won't silently throw away a running one. Two parents, two devices, one
baby: someone is going to stop the wrong thing or delete the same thing twice. The
tool's job is to make that boring, not to punish you for the race condition of
being a family.

He's asleep right now — nineteen minutes in, per the timer I am absolutely going
to stop checking, because checking it wakes the report, which wakes me. The
extension's open source on the swamp registry if you also run Baby Buddy and also
cannot leave a working API alone.

---

I point these same instincts at other people's infrastructure through
[Shrug PW](https://shrugpw.com). The stakes are higher and the sleep is better.

---
title: "I Put My Son in a Swamp"
description: "I modeled my newborn as a typed cloud resource — with a sync method, fifteen reports, and an idempotent delete. It is the fifth interface I have built for tracking one baby, and somewhere in the absurdity there is a real reason two sleep-deprived parents instrument everything."
date: 2026-07-11T00:45:00-04:00
draft: true
categories: ['automation', 'homelab']
tags: ['swamp', 'babybuddy', 'parenting', 'home-assistant', 'mcp', 'pebble', 'devops']
---

My son is a typed resource now. He has a `sync` method that pulls the last seven
days of his life into a versioned snapshot, fifteen reports that summarize how he
slept and ate and — I want to be clear that I did think about this — a
`delete-entry` method that is careful to be idempotent, because deleting the same
diaper twice should not be an error.

I did not set out to put a baby in a swamp. It just followed, the way these
things do, from already having put everything else in one.

## What "in a swamp" means

[swamp](https://github.com/swamp-club/swamp) models real resources as typed
objects with methods — read them, mutate them — and records every run as
versioned data other models can reference. You write extensions in TypeScript. I
used it [last week to automate my home certificate
authority]({{< ref "the-wifi-cert-that-didnt-exist-an-hour-ago" >}}), and the
whole time I kept thinking about the thing I actually spend all night touching,
which is not a certificate.

We run [Baby Buddy](https://github.com/babybuddy/babybuddy) at home — a small,
self-hosted app for tracking a newborn's feedings, diapers, sleep, pumping,
temperature, meds. It has a clean REST API. And a REST API, to a certain kind of
tired brain at 2 a.m., is an invitation.

So I wrote `@kneel/babybuddy`: one model that reads the whole instance into a
snapshot and writes new entries back, plus a pile of reports that run over that
snapshot. Log a feeding, delete a mis-logged one, patch a bad timestamp. Then
ask it questions.

## The reports tell on everyone

The nice thing about summarizing a week of a baby is that the numbers are, on
their own, quietly insane. Ninety-nine feedings. Sixty-five separate sleep
sessions. Forty-four doses of medication. His longest unbroken stretch of sleep
was four hours and forty-eight minutes, which I know to the minute because there
is a report called `sleep-longest-stretch` and I run it the way other people
check the weather.

But the report I did not expect to matter was the medication one. I built it to
answer "are we dosing the vitamin D on schedule," and instead it answered a
question I had not asked, which is "how many different ways has Neil spelled
vitamin D at midnight." The answer is three. `Vitamin D`, `Vitamin D Drops`, and
`Vitamin D drops` are, as far as the database is concerned, three unrelated
substances, dosed on three overlapping schedules, by one man who was very tired.

That is the honest value of instrumenting anything. Not the dashboard. The moment
the dashboard shows you your own sloppiness back.

## This is not the first interface. It is the fifth.

Here is the part that I think is genuinely unhinged, and I say that with
affection for the person who did it: the swamp extension is the *newest* way I
have to track this child, not the only one, and not by a wide margin.

There is a **mobile app** — a Capacitor wrapper around Baby Buddy with the sharp
edges filed off. Biometric lock so a phone left on the couch doesn't show the
whole night's log. Siri intents, so "log a diaper" is a sentence you say into the
air with both hands full, which is the only state your hands are ever in. Live
Activities, so a running feeding timer ticks on the lock screen next to the
elapsed time you are trying not to look at.

There is a **Pebble watchapp**, because I have a Pebble again and it turns out the
best interface for logging a feed at 3 a.m. is a physical button on your wrist
that does not emit a single photon more than necessary. Start a timer, stop it,
pick the amount, done — without the wake-up-your-whole-nervous-system brightness
of a phone. There is a Pebble smart *ring* on order for the same reason. I am not
going to defend the ring. The ring defends itself.

There is a **conversational server** — an MCP that lets me (or Claude, or the
voice assistant it hangs off of) just *say* what happened. "He ate ninety at
eleven." It writes the same feeding record the app would, the same one the watch
would, the same one the swamp model syncs back out.

And there is **Home Assistant**, which is the layer that nags. At 10:30 it
reminds whoever is still vertical to prep the overnight bottle. At 11 it reminds
us the vitamin D goes *in* that bottle — the vitamin D of at least three names.
If nobody acknowledges it, it asks again. It is, functionally, a very polite
robot co-parent with a clipboard.

Five interfaces. One baby. Every single one of them a different door into the
same little REST API.

## Why any of this

You could read all of that as a man building toys instead of sleeping, and you
would not be entirely wrong. But there is a real thing underneath it, and it is
the least technical thing in this whole post.

A newborn is a 24-hour operation run by two people who are each getting about
five hours of sleep in shifts. The single hardest part is not any one feeding.
It's the *handoff* — the 1 a.m. moment where one of us goes horizontal and the
other picks up the watch, and the only way that works is if we are both looking
at the same set of facts. When did he last eat. How much. Is he due. Did the
vitamin D happen or did I dream that.

All of this tracking — the app, the watch, the voice, the nags, and now the
swamp — is not quantified-self vanity. It is a shared source of truth for two
exhausted adults trying to hold one continuous story between them across a
shift change, in the dark, without waking each other up to ask. The
instrumentation is the coordination layer. The baby is just where the data
happens to come from.

## The bit worth keeping

If there's one engineering lesson that survived contact with a real newborn, it's
the same one from the certificate post, wearing a smaller hat: **data that claims
to be complete when it isn't is worse than no data.**

When I built the `sync` method, it capped each query at some number of records. A
sensible default, until you imagine a parent syncing a long window, quietly
losing the oldest entries, and getting a report that looks whole. So the snapshot
carries a `truncated` flag now — an honest "there was more than this" — and the
summary says so out loud instead of lying with a clean-looking table. A review
pass caught it before it shipped, which is the entire reason to have a review
pass.

The same instinct is why `delete-entry` swallows a 404 and calls it done. Two
parents, two devices, one baby — someone *will* delete the same thing twice. The
tool's job is to make the second delete boring, not to punish you for the racing
condition of being a family.

He's asleep right now. Twenty-two minutes in, per the timer on my wrist, which I
will not be checking again, because that would wake the report, which would wake
me. The extension is [open source on the swamp
registry](https://github.com/NeilHanlon/swamp-babybuddy) if you also run Baby
Buddy and also cannot leave a working REST API alone.

---

I do infrastructure and automation for a living through [my consulting
practice](https://shrugpw.com) — the kind of instrumentation that is nominally
for adults. The methodology, it turns out, is identical. There is just less
spit-up.

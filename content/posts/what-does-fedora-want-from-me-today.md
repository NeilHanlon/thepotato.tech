---
title: "What Does Fedora Want From Me Today?"
description: "I taught swamp to read Fedora (accounts, Bugzilla, the packager dashboard) so one command tells me what my packages need. The answer was 135 things."
date: 2026-07-14T13:54:48-04:00
draft: false
categories: ['open-source', 'automation']
tags: ['fedora', 'swamp', 'packaging', 'bugzilla', 'rpm', 'devops', 'adhd']
---

I began contributing as a packager with Fedora a few years ago, in concert with
my participation in founding and bootstrapping Rocky Linux from the ground up.
That alone deserves a blog post series I may write some day... but more to the
point... I haven't done a great job of maintaining my packages. There's a host
of reasons I could get into for why, but particularly in light of having a
newborn and therefore much more limited time and energy than I ever thought was
possible, optimizing my workflows and maximizing my impact (and reducing
ownership of things where needed) are the most powerful knobs I can use to make
the greatest difference not just in Fedora but across all the things I involve
myself with.

As many of these things go, I turned to the swamp.

## The problem

Fedora is by its nature a distributed consensus model playing out in real life.
It moves constantly, and can be really hard to keep up with. There are attempts
to help with this, and they deserve talking about: everything that happens in
the project lands on the [fedora-messaging](https://fedora-messaging.readthedocs.io/)
bus, [datanommer](https://github.com/fedora-infra/datanommer) archives all of
it, datagrepper lets you query the archive, and [Fedora Notifications](https://notifications.fedoraproject.org/)
will happily email you about any of it. And then there's the
[Packager Dashboard](https://packager-dashboard.fedoraproject.org/), which does
the actually-hard aggregation work (dist-git, Bodhi, Koschei, Bugzilla, crash
reports) and presents it per-packager. These are good tools built by people who
understand the problem.

But at the end of the day, pulling together all of these sources of information
into a single "pain of glass" is a difficult problem, particularly if you have
ADHD and might spread yourself a bit thin in the best of times with various
interests. The bus and the notifications are push: streams and inboxes, more
things arriving whether or not I'm ready for them. What I actually needed was a
pull... one command I run when I have the spoons for it, that answers "what
does Fedora want from me today?" and writes the answer down somewhere I can
diff later.

## CVEs, Bugs, and FTBFS... oh my!

So here's where I ended up:

```sh
swamp workflow run fedora-attention
swamp report get "@kneel/fedora-packager-dashboard/attention" \
  --model fedora-dash --markdown
```

...and here's a real excerpt of what came back:

```markdown
# Fedora attention — neil

- **Actionable items:** 135 across 66 packages
- **Open bugs:** 96 · **PRs:** 24 · **Build failures:** 15
- **Snapshot:** 2026-07-13T15:11:48.390Z

## Security / CVE (32)
- **d2** #2455622 — CVE-2026-34986 Go JOSE: DoS via crafted JWE object
- **grpc** #2408295 — CVE-2025-58189 go crypto/tls ALPN negotiation ...
  (30 more)

## FTBFS / build failures (7)
- **xastir** #2435195 — xastir: FTBFS in Fedora rawhide/f44
- **slurm** #2484402 — F45FailsToInstall: slurm
  (5 more)

## Top packages by attention
| Package | Bugs | PRs | Build fails | Total |
| ------- | ---- | --- | ----------- | ----- |
| grpc    | 12   | 5   | 4           | 21    |
| slurm   | 13   | 1   | 0           | 14    |
| d2      | 11   | 0   | 2           | 13    |
```

135 actionable items across 66 packages. Cool. Cool cool cool.

Weirdly, though, seeing it all at once made the whole thing feel smaller. Most
of those 32 CVEs are the same handful of Go stdlib and golang.org/x vulns
fanned out across every Go package I touch (`d2` and `grpc` between them
account for the bulk of it), so in practice it's more like two or three
rebuild-and-update passes than 32 separate crises. The FTBFS list is seven
entries across five packages, two of which are `xastir` reminding me that the
ham radio software needs love again (it always needs love again).

### Whose packages are these, anyway?

Funny thing about `d2`, actually: I don't own it directly at all. I went and
checked the snapshot — its entry says `users: []`, `groups: ["mkdocs-sig"]` —
so it lands on my list purely through a SIG I'm in. And once I knew to look,
it turns out 41 of my 66 packages are the same way: all mkdocs-sig, accounting
for 49 of the 135 items. My *personal* queue is really 25 packages and 86
items. Which means the report already has its first improvement queued up: it
doesn't distinguish *why* a package is mine — direct ownership versus
inherited through a group ACL — and that distinction changes what I actually
do about an item. A CVE on a package I personally own is my problem; the same
CVE on a group-maintained package mostly means checking whether someone else
in the SIG is already on it. The best part is the data's already sitting in
every snapshot (each package entry carries its `users` and `groups`), so the
fix is pure rendering. More on extending the report below.

### The shame table

`grpc` deserves its own aside, because it's the poster child for everything
this post is about. It sits at the top of the attention table with 21 items,
and it's a giant pain to maintain, largely because of protobuf, which it's
chained to, and which has an ongoing Fedora change effort against it and has
been behind upstream for years. I picked grpc up knowing some of that, and I've
been going back and forth on dropping it ever since: its surface is huge and I
don't particularly have the time it deserves. Looking at it holistically in the
report, it feels like a smaller problem than it does when it's ambushing me one
bugmail at a time... sorta. I still might drop it. At minimum I'll be asking
for co-maintainers (consider this the soft launch of that ask).

And that "top packages by attention" table doubles as a divestment worksheet:
if `slurm` generates 14 items a cycle and I haven't used it in years, the
kindest thing I can do for Fedora is help it find a better home. Remember what
I said up top about reducing ownership? The report is how I'm actually going to
do it, instead of just feeling vaguely bad about it. The good news is there's an
active group (OpenHPC) that has a vested interest in slurm and so the
co-maintainer pool is deeper than most.

### What one run actually does

The `fedora-attention` workflow behind the two commands up top refreshes three
models in one shot: the dashboard snapshot (which regenerates the attention
report as a side effect), the bugs assigned to me in Bugzilla, and my current
FAS group membership. Every run is versioned data in the swamp datastore, so a
month from now I can diff what Fedora wanted against what Fedora wants...
which will either be a burndown chart or a horror story. I plan to publish it
either way.

## Data-gathering and AI fan-out

Full disclosure: I didn't type most of the *code* by hand (these words, yes...
the TypeScript, no). I've been running Claude agents against my swamp
workspaces for a couple weeks now — the same setup that
[issued my WiFi certificate]({{< ref "the-wifi-cert-that-didnt-exist-an-hour-ago" >}})
and [put my son in a swamp]({{< ref "i-put-my-son-in-a-swamp" >}}) — and this
went the same way. I described the three planes I wanted (identity, bugs,
packages), and agents went off to research the APIs and build read-only models
in parallel while I did other things (changing diapers, probably), with me
wandering back periodically to say "no, not like that." and "good god why would
you think this is a good idea?!"

What landed:

- `@kneel/fasjson` — Fedora Accounts over the FASJSON REST API. Who am I,
  what groups am I in, who else is in this group.
- `@kneel/bugzilla` — Red Hat Bugzilla's REST API. My account, my assigned
  bugs, and open bugs across every component I maintain.
- `@kneel/fedora-packager-dashboard` — the Packager Dashboard's public
  Oraculum v2 API, which does the cross-source aggregation so I don't have to.
  This one was also the durable choice on purpose: it sits *above* dist-git,
  so it survives the Pagure→Forgejo migration that a direct dist-git model
  would not.

All three are read-only on purpose. I want to watch this stuff for a good
while before I let anything mutate it, if I ever do.

The research pass surfaced the kind of API trivia you only learn by actually
integrating, and it's now baked into the models so nobody has to learn it
twice. Red Hat's Bugzilla only accepts `Authorization: Bearer` header auth
now; the legacy `?Bugzilla_api_key=` query param that half the example code on
the internet still uses gets you an HTTP 400. There's no `/whoami` endpoint
(404), so identity goes through `/user?match=`. `component` comes back as a
JSON array even when there's exactly one. And the dashboard's first uncached
query for a packager can take tens of seconds while Oraculum pulls live data,
which is worth knowing before you decide it's hung. As far as I can tell none
of this is written down in any one place, but now it's encoded in TypeScript
with tests, which is arguably better.

(The Bugzilla token lives in a swamp vault — backed by PasswordStore and my
GPG key — and reaches the model through a CEL expression:
`vault.get("bugzilla", "API_TOKEN")` — so it's never in a model definition,
my shell history, or git.)

### Your own fedora-attention report

The extensions are on the swamp registry, so if you're a Fedora packager who
also wants a morning number:

```sh
swamp extension pull @kneel/fedora-packager-dashboard

swamp model create @kneel/fedora-packager-dashboard fedora-dash \
  --global-arg users=<your-fas-username>

swamp model method run fedora-dash dashboard
swamp report get "@kneel/fedora-packager-dashboard/attention" \
  --model fedora-dash --markdown
```

The dashboard API is public (no token, no Kerberos) so that part works with
zero credential setup. The model takes `users`, `groups`, or `packages`
selectors, so you can point it at a whole SIG (`groups=go-sig`) or a package
set instead of a person. Add `@kneel/bugzilla` with a vaulted token if you want
your assigned-bugs list next to it, `@kneel/fasjson` for the accounts plane,
and wire them into a workflow like my `fedora-attention` so one command
refreshes everything.

And if the report doesn't slice things the way your brain wants (mine is tuned
for "CVEs first, then broken builds, then a shame table"), you can reshape it.
The attention report is one small TypeScript file that reads the latest
`dashboard` snapshot out of the datastore and renders markdown, and every
`sync`'d category — Bodhi updates, Koschei state, orphans, new upstream
releases, crash reports — is already sitting in that snapshot, unrendered.
Grab the source, copy the report into your own workspace's
`extensions/reports/`, and go to town; swamp picks it up on the next bundle,
and the model doesn't care how many reports read it. You can also add methods
to the model itself with `export const extension` if you want a different
slice of the API. If you build something generally useful, send a pull
request. "Orphan candidates sorted by attention-per-month-of-neglect" is
sitting right there, and so is the one I owe myself from the `d2` discovery
above, so group-inherited noise stops masquerading as personal debt.

## The duct tape I could hear

The big lesson is the thesis of this whole series: modeling a system forces
you to actually understand it. And when your attention is the bottleneck,
versioned pull beats well-intentioned push every time.

The smaller lesson is the one that wouldn't leave me alone. Two of the three
models are pure `fetch`, no dependencies. The third isn't. FASJSON speaks
*only* Kerberos/GSSAPI — every endpoint answers `WWW-Authenticate: Negotiate`,
and there's no password or token fallback of any kind. The standard answer
(the one every integration I've ever seen uses) is to shell out: `kinit`, then
`curl --negotiate`, and now your model depends on a subprocess, an ambient
credential cache, and whether the machine happens to have krb5-workstation
installed. That's what my model did. It worked. It was also the only part of
the whole build that felt like duct tape, and every time the workflow ran I
could hear it.

I got annoyed enough to do something unreasonable about it.

That's the next post.

---

This is what I do for money too, through [Shrug PW](https://shrugpw.com):
making other people's operational queues legible. Fewer ham radio packages,
usually.

---
title: "I Made swamp Deploy swamp"
description: "I stood up 'swamp serve' as its own FreeIPA service account using nothing but swamp models. The tool configured the host that runs the tool, and then my own OAuth flow spent an afternoon trying to lock me out."
date: 2026-09-18T16:29:00-04:00
slug: swamp-as-a-service
draft: true
categories: ['automation', 'infrastructure']
tags: ['swamp', 'freeipa', 'tls', 'oauth', 'systemd', 'dogfooding', 'devops']
---

I run swamp for almost everything at this point. So when it came time to stand up
the swamp control plane itself, as a long-running service on a box in my basement,
there was really only one acceptable way to do it. I was going to deploy swamp
using swamp.

I set exactly one rule going in: no Ansible. No shell scripts I'd forget the shape
of in a month. Every change to the host, the identity, the cert, the systemd unit,
would be a swamp model run with a versioned record I could query later. If the
premise of the whole tool is that modeling a system forces you to understand it,
then the tool deserved to be modeled like anything else.

The goal was `swamp serve` running as its own identity: a FreeIPA service account,
`swamp:swamp`, on the little KVM box I keep for exactly this kind of thing. Central
identity in FreeIPA and SSSD, no personal credentials baked into a daemon, the
whole thing legible after the fact. That was the plan. The plan survived about as
long as plans do.

## Renaming things, which turned out to be free

Before any of the real work, some housekeeping. The models I'd used to bring the
box up were named after the machine's old bad name, all `-tc` this and `-tc` that,
and it bothered me every time I typed it. Normally renaming a stateful thing is a
small act of courage. Here it wasn't, because swamp keys its state by UUID, not by
name. The instance keeps its identity across a rename; the name is just a label you
read. So I renamed the lot to `-thinkcenter` and nothing moved underneath. A
cosmetic change stayed cosmetic. I mention it only because I spent a second bracing
for pain that never came, which is rare enough to write down.

## Issuing the cert through swamp, not around it

`swamp serve` wants TLS, which means a server certificate, which is usually the
point where a clean automation story sprouts a manual step. Somebody SSHes in,
runs `openssl` by hand, copies a key around, and the private key spends the rest of
its life as a file nobody quite remembers creating.

I didn't want the key to exist as a file I owned. So the cert request went through
`@shrug/freeipa` and its `certRequest` method: the RSA keypair is generated inside
the model, the private key is written straight into a vault (pass, in my case) and
referenced afterward by CEL expression, and cert plus key get delivered to the host
through `@adam/cfgmgmt`. The key never touches my local disk in a form I have to
remember to delete. That is the entire reason to do it this way. A secret you never
handle is a secret you can't fumble.

That was the version in my head. The version that met the live CA was less tidy.

## The two bugs the mocks were too polite to find

Both models had test suites. Both suites passed. Both bugs showed up the instant
real FreeIPA was on the other end of the wire, which is the oldest lesson in this
business and apparently one I need re-taught on a schedule.

The first: the audit record swamp writes for a run derives its data-instance name
from the principal. Service principals have a slash in them, `swamp/host` style. A
path-traversal guard in the naming code saw the slash, correctly decided it didn't
want user input containing `/` anywhere near a path, and rejected it. A validator
doing its job perfectly, on input it was never told to expect. The mock principals
in the tests were all tidy user-shaped strings, so the suite never had an opinion.

The second was worse because it fails quiet. `generateCsr` built a certificate
signing request with a common name and nothing else. No Subject Alternative Name.
The CA happily issued against it, the method reported success, and swamp wrote a
green run. Then a modern TLS client took one look at a CN-only cert with no SAN and
refused the connection, because CN-as-hostname has been deprecated for years and
this particular IPA profile does not synthesize a SAN from the CN for you. The fix
was a `dnsNames` argument that actually emits the SAN extension on the CSR.

The lesson I keep relearning: "the method succeeded" is a claim about the method,
not about the artifact. The cert existed. The cert was also useless. Now I verify
the thing itself before I believe anything upstream of it told me:

```sh
openssl x509 -in server.crt -noout -ext subjectAltName
```

If that line doesn't print the name a client will actually ask for, the run was a
lie no matter what color it was.

## Least privilege means you will iterate the ACL

The service account I use for FreeIPA writes, `svc-freeipa-rw`, was deliberately
scoped down to issuing user certificates. That was correct when I set it up. It was
also exactly wrong for the thing I now needed, which was a service cert, and I was
glad to hit the wall, because I had built it on purpose.

So I did the break-glass dance. FreeIPA handed me a 400 and an ACIError naming the
permission it wanted. I added that permission, retried, got the next 400 naming the
next one. "System: Add Services" got me partway; writing the certificate onto the
service entry needed "System: Modify Services" as well, which is not obvious until
the error tells you. I bundled the pair into a new privilege, "swamp service
management," folded that into the "swamp writers" role, and moved on. Each denial
was the ACL teaching me the next thing it wanted. That loop is annoying and it is
also the system working: you don't get the permission until you can name exactly why
you need it.

## Two cfgmgmt footguns, noted for the next person

A couple of things bit me on the config-management side that are worth saying out
loud, because both fail in the direction of looking fine.

`@adam/cfgmgmt`'s `copy_file` and `file` operations don't default the `ensure`
field to anything. Leave it off and the operation decides it has nothing to enforce,
reports "compliant," and does nothing. You get a green run and an empty destination.
I deployed nothing, successfully, for longer than I'd like to admit before I noticed
the file I was sure I'd shipped wasn't there. A no-op that reports success is worse
than an error, because an error at least interrupts you.

The other: running swamp as a non-root service account means the process needs a
working directory it can actually read, or `readSwampSources` throws EACCES on
startup and the whole thing falls over before it does anything useful. The fix is
unglamorous, `runuser` into the account and `cd` into a directory swamp owns, but it
only becomes obvious once you stop running everything as root and start living with
the least-privilege setup you asked for.

## The afternoon my own OAuth locked me out

Here is the one I came to tell you about.

`swamp serve --auth-mode oauth` does a device-code grant on first start. You launch
it, it prints a URL and a short code, you go to the URL, type the code, approve. The
normal, sane, browser-free way to authenticate a headless daemon. I've done it a
dozen times.

I also, reasonably, ran the daemon under systemd with `Restart=on-failure`, because
that is what you do with a service you want to stay up.

These two decisions do not like each other. On first start there's no token yet, so
the process is, from systemd's point of view, failing. systemd restarts it. The new
process mints a brand-new device code, prints it, and waits. I go to the URL and
start typing the code I can see in the journal. systemd, deciding this instance has
also failed, kills it and starts another, which mints another code. The code I'm
carefully entering now belongs to a process that no longer exists.

And it gets worse, because now I'm generating device codes in a tight loop, and the
device endpoint does what any sane endpoint does when hammered: it starts handing
back 400s and rate-limits me. So even the codes that do belong to a live process
can't be redeemed. I sat there for an embarrassing stretch racing a restart loop I
had built, losing, and slowly working out that the tool wasn't broken. The
deployment was.

The actual insight, once I stopped swearing: an interactive first-run bootstrap and
a restart-on-failure unit are fundamentally incompatible. One assumes a human will
take an unbounded amount of time to do a thing exactly once. The other assumes any
process that isn't already healthy should be replaced immediately and forever. You
cannot satisfy both at the same time with the same unit.

There are a few honest fixes. Bootstrap the auth outside the unit, get a token, then
let systemd manage the already-authenticated service. Or set `Restart=no` for the
first run and turn it on afterward. Or skip the interactive dance entirely and use
token auth, mint a server token once, hand it to the daemon, no external device
endpoint in the startup path at all. I went with token auth. For a homelab control
plane that needs to come back on its own after a reboot, an authentication method
that can't be defeated by the restart policy is just the correct call. The device
flow is a lovely piece of UX for a laptop. It has no business in a crash loop.

## The tool configures the host that runs the tool

So it runs now. `swamp serve`, as `swamp:swamp`, with a cert whose SAN I checked by
hand, on a host whose identity, files, and unit were all put there by swamp model
runs. Every mutation along the way, the cert request, the RBAC grant, the file
drops, the unit, is a versioned run I can go back and read, including the two model
bugs I fixed in the middle of doing it. The audit trail contains its own
debugging session, which is either good hygiene or a diary I'll regret, depending on
the day.

<!-- NEIL: if you want receipts here, drop in a real `swamp data` query or a run id showing the certRequest audit record -->

I like this outcome more than I expected to, and not for the reasons I started with.
The point wasn't purity, or avoiding Ansible for its own sake. It was that when the
thing that configures the machine is the same thing running on the machine, the
whole setup stops being a story I tell about the box and becomes something I can
query. The box can tell me what happened to it. I just had to survive my own OAuth
flow to get there.

Until next time.

---

I do this to other people's infrastructure for money through
[Shrug PW](https://shrugpw.com), usually with fewer self-inflicted restart loops.

---
title: "The WiFi Certificate That Didn't Exist an Hour Ago"
description: "I built a family of FreeIPA automation extensions for swamp, then used them to mint my laptop an 802.1X client certificate and walk onto the network — end to end, through code I'd just finished writing. A note on the write-safety pattern that made it safe."
date: 2026-07-10T18:30:00-04:00
draft: true
categories: ['infrastructure', 'automation']
tags: ['freeipa', 'swamp', 'pki', '802.1x', 'eap-tls', 'radius', 'homelab', 'devops']
---

My laptop is on WiFi right now with a client certificate that did not exist an
hour ago. I generated the keypair, my own certificate authority signed it, the
private key went straight into encrypted storage, and the machine walked onto
the 802.1X network and pulled a DHCP lease — all through a tool I had just
finished writing. This is a short note on how that came together, and on the one
piece of engineering I think is actually worth sharing.

## The itch

I run [FreeIPA](https://www.freeipa.org/) at home — my own Kerberos realm, LDAP
directory, and certificate authority, the same identity stack a lot of companies
run in the large. It is a genuinely great piece of software. It is also, in my
setup, operated entirely by hand: `kinit`, the `ipa` CLI, a shell script when I
am feeling fancy. Every user certificate, every group, every bit of it is a
human typing commands and hoping they remembered the flags.

I wanted it declarative. I wanted to describe an identity object and have
something reconcile it, keep a versioned record of what happened, and let me
wire one piece of infrastructure into the next.

## What swamp is, briefly

[swamp](https://github.com/swamp-club/swamp) models real resources as typed
objects with methods — create, read, mutate — and captures every run as
versioned data you can reference from other models. You extend it in TypeScript.
Think of it as the good parts of infrastructure-as-code without pretending the
world is a static graph. FreeIPA had no coverage in the registry, so this was
greenfield.

## A family, not a monolith

FreeIPA is a platform, not a service, so I split the work into a family of small
packages rather than one god-model. The first, `@shrug/freeipa/domain`, is
read-only: it logs into the JSON-RPC API and snapshots the realm, the server
inventory, and the replication topology. "Understand the domain" before you
touch it.

Then the interesting ones, the packages that *write*: `user`, `group`, and
`cert`. I split certificates into their own package on purpose — in FreeIPA a
certificate can be issued to a user, a host, or a service, so binding cert
issuance to the "user" model would have been wrong the moment I wanted a device
cert.

I built the three write packages in parallel — three agents, three repositories,
each mirroring the structure of the read-only one and each carrying a
byte-for-byte identical "write-kernel." That shared kernel is where the real
thinking went.

## The part worth sharing: how do you safely persist a mutation?

Here is a question that sounds trivial and is not: when a mutating operation
runs, *when* do you write down what happened?

The default guidance — swamp's, and honestly most people's instinct — is **throw
before you write**. If the operation fails, persist nothing, because a stored
record that claims success the world did not deliver is a lie that downstream
consumers will read and act on. That rule is correct, and I kept it. Mostly.

Because two cases quietly break its assumption.

**Irreplaceable material.** When I issue a certificate, the model generates a
fresh private key, sends the signing request, and the CA signs it. The
certificate now *exists*. If any step after that throws and I had followed "throw
before writing," I would lose the only private key that matches a certificate
that is already real. Here the safe-sounding rule is actively destructive. The
right principle is the opposite: persist irreplaceable state the instant it
becomes real, before anything else can fail.

**Partial failure.** One of the operations creates a steering group as *both* a
user-group and a host-group — two independent calls. If the first lands and the
second errors, "it failed" is true but useless; what you need to know is which
half exists so you can reconcile it.

So the kernel follows a three-way rule instead of a slogan:

1. **State** — the object itself — is written only on success. A failed mutation
   never publishes misleading state. (The original rule, intact.)
2. **Irreplaceable material** — a generated key, a signed cert — is persisted the
   moment it is real, before any later throw can eat it.
3. An **audit record** is written on *both* paths, success and failure. It is
   telemetry, not state; when it says `success: false` it is telling the truth,
   so persisting it on failure violates nothing.

The slogan is right until the domain proves it wrong in a specific, nameable
way. Then you deviate on purpose, and you write down why.

## The payoff

With that in place the actual automation is almost boring, which is the goal.
One method idempotently ensures the VLAN-steering group exists as both a
user-group and a host-group, swallowing "already exists" so re-runs are safe.
Another generates an RSA keypair and a PKCS#10 request in-process, submits it to
the CA, and stores the resulting private key **encrypted in my secret store** —
never in plaintext, never in the model's own data.

Then the last mile, by hand because it should be: pull the signed certificate
and the key out to files, point NetworkManager's EAP-TLS profile at them, and
bring the interface up. The RADIUS server validated the certificate against my
CA, said yes, dropped me on a VLAN, and DHCP did the rest. I was online — on an
SSID with a potato in the name, because this is *my* network and I make the
rules.

A certificate that did not exist when I started the afternoon, issued by
infrastructure I automated the same afternoon, carrying a laptop onto the
network. That is the whole loop, closed.

## Why bother

I could have typed the `ipa` commands. I have, many times. But automating a thing
is how you are forced to actually understand it — every flag you were cargo-culting,
every failure mode you were getting away with ignoring. The write-safety pattern
above did not come from wanting clever code; it came from asking "what happens if
this throws *here*" until the answer stopped being "you lose your private key."

The packages are open source on the swamp registry. If you run FreeIPA and want
to stop operating it by hand — or if you just like arguing about when to persist
a failure — come find me.

---

I do this kind of infrastructure and automation work through
[my consulting practice](https://shrugpw.com), and I am around the usual places
on the internet.

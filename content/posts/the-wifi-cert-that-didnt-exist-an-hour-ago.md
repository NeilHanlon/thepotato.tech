---
title: "The WiFi Certificate That Didn't Exist an Hour Ago"
description: "I taught swamp to drive FreeIPA, then used it to issue my laptop an 802.1X client cert and get onto my own network. Mostly this is about knowing when to write things down."
date: 2026-07-10T18:30:00-04:00
draft: false
categories: ['infrastructure', 'automation']
tags: ['freeipa', 'swamp', 'pki', '802.1x', 'eap-tls', 'radius', 'homelab', 'devops']
---

My laptop is on WiFi right now on a certificate that didn't exist an hour ago. I
made the keypair, my own CA signed it, the private key went into my secret store,
and the machine authenticated onto the 802.1X network and pulled a DHCP lease —
all through code I'd finished writing about twenty minutes earlier. I want to
talk about the boring part that made it safe, because the boring part is the only
part I'd defend.

## The itch

I run [FreeIPA](https://www.freeipa.org/) at home. Kerberos realm, LDAP, a CA —
the same identity stack plenty of companies run, except mine is operated entirely
by hand. `kinit`, the `ipa` CLI, a shell script when I'm feeling fancy. Every
cert, every group, every bit of it is me typing commands and hoping I remembered
the flags. It works, and it's also exactly the sort of thing I'll fat-finger at
11pm.

I wanted it declarative: describe an identity object, have something reconcile
it, keep a record of what it did, and let me wire one piece of the homelab into
the next.

## swamp, quickly

[swamp](https://github.com/swamp-club/swamp) models real resources as typed
objects with methods — create, read, mutate — and keeps every run as versioned
data other models can read. You write extensions in TypeScript. It's the good
parts of infrastructure-as-code without the pretense that the world holds still.
FreeIPA had nothing in the registry, so I got to start from scratch, which is my
favorite way to start.

## Not one model, a family

FreeIPA is a platform, not a service, so I split it into a few small packages
instead of one enormous one. `@shrug/freeipa/domain` is read-only: it logs into
the JSON-RPC API and snapshots the realm, the server inventory, the replication
topology. Understand the domain before you touch it.

Then the ones that write: `user`, `group`, and `cert`. Certs got their own
package on purpose — in FreeIPA a certificate can belong to a user, a host, or a
service, so hanging cert issuance off the "user" model would have been wrong the
second I wanted a device cert. (I wanted a device cert.)

I built the three write packages at the same time, in parallel: three agents,
each in its own git worktree, each cloning the shape of the read-only package and
each carrying an identical copy of the same "write-kernel."

### What the write-kernel actually is

That last bit needs unpacking, because "byte-for-byte identical write-kernel" is
the kind of phrase that sounds like it means something and might not. It's not a
shared library — each package vendors its own copy. It's a small module that
every write goes through: it takes the mutation you want, runs it, and decides
what gets persisted and when. Same code, same rules, in all three packages, so
"how do we write things down" gets answered once and copied, not reinvented three
times slightly differently. Why it's worth copying is the next section.

## The actual point: when do you write it down?

Here's a question that sounds trivial and isn't: when a mutating operation runs,
*when* do you record what happened?

swamp's default guidance — and honestly most people's reflex — is throw before
you write. If the op fails, persist nothing, because a stored record claiming a
success the world never delivered is a lie, and downstream models will read that
lie and act on it. That's correct, and I kept it. But it quietly assumes every
kind of "what happened" wants to be written at the same instant, and two of them
don't.

The first is **irreplaceable material.** When I issue a cert, the model generates
a fresh private key, sends the signing request, and the CA signs it. The cert
exists now. If something after that throws and I'd followed "throw before
writing," I'd have thrown away the only private key that matches a certificate
that's already, really, out in the world. So that one flips: write the
irreplaceable thing the moment it's real, before anything else gets a chance to
fail.

The second is **partial failure.** One operation creates a steering group as both
a user-group and a host-group — two separate calls. If the first lands and the
second blows up, "it failed" is technically true and completely useless. What I
need to know is which half exists, so I can go fix the other one.

So the kernel follows three rules instead of a slogan:

1. **State** — the object itself — is written only on success. A failed mutation
   never publishes state that says otherwise. (The original rule, untouched.)
2. **Irreplaceable material** — a generated key, a signed cert — is written the
   moment it's real, before any later throw can eat it.
3. An **audit record** is written on *both* paths, success and failure. It's
   telemetry, not state; when it says `success: false` it's telling the truth, so
   writing it on failure isn't lying about anything.

That's the whole idea. "Only write on success" is a fine default right up until
the domain hands you a case where it's actively wrong — and then you break it on
purpose and leave a comment saying why.

## The payoff, which is deliberately boring

With that in place the rest is unglamorous, which was the goal. One method makes
sure the VLAN-steering group exists as both group types and shrugs off "already
exists" so I can re-run it. Another generates an RSA keypair and a PKCS#10 request
in process, hands it to the CA, and stashes the resulting private key encrypted in
my secret store — never in plaintext, never in the model's own data.

Then the last mile, by hand, because it should be: pull the signed cert and key
out to files, point NetworkManager's EAP-TLS profile at them, bring the interface
up. RADIUS checked the cert against my CA, said yes, dropped me on a VLAN, and
DHCP did the rest. Online — on an SSID with a potato in the name, because it's my
network and I get to name the SSID.

A certificate that didn't exist when I sat down, issued by infrastructure I
automated the same afternoon, carrying my laptop onto the network. Loop closed.

## Why bother

I could have typed the `ipa` commands. I have, a hundred times. But automating
something is how you're forced to actually understand it — every flag you'd been
copy-pasting on faith, every failure mode you'd been quietly getting away with.
The write-safety stuff up top didn't come from wanting clever code. It came from
asking "what happens if this throws *here*" over and over until the answer
stopped being "you lose the private key."

And yes, I can hear it: *you could do this with Ansible.* I could do this with
Ansible. I *have* done this with Ansible — there's a `freeipa` collection, it's
real, it works. You **should** do this with Ansible... probably? I went with swamp
because I wanted the versioned data and the models that read each other, and a
playbook doesn't hand me that. But if you just need certs issued and you already
live in playbooks, nobody's going to arrest you for reaching for the boring tool.

The packages are open source on the swamp registry. If you run FreeIPA and want
to stop hand-driving it — or you just like arguing about when to persist a
failure — come find me.

---

This is what I do for money too, through [Shrug PW](https://shrugpw.com): bigger
networks, fewer potatoes.

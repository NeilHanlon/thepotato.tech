---
title: "I Violated the Geneva Conventions by Implementing Kerberos in TypeScript"
description: "The FASJSON model only spoke Kerberos, so my swamp had to kinit. I got annoyed enough to reimplement the client half of GSSAPI in TypeScript with no subprocess, and then the immutable datastore started fighting back."
date: 2026-08-01T20:40:00-04:00
slug: kerberos-in-typescript
draft: false
categories: ['automation', 'infrastructure']
tags: ['swamp', 'kerberos', 'gssapi', 'fedora', 'fasjson', 'freeipa', 'typescript', 'security']
---

A couple weeks ago I shipped a [swamp]({{< ref "what-does-fedora-want-from-me-today" >}}) workflow
that tells me what Fedora wants from me on a given day. Three models fan out
in parallel, pull bugs and builds and package state, and one command writes a
markdown snapshot I can diff against last week's. It's the workflow I wanted,
and it runs every time I have the spoons for it.

Two of the three models are pure `fetch`, and carry no external dependencies. The third isn't.
The FASJSON service speaks *only* Kerberos/GSSAPI: every endpoint requires
`WWW-Authenticate: Negotiate`, and there's no password or token fallback of any
kind. The standard answer (the one every integration I've ever seen uses) is to
shell out: `kinit`, then `curl --negotiate`, and now your model depends on a
subprocess, an ambient credential cache, and whether the machine happens to have
krb5-workstation installed.

That's what my model did. It worked. It was also the only part of the whole
build that felt like duct tape, and every time the workflow ran I could hear it.

I got annoyed enough to do something unreasonable about it. Fair warning: I
didn't hand-write most of what comes next so much as specify it, argue with it,
and try to break it. Keep that in mind. It turns out to be the point.

## Why not just shell out?

This isn't (just) an aesthetic complaint. Shelling out to `kinit` has real
failure modes, and they're the kind that suck when it's 2am and you're
half-asleep and the service is down again because someone (me) insisted on
using kerberized postgresql but the ticket refresh failed.

The ambient `KRB5CCNAME` cache is shared mutable global state your model doesn't
own. Two runs in parallel step on each other. A stale cache from a previous run
silently authenticates as the wrong principal, and the failure mode is "the API
said no" with no useful signal about why.

Moreover, it depends on host packages and PATH. The extension isn't
self-contained anymore; it's a TypeScript file that happens to need
krb5-workstation installed on the box. That breaks the model-is-the-dependency
promise, and it means your CI Dockerfile needs a `RUN dnf install
krb5-workstation` line that has nothing to do with your actual problem.

Credentials live outside swamp's vault and secret machinery. The password is in
a vault, fine, but the moment it hits `kinit` it's in a file on disk that the
datastore doesn't know about, can't version, can't rotate, can't tell you is
there. That's state that only looks managed, which is arguably worse than none.

The thesis of this series is that modeling a system forces you to actually
understand it. A subprocess lets you skip that.

## What I actually built

First, the honest version of "I wrote Kerberos," because that phrasing is doing
a lot of work. I did not type an ASN.1 DER encoder from memory. I said what I
needed, a model produced most of the code, and I spent my time on the part I'm
actually good at: reading the spec like it owed me money, deciding what had to be
constant-time, and trying to break the result until it stopped breaking.

That division of labor bothers some people. It stopped bothering me once I worked
out why, and the why is narrow on purpose. A working crypto implementation is a
bitstring: a client that either produces a valid AS-REQ or doesn't, either checks
the MAC in constant time or leaks. For an object like that, the channel that
emitted the bits is noise. What survives is whether they're correct, and
correctness here is verifiable no matter who or what typed it. I can verify it.
Verifying and breaking is the scarce skill; typing the DER never was.

I want to be careful with that, because "the outcome is all that matters" is how
you talk yourself into genuinely bad things everywhere the outcome *isn't* the
whole story. This is not that argument. It's the boring, bounded version: for a
byte string whose correctness you can fully check against a spec, provenance
carries no information the verification doesn't already recover. That's a claim
about code, not about conduct.

So... scope: I didn't write a full Kerberos stack (insofar as _I_ "wrote"
anything.) It's just the client-initiator half of GSSAPI: AS-REQ/AS-REP to get
a TGT, TGS-REQ/TGS-REP to mint a service ticket for a specific SPN, and SPNEGO
wrap into the `Authorization: Negotiate` header. No `child_process`. No
`krb5.h`. Just some `fetch`, a sprinkle of WebCrypto, and a bowl full of bytes.

The real crypto is there: aes256-cts-hmac-sha1 and aes256-cts-hmac-sha384 (the
FIPS-relevant etypes), PBKDF2 string-to-key per RFC 3962, and "hand"-rolled DER
encode/decode of the ASN.1 because no TypeScript ASN.1 library does the job
without dragging in a universe of dependencies. I won't pretend that was fun. It
was correct, which is the next best thing (probably).

The tests are the credibility, and balance out the obvious software war crimes
under review. We've got _all_ the paranoid classics:

- RFC and NIST known-answer tests for the crypto layer: RFC 6070
    for PBKDF2, RFC 3962 intermediate outputs, exhaustive CTS padding lengths.
- Every-byte tampering tests on the ciphertext.
- Wrong-key, wrong-usage, and wrong-truncation tests that check the MAC
    actually rejects bad input instead of passing it through.
- "Hand"-derived DER fixtures for the ASN.1 layer,
    so a regression in encoding shows up as a test failure instead of a
    KDC rejection at runtime. 
- Mock KDCs that do real crypto rather than return stubbed responses.

And then gated live tests against the real KDCs in my lab, because the mock is only
as good as the assumptions I made writing it.

The tally came to 176 tests in the end. Overkill--until a KDC sends back something the mock didn't
predict and the suite already has a case for it.

And then... it worked. The same `fedora-attention` workflow from the last post, the
one that used to shell out to `kinit`, now gets `groups:neil = 20` real groups
back over a `Negotiate` header this very code minted. No kinit anywhere on the box.
No ambient cache. No bet about whether krb5-workstation is installed.

## The datastore fought back

As _everyone_ knows... (_ducks_), Kerberos credentials are short-lived, mutable
secrets. But Swamp's datastore is _immutable_ and versioned: every write kept
forever. Those two facts do not want to be friends, and most of the hardening
below is me negotiating the peace (with varying degrees of success.)

Session keys, tickets, and the SPNEGO header are all secret, but the first cut
of this extension leaned on datastore-level encryption instead of swamp's
own vault. Ew. Yuck. No plz.

The fix was field-level `sensitive` marking so only the truly-secret fields get
vaulted (nested fields included) while non-secrets stay plaintext and
debuggable. Of course, fixing the code wasn't enough: the store is immutable, so
pre-fix runs had already written real tickets in cleartext into version
history, and the code fix only covered new writes. An immutable store doesn't
do "erase that entire personal log," so I swept the history by hand too (and
this time I really do mean by hand). Same "data that lies by looking complete"
instinct as [the baby post]({{< ref "i-put-my-son-in-a-swamp" >}}): the
snapshot said it was fine, and it wasn't.

The clanker decided to create credentials with `lifetime: infinite`, and
`destroy` only removed the TGT, leaving minted service tickets behind in the
datastore. I chose to bound the ccache and service tickets to 24 hours, and the
SPNEGO header to 1 hour since it's the most exposed, and made teardown sweep
everything via a per-principal ledger instead of deleting the root and hoping.

The rest isn't the datastore's fault, but I can't help myself from paranoid
bugfixing on a good day, and we already had it up on the lift, so...

Constant-time MAC compare. The Kerberos integrity check is an HMAC, and comparing
HMACs with `===` leaks timing an attacker can use to forge one. The fix is a
single line — `crypto.subtle.timingSafeEqual` or a byte-by-byte accumulator — but
I didn't think to write it until I'd read the spec three times.

Bounded PBKDF2 iterations. A hostile KDC controls the iteration count through the
RFC 3962 s2kparams field, and if you don't cap it you'll happily run for hours.
The cap is 1,000,000 iterations, sub-second worst case at PBKDF2-HMAC-SHA1, and a
legitimate KDC never exceeds the RFC default of 4096. The suite verifies that the
cap rejects, the boundary computes, and zero iterations (which RFC 3962 says means
2^32) gets rejected cleanly instead of hanging.

And lastly, the least-privilege bit, with a twist. I made `forwardable` and `renewable`
opt-in, off by default, because that's what the spec says you should do. Then I
found that FASJSON *requires* a forwardable ticket, because it delegates the user
credential to bind IPA LDAP over SASL/GSSAPI. Turning it off broke it in exactly
the way that teaches you what delegation is. The flag is still opt-in, but the
error message when you forget it now says "FASJSON needs forwardable tickets
because it delegates to LDAP" instead of "nope."

A genuine platform bug fell out of this and got fixed upstream. swamp
[#1169](https://swamp-club.com/lab/1169) →
[PR #1866](https://github.com/swamp-club/swamp/pull/1866): cross-run reads of a
vaulted field returned the unresolved `${{ vault.get(...) }}` ref string instead
of the resolved value, and per-instance vault keys collided when two models
vaulted to the same slot. Mapping a real credential lifecycle onto the datastore
is what surfaced it. I only caught it when I tried to cache a TGT across runs and
the second run couldn't read what the first one wrote.

## The bigger question underneath

Why did any of this matter beyond one stubborn Fedora endpoint? Because a fleet
of swamp workers has FASJSON's problem one level up: how does a worker prove who
it is? For a lot of systems the honest answer today is a bearer token plus a
client-asserted machine id, a secret you copy around and hope nobody else gets.
Which is the exact thing I just spent a week refusing to do for one API.

That's its own argument and it deserves its own room, so I wrote it up separately
as **"From Bearer Tokens to Workload Identity"**: the design case for
FreeIPA-backed worker principals, short-lived service tickets, and constrained
delegation. It's the next post in this series, and will come out precisely when
I mean it to (i.e., eventually.)
<!-- TODO: link to from-bearer-tokens-to-workload-identity once post 2 is draft:false (use a ref shortcode; keep it out of comments so Hugo doesn't try to resolve it), then delete this comment -->
The short version: bearer tokens are what you use when you've decided not to model
identity. Kerberos is what modeling it looks like.

## Try it

`@kneel/krb5` is on the swamp registry (published `2026.07.16.2`). The honest
paragraph on what it is and isn't: client-initiator GSSAPI, single AP-REQ, no
mutual-auth or continuation yet. If you need a Kerberos client in TypeScript and
you're already in swamp, it's there. If you need a full GSSAPI implementation with
mutual auth and context continuation, this isn't it... yet.

The extension pulls the same way the others do:

```sh
swamp extension pull @kneel/krb5
```

A subprocess offended me and I replaced it with a few thousand lines I mostly
didn't type. The tickets it mints are real either way, and that was the only
thing that ever had to be true.

Until next time...

---

This is what I do for money too, through [Shrug PW](https://shrugpw.com): making
other people's operational queues legible. Fewer ham radio packages, usually.

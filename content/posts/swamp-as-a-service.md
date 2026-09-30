---
title: "I Made swamp Deploy swamp"
description: "I stood up 'swamp serve' as its own FreeIPA service account using nothing but swamp models. The tool configured the host that runs the tool, and then my own OAuth flow spent an afternoon trying to lock me out."
date: 2026-09-30T12:56:00-04:00
slug: swamp-as-a-service
draft: false
categories: ['automation', 'infrastructure']
tags: ['swamp', 'freeipa', 'tls', 'oauth', 'systemd', 'dogfooding', 'devops']
---

I run swamp for a _lot_ of things at this point, so when it came time to stand up the swamp control plane itself, a long-running service on a box in my basement, there was really only one acceptable answer: deploy swamp using swamp.

The one rule I set going in was to only use swamp, for everything. No Ansible, and no shell script that makes perfect sense today and becomes archaeological evidence six months from now. Every change to the host, identity, certificate, and systemd unit had to go through a swamp model and leave behind a versioned run I could interrogate later. Partly that was dogfooding, but mostly it was consistency: if my whole argument for swamp is that modeling a system forces you to understand it, then exempting swamp itself seemed rude.

The target was straightforward. `swamp serve` running as `swamp:swamp`, with its own FreeIPA service identity on the little KVM box I keep around for exactly this sort of thing: FreeIPA and SSSD for identity, no credentials of mine stuffed into a daemon somewhere, and enough provenance that I could later reconstruct what I'd done to the box. That was the plan, and it survived about as long as plans generally do.

## Renaming things, which was somehow the easy part

Before doing any of the interesting work, I had some naming debt to clean up. The models that originally brought this box up were all named after the machine's old bad name, so everything was `-tc` this and `-tc` that, and it had been bothering me every time I typed one of them. Which is, of course, an excellent reason to go renaming stateful infrastructure.

Normally that sentence ends poorly. But swamp keys the actual state by UUID rather than by the human-readable name, so the instance keeps its identity and the name is just the label I have to look at. I renamed the lot to `-thinkcenter` and nothing happened, which was precisely what I wanted. The cosmetic change stayed cosmetic. I mention it mostly because I spent a few seconds bracing for consequences that never arrived, and those moments are rare enough in infrastructure work that I feel obligated to document them when they occur.

## Issuing the cert through swamp, not around it

`swamp serve` wants TLS, so I needed a server certificate, and that is usually the exact point where an otherwise respectable automation story grows one weird manual appendix. Somebody SSHes in, runs `openssl`, copies a key somewhere, fixes the permissions, and the private key spends the next five years living as a file nobody quite remembers creating.

I did not want to own that file, so the request went through `@shrug/freeipa` and its `certRequest` method instead. The RSA keypair gets generated inside the model, the private key goes directly into a vault (`pass`, in my case) where I refer to it afterward through CEL, and then the certificate and key get delivered to the host through `@adam/cfgmgmt`. The private key never has to become a temporary file in `$HOME` that I swear I will remember to delete, and a secret I never handle is one I have fewer opportunities to screw up.

That was the version in my head. The version involving an actual FreeIPA CA turned out to be more educational.

## Two bugs the mocks never hit

Both models had test suites, and both suites passed. Both bugs surfaced the instant I pointed the code at a real FreeIPA, which is apparently a lesson I need to relearn every few years to keep it fresh.

The first one was almost funny. The audit record swamp writes for a run derives its data-instance name from the principal, and while user principals look nice and boring, service principals contain a slash, in the `swamp/host` style. There is, quite reasonably, a path-traversal guard in the naming code that rejects any `/` in user-controlled input, so it did exactly what it was built to do and rejected the service principal. The tests had only ever handed it nice user-shaped principals, so nobody had previously asked the obvious question: what happens when a completely valid principal looks suspiciously like a path? The answer is that swamp refuses to write the audit record, and I learn something.

The second bug was worse, mostly because it succeeded. `generateCsr` built a certificate signing request with a common name and no Subject Alternative Name, FreeIPA accepted it, the CA issued a certificate, the method returned success, and swamp wrote a green run. Then an actual TLS client rejected the CN-only certificate outright, which is the correct behavior: CN-as-hostname has been obsolete for years, and this particular IPA profile does not helpfully synthesize a SAN from the CN. The fix was adding a `dnsNames` argument and actually emitting the SAN extension in the CSR.

This is another one of those lessons I apparently know but enjoy periodically reproving to myself: "the method succeeded" is a statement about the method, not about whether the artifact it produced is worth a damn. The certificate existed, and the certificate was also useless. So now I look at the actual thing before believing the stack of software that produced it:

```sh
openssl x509 -in server.crt -noout -ext subjectAltName
```

If that does not contain the name a client is actually going to ask for, I do not much care how green the run was.

## Least privilege means occasionally arguing with your own ACL

The FreeIPA service account I use for writes, `svc-freeipa-rw`, had deliberately been scoped down to issuing user certificates. That was good, and also completely insufficient for what I had just decided to do. I needed to create and modify a service principal and issue a service certificate, the account correctly did not have permission to do any of that, and so FreeIPA started handing me 400s with ACI errors telling me exactly what I was not allowed to touch.

Thus began the usual least-privilege dance: add the permission named in the error, retry, get the next error, stare at it, and add that permission too. `System: Add Services` got me through creating the service, and writing the certificate back onto the service entry then needed `System: Modify Services`, which is perfectly sensible once you know you need it and not especially obvious before then. I bundled the pair into a new privilege, `swamp service management`, attached that to the `swamp writers` role, and carried on.

This is mildly annoying while you are doing it, but it is also exactly what I want to happen. The account did not carry a giant "probably enough permissions" blob; it hit a wall, and each time I had to name the specific thing it needed before it was allowed to proceed. I have been on the other side of that design enough times to appreciate the inconvenience.

## Two cfgmgmt footguns

A couple of things on the config-management side also got me, both in the particularly irritating category of "looks successful."

The first: `@adam/cfgmgmt`'s `copy_file` and `file` operations do not default `ensure` to anything, so if you omit it, the operation concludes there is nothing in particular to enforce, reports itself compliant, and does precisely nothing. The result is a green run and an empty destination. I successfully deployed no file at all for longer than I am proud of before I finally checked the host and discovered that the file I was absolutely certain I had just installed was, in fact, not there. A no-op that reports success is substantially more dangerous to me than a hard failure, because at least a hard failure is loud enough that I notice it.

The second was less interesting but still useful. If `swamp serve` runs as an unprivileged service account, the process needs to start somewhere it can actually read, or `readSwampSources` dies with EACCES before the service gets far enough to do anything. The fix is not exactly cutting-edge systems engineering, just `runuser` into the account and `cd` to a directory it owns, but it is the kind of thing root quietly hides for you until the day you finally run something with the privileges you claimed it only needed and the filesystem starts reminding you that permissions are real.

## The afternoon my own OAuth flow tried to lock me out

Anyway. This is the part I actually came here to write about.

`swamp serve --auth-mode oauth` uses a device-code grant on first startup, which is pretty standard headless-service stuff: you launch it, get a URL and a short code, open the URL somewhere with a browser, type in the code, and approve the login. I have used this flow plenty of times and never thought twice about it. I also, very reasonably, put the daemon under systemd with `Restart=on-failure`, because I would like my control plane to come back when it dies.

These are individually sensible decisions that, combined, form a small machine for making Neil angry. On first startup there is no token yet, so the process starts the device flow and waits for me to authenticate. systemd sees a process sitting there not-yet-healthy, decides it has failed, and restarts it, and the new process requests a new device code. I look in the journal, grab the code, open the URL, and start typing, and meanwhile systemd kills that process too and starts another one with a fresh code of its own. The code I am carefully entering now belongs to a process that no longer exists.

I did this more than once before the shape of the problem became apparent, because of course I did. And it gets better: my restart loop was hammering the device authorization endpoint hard enough that it started returning 400s and rate-limiting me, so even when I did catch a code belonging to a process that still existed, I could no longer redeem it in time. I spent an embarrassing amount of time racing a restart loop I had personally configured, and I lost, repeatedly.

Eventually the swearing became less productive and I noticed the fairly obvious design problem: an interactive first-run bootstrap and `Restart=on-failure` are fundamentally incompatible. The first assumes a human may take an arbitrary amount of time to do one thing exactly once, while the second assumes a process that is not already healthy should be murdered and replaced until morale improves. You cannot make both of those assumptions true at the same time inside one unit.

There are a few sane ways out. You can bootstrap authentication manually before putting the service under systemd, then let the unit manage an already-authenticated daemon. You can set `Restart=no` for the first run and change it afterward. Or you can decide that an unattended service should probably use an unattended authentication mechanism, which is the one I went with: token auth. You mint a server token once, hand it to the daemon, and you are done, with no human interaction and no external device-code flow sitting directly in the startup path. For something in my basement that needs to recover by itself after a reboot, that is plainly the right shape. Device auth is a lovely UX for a CLI on a laptop, but it has no business being inside a crash loop.

## The tool configures the host that runs the tool

And so, after all of that, it works. `swamp serve` runs as `swamp:swamp`, with a FreeIPA identity and a certificate whose SAN I have personally stared at, and the account, files, certificate, and unit all got onto the machine through swamp model runs. The cert request is a run, the RBAC changes are runs, the file deployment and service setup are runs, and the debugging session that happened in the middle is, somewhat accidentally, also part of the audit history. Every mutation that got the machine from "generic little KVM box" to "thing running my control plane" has a versioned record I can go back and inspect, which I find more satisfying than I expected to.

If I want to see that cert request in particular, it is one query away. Each `certRequest` run leaves an audit record under the `shrug-cert` model, named after the service principal it was issued for, the same principal whose slash broke the validator earlier:

```sh
swamp data list shrug-cert
swamp data get shrug-cert "$record" --json | jq '.attributes | {serial, notBefore, notAfter, san}'
```

I started this mostly because using Ansible to deploy the thing I keep claiming should replace a bunch of my Ansible would have been aesthetically offensive. But the useful part turned out not to be purity. It is that the setup is no longer a story in my head about what I think I did to this box; the box can, more or less, tell me itself. I just had to survive my own OAuth flow first.

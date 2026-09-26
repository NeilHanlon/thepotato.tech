---
title: "Why I Drive XCP-ng Through swamp and Not an MCP"
description: "Vates shipped a first-party Xen Orchestra MCP. It is read-only and it lives inside a chat window. Here is why I still reach for a swamp model to run my hypervisors, and it is not the reason you think."
date: 2026-09-18T16:29:00-04:00
slug: swamp-versus-an-mcp
draft: true
categories: ['automation', 'infrastructure']
tags: ['swamp', 'xcp-ng', 'xen-orchestra', 'mcp', 'ai', 'devops']
---

Vates shipped an MCP server for Xen Orchestra. First-party, in XO 6.2, announced
on their blog. If you run XCP-ng and you have been anywhere near the current wave
of "let the assistant see your infrastructure," this is the thing you were going
to ask for anyway, and I am glad it exists.

I read the tool list and then I went back to my swamp model.

This post is me explaining why, because the obvious answer ("swamp can write and
the MCP can't") is true but boring, and it is the least interesting thing about
the difference. Let me get the boring part out of the way and then tell you what
I actually think.

## What the MCP is, and what it is for

At the time of writing the XO MCP is read-only by design. It exposes things like
an infrastructure summary, a pool dashboard, listing VMs and hosts and pools with
details, and a documentation search.

<!-- NEIL: reconfirm the XO MCP tool list against the current release at publish -->

That is a genuinely useful thing to have. When I am in a conversation and I want
to know what is running on which host without alt-tabbing to the XO UI, a read
lens I can talk to is exactly right. I am not here to dunk on it. It does the job
it was built for.

The job it was built for is the whole point. An MCP server is a way to hand a
model a set of tools during a conversation. It is a chat-time read lens. My swamp
model is a deterministic control plane. Those are different objects, and most of
the "swamp vs MCP" framing you could build out of this post falls apart the moment
you say that sentence out loud, because they are not competing for the same job.

So before anyone reaches for the pitchfork: this is not an "AI is bad" post. I
build with these tools every day. I reimplemented [a Kerberos client]({{< ref "kerberos-in-typescript" >}}) mostly by arguing with one. My claim is narrower and
more boring than that. The durable execution layer, the
thing that actually mutates your hypervisors, should be deterministic code you can
test and read. The model belongs in front of that layer, proposing actions, not
inside it being the thing that runs them. Agent proposes, swamp executes and
verifies. You can absolutely put an agent in front of a swamp model. I do.

With that said, here is why the control plane is a model and not a tool call.

## Write is the boring reason

Yes: the MCP reads and my `@shrug/xen-orchestra` model writes. It creates VMs from
a template with cloud-init, starts them, stops them cleanly or hard, snapshots,
destroys, and manages VIFs. The MCP can tell you a VM is off. The model can turn
it on. If all you took from this post was "one is read-only," you would not be
wrong.

But read-only is a design choice Vates made on purpose, and it is the right one
for a chat tool. I would not want a language model deciding, mid-sentence, to
`destroy` a VM because it pattern-matched my question as a request. So "it can't
write" is not really a knock on the MCP. It is a reason the two things are shaped
differently, which is the actual subject here.

## The reason I actually care: determinism

A swamp method is code with a fixed contract. Same inputs, same run, every time,
in CI, at 2am, whether or not anyone is watching. It either provisions the VM or
it returns an error I can read, and the next run does the identical thing.

A tool call mediated by a model is a different animal. The model might call the
tool. It might call it with the arguments I meant, or with arguments it inferred.
It might call three tools in an order I did not ask for. Most of the time it is
fine. "Most of the time it is fine" is a lovely property for a chat assistant and
a terrible one for the thing that owns your hypervisor fleet. I do not want my
control plane to have a temperature.

This is the part that does not fit in a feature-comparison table, so it never shows
up in the "MCP vs X" posts, but it is the whole ballgame. You can unit-test a
method. You can code-review it. You cannot unit-test a model's decision to call a
tool, because that decision is not in your repo.

## Composition, provenance, and the parts nobody screenshots

Once the control plane is deterministic code, the good stuff follows almost for
free.

It composes. An XO step in a swamp workflow wires to everything else through CEL
expressions: resolve a VM's UUID, then reserve DHCP for it on the OPNsense model,
then register a read-only deploy key on the Forgejo model, then read a token out
of a vault. That is a directed graph of typed steps across four different systems.
A set of chat tools does not assemble itself into a pipeline like that; it waits
to be invoked, one call at a time, by something with a context window.

It is gated. TLS verification is always on, with no insecure toggle to
accidentally leave flipped. UUIDs get resolved at runtime instead of pasted in and
rotting. There is a verify-before-destroy check so a fat-fingered id does not
delete the wrong guest. There is a pile of injected-fetch unit tests and an
adversarial security review behind it. None of that is glamorous and all of it is
the reason I trust the thing unattended.

It is auditable. Every run drops a data snapshot and a report. When something
breaks, I am reading a versioned record of what the run actually did, not
scrolling back through a chat transcript trying to reconstruct what the assistant
decided and why. Reruns are idempotent, so "run it again" is a safe sentence.

And the secrets stay out of the prompt. The XO auth cookie comes from a vault and
is referenced by the model. It never lands in a context window, which matters more
every time you remember that context windows get logged.

The unattended part deserves its own sentence, because it is where the two worlds
stop overlapping entirely. My swamp workflows run on a schedule, headless, through
`swamp serve`. There is no human and no chat. An MCP fundamentally needs an
assistant on one end and a person on the other. That is not a flaw in the MCP. It
is a description of what a chat tool is.

## The proof is a migration I already did

I am wary of arguments that only work on a whiteboard, so here is one that
actually ran.

I moved my `swamp serve` orchestrator onto its own VM. `swamp-serve-01` was
provisioned end to end through `@shrug/xen-orchestra`: created from a template,
brought up, the works. Along the way a stray VIF needed to go, so it went, through
`listVifs` and `deleteVif` on the same model. Its DHCP reservation got pinned on
the OPNsense model so the address would not wander. A read-only deploy key got
registered on the Forgejo model so the box could pull its config and nothing else.

That is one gated, reproducible flow reaching across a hypervisor, a firewall, and
a git host, every step verified, the whole thing written down. It is exactly the
kind of work an MCP cannot do, and not because Vates was lazy. It cannot do it
because a chat-time read lens is the wrong shape for a multi-system mutation you
want to trust and repeat.

Run that same fleet through the MCP and you get a very good description of it. You
can ask what is where and get an honest answer. You just cannot change anything,
and you would not want the description-engine to be the thing that does.

## What I actually want

Both. Obviously both.

I want the read lens in my chat window when I am thinking out loud, and I want the
deterministic model underneath when it is time to touch the fleet. The healthy
version of this is the agent reading through the MCP to understand the state, then
proposing a swamp workflow, which runs and verifies and writes down what it did.
The model does the thinking. The code does the doing. Neither one pretends to be
the other.

The XO MCP is a good addition to that world. I just keep my hands on the control
plane, and the control plane is a swamp model.

Until next time.

---

This is what I do for money too, through [Shrug PW](https://shrugpw.com): making
other people's infrastructure do what it says it does, on purpose, on a schedule.

---
title: "Why I drive XCP-ng through swamp and not an MCP"
description: "Vates shipped a first-party Xen Orchestra MCP. It's read-only and chat-mediated. I argue a swamp model is the better substrate for XCP-ng - and not just because I have write support."
date: 2026-09-18T16:29:00-04:00
slug: swamp-versus-an-mcp
draft: true
categories: ['automation', 'infrastructure']
tags: ['swamp', 'xcp-ng', 'xen-orchestra', 'mcp', 'ai', 'devops']
---

<!-- ROUGH OUTLINE - not prose yet. Beats + notes. This one is an OPINION piece;
     frame carefully. NOT "AI bad" - "deterministic substrate + optional agent on top." -->

## The hook / foil
- Vates shipped a first-party XO MCP server (@xen-orchestra/mcp, XO 6.2).
  Link: xen-orchestra.com/blog/mcp-meets-xen-orchestra
- It's read-only by design: get_infrastructure_summary, get_pool_dashboard,
  list_vms/get_vm_details, list_hosts/list_pools, search_documentation.
- Good foil, genuinely useful. But it's a chat-time READ LENS.
- Thesis (state it plainly, early): the MCP is a chat-time read lens; swamp is a
  deterministic control plane. Different jobs.

## FRAMING GUARDRAIL (call it out so the comments don't derail)
- I am not anti-AI or anti-MCP. Put an agent IN FRONT of swamp all you want.
  The point: the durable execution layer should be deterministic code; the LLM is
  optional orchestration, not the execution path. Agent proposes, swamp executes + verifies.

## The argument - write support is only #1 of many
1. Write, not just read. MCP is read-only. The model actually provisions:
   create-from-template + cloud-init, start, stop (clean/hard), snapshot, destroy,
   plus VIF management.
2. Deterministic, not probabilistic. A method is code with a fixed contract; an MCP
   tool call is mediated by an LLM that may not call it, may hallucinate args, may
   reorder. Same inputs -> same run, every time, in CI.
3. Composable in a workflow DAG. XO steps wire to other systems via CEL: resolve
   UUIDs, reserve DHCP on OPNsense, register a Forgejo deploy key, read a token from
   a vault. MCP tools don't compose into a declarative pipeline.
4. Gated + verifiable. verify-before-destroy, TLS verification always on (no insecure
   toggle), UUIDs resolved not hardcoded, 27 injected-fetch unit tests, adversarial
   security review (10 findings resolved). You can unit-test and code-review a model;
   you can't unit-test an LLM's decision to call a tool.
5. Auditable + reproducible. Every run emits a data snapshot + report; reruns are
   idempotent. Provenance you can point at, not a chat transcript.
6. Secrets stay in vaults, out of the prompt. Token via authenticationToken cookie
   from a vault; nothing bleeds into an LLM context window.
7. Runs unattended / scheduled. cron + serve, no human-in-the-loop chat. An MCP needs
   an assistant and a person driving it.
- (NOTE: 8 was "not anti-AI" - promoted it up to the framing guardrail above.
  Don't repeat it as a list item.)

## Case study spine (real, already done - this is what makes it not-a-rant)
- The serve-orchestrator VM migration (design/serve-orchestrator-vm.md, Phase 0-1).
- swamp-serve-01 provisioned end-to-end through @shrug/xen-orchestra, then:
  - stray VIF pruned via listVifs/deleteVif
  - DHCP pinned through the OPNsense model
  - read-only git deploy key registered via the Forgejo model
- Multi-system, gated, reproducible flow an MCP fundamentally cannot perform.
- Contrast line: the same fleet through the MCP can only be *described*, never *changed*.

## Close
- Land the "deterministic substrate, optional agent on top" thesis one more time.
- Maybe: what I'd actually want from the XO MCP (read lens) + swamp (control plane)
  working together.

<!-- TODO before drafting: re-confirm the XO MCP tool list against the current release
     at publish time (it will move). Pull concrete numbers/UUIDs from the design doc.
     Keep the tone confident-not-smug; this one has the highest flame potential. -->

---
title: "Wiring swamp's OTel traces into a self-hosted LGTM stack"
description: "swamp emits OTLP traces natively - one span tree per run. Here's how I ship them through an auth gateway into Tempo, turn them into RED metrics, and read them in Grafana."
date: 2026-09-18T16:29:00-04:00
slug: configuring-swamp-otel
draft: true
categories: ['automation', 'observability']
tags: ['swamp', 'opentelemetry', 'otel', 'tempo', 'grafana', 'lgtm', 'observability']
---

<!-- ROUGH OUTLINE - not prose yet. This is a HOW-TO / reference. Keep it practical,
     low on jokes, high on copy-pasteable steps. Pairs with "Who watches Grafana?". -->

## Framing (short)
- swamp emits traces natively via OTLP. NOT logs, NOT metrics from the runtime -
  traces only: one span tree per run, per-phase spans, ERROR + exception events.
- Goal of the post: get those traces from a swamp run into a self-hosted
  LGTM/Tempo stack, then make them useful (RED dashboard).

## Section 1 - what swamp actually emits
- One span tree per run. Per-phase spans. ERROR status + exception events on failure.
- Contrast w/ what people expect: these are EXECUTION spans, not LLM token spans.
  (aside: Honeycomb's agent-observability use case uses gen_ai.* for token burn -
  swamp is not that. Note it so nobody's confused.)

## Section 2 - the traced wrapper
- swamp-traced.sh: token from pass, force OTLP over http/protobuf, exec swamp.
- Why a wrapper instead of baking env into the unit (portability / keep secrets out
  of the unit file). Show the script.

## Section 3 - the auth gateway (the part people get wrong)
- ingest.shrug.host -> Caddy basic-auth -> inject X-Scope-OrgID -> Tempo.
- Why: Tempo multitenancy needs the org header; you don't want it client-side.
- Caddy snippet. Note TLS.

## Section 4 - resource attributes (site/host)
- OTEL_RESOURCE_ATTRIBUTES for site + host so spans are attributable across the fleet.
- Gotcha: swamp-club#1084 fix - reference what it fixed. (confirm issue # at publish)

## Section 5 - from traces to RED metrics
- span-metrics generator -> RED (rate/errors/duration) dashboard.
- This is what makes traces actually watchable day-to-day vs one-off debugging.
- Screenshot of the dashboard here.

## Close
- You now have: per-run traces + a RED view, self-hosted, auth'd, multi-tenant-ready.
- Pointer to the companion post ("Who watches Grafana?") for the rest of the LGTM story.

<!-- TODO before drafting: paste the ACTUAL swamp-traced.sh + Caddy snippet from the
     ops-workspace (don't reconstruct from memory). Confirm swamp-club#1084. Grab the
     RED dashboard screenshot. This is the driest of the three - keep it tight, it earns
     its keep as reference, not as a story. -->

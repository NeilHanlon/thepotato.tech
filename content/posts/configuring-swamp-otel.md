---
title: "Wiring swamp's Traces Into My Own LGTM Stack"
description: "swamp emits OTLP traces natively: one span tree per run. Here is how I ship them through a Caddy auth gateway into Tempo and turn them into a RED dashboard I actually look at."
date: 2026-09-18T16:29:00-04:00
slug: configuring-swamp-otel
draft: true
categories: ['automation', 'observability']
tags: ['swamp', 'opentelemetry', 'otel', 'tempo', 'grafana', 'lgtm', 'observability']
---

This one is a how-to, not a story. If you run swamp and you have somewhere to put
traces, this is the wiring I use. I have tried to keep the editorializing to a
minimum, which for me is its own kind of effort.

Two things up front, because they set up everything else. swamp emits traces, and
only traces. And they are traces of the run, not of any model that happens to be
talking to a language model.

## What swamp actually emits

When a run executes, swamp produces one span tree. The run is the root span, each
phase is a child span under it, and a step that fails carries an ERROR status with
the exception recorded as an event on the span. That is the whole shape. No
metrics come out of the runtime, no logs get shipped for you; you get the trace
and you build the rest from it.

It is worth being precise about what these spans are, because "swamp" and "OTel"
and "agent" now show up in the same sentence often enough to cause confusion.
These are execution spans. A span says "this run started here, fanned out into
these phases, this one took four seconds, this one threw." They are not `gen_ai.*`
spans. If you have read about agent observability and token-burn tracing, that is
a different thing measuring a different layer: prompts, completions, tokens. swamp
is not emitting any of that, because a swamp run is code executing against APIs,
not a model thinking. When I say I trace my runs, I mean I can see which step in a
nightly workflow was slow or angry, not how many tokens anything spent.

That distinction is the entire reason the rest of this is simple. I am shipping
ordinary execution traces to an ordinary trace store.

## The traced wrapper

swamp speaks OTLP, so in principle you set a few environment variables and it
exports. In practice I do not want the exporter config, and definitely not the
ingest token, living in a systemd unit or my shell history. So I wrap it.

`swamp-traced.sh` pulls the ingest token out of `pass`, forces OTLP over
http/protobuf, points the exporter at my gateway, and then execs swamp with
whatever arguments I gave it. It is a thin wrapper on purpose: it sets up the
environment and gets out of the way, so `swamp-traced workflow run ...` behaves
exactly like `swamp workflow run ...` with traces turned on.

<!-- NEIL: paste real swamp-traced.sh here -->

The reason it is a wrapper and not baked into the unit file is portability and
secret hygiene. The token comes from `pass` at invocation time, so it is never
written down anywhere durable, and I can run the same wrapper by hand, from cron,
or from a unit without three copies of the exporter config drifting apart.

## The auth gateway (the part people get wrong)

The exporter does not talk to Tempo directly. It talks to a gateway:
`ingest.shrug.host`, which is Caddy doing basic auth and then injecting the
`X-Scope-OrgID` header before it proxies to Tempo.

<!-- NEIL: paste the Caddy ingest snippet here -->

The header matters and the placement matters. Tempo uses `X-Scope-OrgID` for
multitenancy: it decides which tenant's data a request reads or writes. If a
client sets that header, then the client chooses its own tenant, which means the
tenant boundary is only as good as every client's good behavior. So I do not let
clients set it. The exporter authenticates to Caddy, Caddy decides which tenant
that credential maps to, and Caddy sets the header on the way through. The client
never names its own tenant. That is the whole trick, and it is easy to get wrong
by wiring the header on the sender because that is where the OTel docs put it.

## Attributing spans to a host and site

Out of the box, a span tells you a run happened. It does not tell you which box it
happened on, which is useless the moment you have more than one. OpenTelemetry
handles this with resource attributes, and swamp reads
`OTEL_RESOURCE_ATTRIBUTES`, so I set site and host there in the wrapper and every
span gets stamped with where it came from.

```sh
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=hel,host.name=$(hostname -s)"
```

This did not work the first time I tried it, for a reason that was a genuine bug
rather than my fault for once. swamp was not threading the resource attributes all
the way through to the exported spans, so everything showed up unattributed. That
got fixed upstream.

<!-- NEIL: confirm swamp-club issue number for the OTEL_RESOURCE_ATTRIBUTES fix (outline guessed #1084) -->

## From traces to a dashboard I look at

Raw traces are good for the question "why was this one run weird." They are bad
for the question "how are my runs doing lately," because nobody scrolls a trace
list for fun. The bridge is a span-metrics generator: it watches the spans coming
into Tempo and derives rate, error, and duration metrics from them, which is the
RED method. Those metrics land in the metrics store, and I point a Grafana panel
at them.

The result is a dashboard that answers the day-to-day questions without opening a
single trace: how often are runs happening, what fraction are erroring, how long
are they taking, and is any of that trending the wrong way. When something on the
dashboard looks off, then I open the actual trace and read the span tree to find
the phase that broke. Metrics to notice, traces to diagnose.

<!-- NEIL: RED dashboard screenshot here -->

## That is the wiring

Wrapper mints the environment and the token, gateway authenticates and stamps the
tenant, Tempo stores the span trees, the span-metrics generator turns them into a
RED view. None of it is exotic; the only swamp-specific parts are that swamp emits
traces natively and that you want the resource attributes set so the spans are
attributable.

The other half of this, watching the LGTM stack that is watching everything else,
is its own can of worms and its own post, which is coming. This one was just the
plumbing.

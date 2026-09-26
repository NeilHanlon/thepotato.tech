---
title: "Deploying swamp-as-a-service, with swamp itself"
description: "I stood up 'swamp serve' on a dedicated FreeIPA service account using nothing but swamp models. The tool configured the host that runs the tool, and it fought me the whole way down."
date: 2026-09-18T16:29:00-04:00
slug: swamp-as-a-service
draft: true
categories: ['automation', 'infrastructure']
tags: ['swamp', 'freeipa', 'tls', 'oauth', 'systemd', 'dogfooding', 'devops']
---

<!-- ROUGH OUTLINE - not prose yet. Beats + notes to self. Cut ruthlessly. -->

## The premise / hook
- I run swamp for everything. So of course I deployed the swamp control plane
  itself using swamp. Ouroboros. "the tool configures the host that runs the tool."
- One rule going in: no Ansible. Everything-as-swamp-models, full audit trail.
- Target: `swamp serve` running as its own FreeIPA identity (swamp:swamp), on the
  thinkcenter KVM box.

## Beat 1 - identity first (FreeIPA / SSSD)
- Why a dedicated service account and not just my user. Identity central, SSSD.
- Renaming the badly-named -tc models to -thinkcenter. Aside: UUID-keyed state
  means a cosmetic rename is safe (state doesn't move). Nice swamp property, one line.

## Beat 2 - issue the TLS cert THROUGH swamp
- @shrug/freeipa/cert certRequest: principal-agnostic, in-model RSA keygen.
- The key never touches local disk - auto-vaulted to pass, referenced by CEL.
- Deliver cert+key to the host via @adam/cfgmgmt.
- (this is the "look how clean it is" beat before it all goes wrong)

## Beat 3 - the two bugs mocks never caught (live-only)
- Only surfaced against a REAL IPA, not the mocked tests:
  - (a) audit data-instance name derived from principal -> path-traversal
    validator rejects service principals containing '/'.
  - (b) generateCsr was CN-only -> cert had NO SubjectAltName -> modern TLS
    clients reject it, and this IPA profile won't synthesize a SAN from CN.
    Fix: dnsNames arg that emits a real SAN.
- LESSON beat: smoke-before-push / live-prove. Verify the artifact
  (openssl x509 -ext subjectAltName), don't trust "succeeded."

## Beat 4 - least privilege, in practice (the ACL grind)
- svc-freeipa-rw was scoped to USER certs on purpose. Issuing a SERVICE cert
  needed a break-glass grant.
- New privilege "swamp service management" (Add Services, then ALSO Modify
  Services to write userCertificate), bundled into role "swamp writers."
- The loop: attempt -> 400/ACIError -> add exactly the permission it named -> retry.
  Each denial teaches the next permission. Least-priv means you WILL iterate.

## Beat 5 - cfgmgmt footguns (short, punchy section)
- copy_file/file with NO default for `ensure` silently reports "compliant" and
  no-ops. You deploy nothing and it says success. (the quiet one)
- Running swamp as a non-root service account needs a CWD it can read or
  readSwampSources throws EACCES. Fix: runuser + cd to a swamp-owned dir.

## Beat 6 - THE MONEY SECTION: OAuth device-flow vs systemd Restart
- `swamp serve --auth-mode oauth` does a device grant on first start
  (visit .../device, enter code).
- Under systemd Restart=on-failure this RESTART-STORMS: each restart mints a
  fresh device code, the burst rate-limits the device endpoint into 400, and the
  human can never authorize in time - the code you approve belongs to a process
  systemd already killed.
- Root insight: interactive first-run bootstrap fundamentally conflicts with a
  restart-looping unit.
- Fixes: bootstrap auth OUTSIDE the unit / Restart=no during first-run / just use
  token auth. We went token auth - right call for a homelab control plane.
- (this is probably the strongest standalone beat; consider leading with a cold-open
  of the restart storm and flashing back? decide later.)

## Close - meta
- "The tool configures the host that runs the tool."
- Every mutation (cert, RBAC grant, host files, systemd unit) is a swamp run with
  a queryable trail - INCLUDING the two model bugs we fixed mid-flight.
- Codeable-takeaways box: verify SAN not just issuance; ensure:present is not a
  default in @adam/cfgmgmt; device-flow != systemd Restart; least-priv = you iterate the ACL.

<!-- TODO before drafting: decide cold-open (restart storm) vs chronological.
     Pull real UUIDs/principal names or anonymize. Keep family/infra details scrubbed.
     Link back to the Kerberos post and the Fedora post. -->

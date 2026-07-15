# GA registration success-rate research (2026-07-15)

## Current funnel

Latest 100-slot production run `29347583690`:

```text
100 fresh GA runners
  37 denied before touching signup
  63 live probes
    50 reached collector result|0
      36 CreateAccount strict success
      12 fresh-rechallenge absolute timeout
       2 explicit post-proof riskBlock
    12 pre-proof explicit riskBlock
     1 collector result|-1
  36 created, 34 Graph healthy
```

Reported rates must keep their denominator:

- raw strict yield: `36/100 = 36%`;
- live-probe strict rate: `36/63 = 57.1%`;
- strict rate after accepted proof: `36/50 = 72%`;
- Graph health after creation: `34/36 = 94.4%`.

The previous 100-slot run `29338532443` produced 20 strict / 18 Graph healthy.
The gain came from both more usable egresses and a higher accepted-proof rate;
workflow conclusion alone is not a registration metric.

## Decisive bottlenecks

1. Azure egress family is the largest pre-captcha cause. The expanded denylist
   removes 27 of 30 explicit risk blocks in the joined two-run sample while
   preserving every observed strict success.
2. The largest remaining technical loss is not the first hold. Twelve of the
   latest 50 accepted proofs received a fresh HumanCaptcha but exhausted the
   old 60-second/two-round recovery path.
3. The online ADS route still uses a 22-second warmup, 9.5-12.5 second physical
   hold, up to three presses, and only two outer fresh rounds. The locally
   reproduced exact-release route uses a 6.5-second physical hold, an eight
   server-challenge budget, and has a verified two-fresh-challenge
   `CreateAccount 200` sample.
4. Two created accounts failed the immediate Graph stage. Account creation and
   mailbox health must remain separate counters.

## First controlled change

The workflow now pins `release_5s_success_baseline` and
`release_5s_success_attempt2` to private source
`00b68437e041cbdcee2be209a18d7a5592f4c2dd` instead of the unrelated default
source ref. Each fresh runner receives a distinct deterministic Cloak
fingerprint seed while all exact-release timing and proof parameters remain
unchanged.

Run this as a small GA-own-IP experiment before replacing the current online
ADS production variant:

```text
variant=release_5s_success_attempt2
runtime_mode=legacy
network_mode=ga_own_ip
coordinator_mode=entry
egress_prefix_denylist=4.,13.,20.,40.,52.,68.
node_slots_json=[1..20]
max_parallel=5
slot_stagger_seconds=12
per_ip_max_registrations=1
```

`runtime_mode=legacy` is intentional for the first comparison: the exact
source pins CloakBrowser 0.3.32, while the current prebuilt cache contains
0.4.8. Cache migration should be a separate variable after the captcha path is
measured.

## Exact 5s result: captcha accepted, account creation rejected

Run `29376059630` completed with:

```text
20 dispatched
13 egress-denylist skips
 7 live probes
   5 collector result|0 on both HumanCaptcha rounds, then risk/verify 403
   1 pre-proof explicit riskBlock
   1 username unavailable
 0 strict CreateAccount
```

The five post-proof failures all followed the same server sequence:

```text
risk/initialize 200
risk/verify 200 -> HumanCaptcha
collector result|0
risk/verify 200 -> fresh HumanCaptcha
collector result|0
risk/verify 403 -> riskBlock
```

Therefore the exact 5s primitive is effective at the hsprotect collector
boundary, including a fresh challenge, but the complete historical bundle is
not a production registration replacement. `collector result|0` is only proof
acceptance by the captcha collector; Microsoft still makes a separate
`risk/verify` decision. The live egress families in this run include families
that created accounts at high rates under the current online-ADS variant, so
classifying all five outcomes as an IP-only regression would overstate the
evidence. Browser identity, proof shape, and host handoff remain coupled in the
exact historical variant.

## Extending the fresh deadline does not recover the second challenge

Run `29376810902` kept the current online-ADS source, CloakBrowser 0.4.8,
natural first proof, coordinator policy, and hold settings. The controlled
change was only:

```text
fresh absolute deadline: 60s -> 180s
```

Result:

```text
100 dispatched
 59 egress-denylist skips
 41 live probes
   29 strict CreateAccount
   29 Graph healthy
    7 accepted first proof -> fresh challenge -> 180s timeout
    3 pre-proof explicit riskBlock
    1 accepted proof -> explicit riskBlock
    1 username unavailable
```

Rates with explicit denominators:

```text
raw strict                 29/100 = 29.0%
live-probe strict           29/41 = 70.7%
accepted-checkpoint strict  29/37 = 78.4%
Graph after creation        29/29 = 100%
```

Decrypted traces settle the mechanism:

- all 29 strict successes had one `collector result|0` and
  `riskChallengeRequired -> continue`;
- none of the 29 strict successes traversed a second HumanCaptcha;
- all seven timeout slots had an initial `result|0`, received a fresh
  HumanCaptcha, then produced only `result|-1` on the fresh natural holds;
- all seven reached the 180-second deadline at `post_wait`, after one to three
  failed fresh proofs.

So the 60-second watchdog was exposing the failure early, not causing it.
Increasing it to 180 seconds spends more runner time on already rejected fresh
proofs and did not demonstrate a single fresh-challenge recovery.

## Next controlled change: natural first proof, 5s fresh proof only

The next variant targets the actual failed edge instead of replacing the whole
registration path:

```text
variant=online_ads_ga_fresh_5s_recovery
private source=83a642e7f8f7f7a93a3e1a94754917b705239881
initial HumanCaptcha=unchanged natural online-ADS path
fresh HumanCaptcha=early-armed, dormant 15s logical / 6.5s wall handler
browser/config/final normalizer=unchanged online-ADS production values
```

The handler is invocation-gated: the first `handle_captcha` call always uses
the natural implementation; only a Microsoft re-issued HumanCaptcha uses the
5s primitive. This preserves the path responsible for all 29 current strict
successes while testing whether the historical primitive can convert the
fresh-round `result|-1` cluster into `result|0` without importing the old
CloakBrowser 0.3.32 identity bundle.

Implementation smoke evidence:

- run `29378259289` did not touch signup on its ten live slots because the
  first wrapper revision passed one option unavailable in the pinned source;
  the argument was removed and a static wrapper/parser flag validator was added
  to the public workflow;
- run `29378482221` then produced `2/2` strict, Graph-healthy live probes and
  confirmed `invocation=1 handler=natural` with no time-warp activation;
- the first actual fresh sample in run `29378685127` reached
  `invocation=2 handler=time_warp_hold`, but late hook installation emitted no
  decisive PX561 final. The run was cancelled after this mechanism reproduced,
  rather than spending the remaining slots on a known-broken variant;
- source `2347567` switched the hook mode to early and bounded a no-final
  attempt to 45 seconds, but `--defer-route-hook-until-proof` still meant the
  route injector was absent when the fresh iframe bootstrapped. Run
  `29379164017` produced 7 strict/Graph-healthy accounts from 12 live probes;
  its one fresh case ran both bounded fresh invocations but again emitted no
  decisive PX561 final;
- source `92cc799` adds a controller-to-probe preparation callback. It attaches
  the hsprotect route injector after Microsoft requests the fresh challenge but
  before the new shell/iframe is created. Thus the initial challenge remains
  natural and untouched, while the fresh iframe receives the dormant runtime
  hook from its first document/script byte. Automatic KNP prestart remains
  disabled on the initial challenge; the explicit fresh invocation prestarts
  KNP immediately before mouse-down.

Run `29379820651` validates that boundary with two fresh cases:

- both fresh iframes were route-injected before their document and captcha JS
  initialized, and both emitted decisive PX561 finals instead of the previous
  no-final timeout;
- one case returned `result|-1` on both bounded rounds;
- the other returned `result|-1` on fresh round 1, then `result|0` on fresh
  round 2. Microsoft answered that accepted proof with another
  `riskChallengeRequired` rather than `continue`;
- the controller's two-round cap then ended the flow before it could solve the
  newly issued third HumanCaptcha.

This is the first GA evidence that the fresh-only transplant repairs the
captcha boundary while preserving the natural initial path. Source `83a642e`
raises only the fresh server-round budget from two to three. The follow-up must
use the existing 300-second absolute ceiling; the accepted second fresh proof
arrived with too little of the previous 180-second budget left for a third
round.

## Three fresh rounds do not by themselves improve end-to-end recovery

Run `29380273787` tested source `83a642e` with a 300-second absolute fresh
deadline and three fresh server rounds:

```text
50 dispatched
 25 egress-denylist skips
 25 live probes
   19 strict CreateAccount
   16 Graph healthy
    3 created, ingest endpoint returned HTTP 404
    2 pre-proof explicit riskBlock
    2 accepted first proof -> explicit riskBlock
    2 accepted first proof -> fresh challenge -> no strict CreateAccount
```

Both fresh slots executed all three permitted rounds, but all six fresh
collector responses were `result|-1`. All 19 strict creations still followed
the one-challenge path `riskChallengeRequired -> continue`; none was recovered
from a second HumanCaptcha. Therefore increasing only the round/deadline budget
does not repair the proof shape and consumes runner time without adding healthy
accounts.

The three ingest failures are not Graph-auth failures. Their registration
completed, but the shared `/outlook-email/api/external/outlook/import-authorize`
route returned HTTP 404 during a short hourly nginx reconfiguration window.
They remain separate from captcha success-rate analysis.

The observed 404 requests span `01:00:17` through `01:01:29` UTC, while the
first later request returned 200. The ingestion loop now retries only transient
network/404/408/425/429/5xx responses at `0/25/50/75/100s`. Permanent
application failures stop immediately. This protects Graph-healthy yield from
the measured route window without reclassifying OAuth or Graph rejection as a
transport retry.

## Next controlled source: exact guards only on the fresh handler

The next source pin is `b80b75375a0925b0fa3e80f962f7014ecfe5d495`.
It leaves the initial natural HumanCaptcha path unchanged and changes only the
fresh time-warp handler:

- non-target requests in the fresh route injector use `route.fallback()` so
  the existing online-ADS normalizer remains in the route chain;
- PX1200 timing normalization and PX561 alignment are enabled;
- the KNP sandbox event, exact KNP wait/grace, U0 lead, and pre-hold readiness
  gates match the previously successful exact-proof primitive;
- the wall hold remains 6.5 seconds, with one attempt per Microsoft-issued
  fresh challenge and a maximum of three fresh server rounds.

The decisive measurement is not overall workflow green or collector
`result|0`. It is the fresh-only funnel:

```text
fresh PX561 final
-> fresh collector result|0
-> risk/verify continue
-> strict CreateAccount
-> Graph healthy
```

## Exact guards still used the wrong final normalizer

Run `29381346438` tested source `b80b753` with 50 slots, ten-way parallelism,
the 300-second fresh deadline, and no other registration-path change:

```text
50 dispatched
 29 egress-denylist skips
 21 live probes
   20 accepted an initial collector result|0
   14 strict CreateAccount
   14 Graph healthy
    3 fresh absolute timeout
    1 fresh rounds exhausted without CreateAccount
    2 accepted first proof -> explicit riskBlock
    1 username unavailable
```

Rates with explicit denominators:

```text
raw strict                 14/50 = 28.0%
live-probe strict           14/21 = 66.7%
accepted-checkpoint strict  14/20 = 70.0%
Graph after creation        14/14 = 100%
Graph healthy / run minute  14/15.15 = 0.924/min
```

The run-level failure is the intentional goal-evaluation result because five
non-IP technical failures remain; all 50 matrix jobs themselves finished
successfully. Decrypted evidence from all four fresh slots is decisive:

- all twelve fresh invocations passed their runtime/readiness gates;
- eight emitted a decisive PX561 final and all eight returned `result|-1`;
- four invocations timed out without a decisive final;
- no fresh proof returned `result|0`, reached `risk/verify -> continue`, or
  produced CreateAccount.

The guards were installed correctly, but every fresh final was still routed
through `minimal_natural_hold`. Its implementation explicitly preserves a
9.5–12.5-second natural-hold envelope; it is not the normalizer used by the
validated 15-second-logical / 6.5-second-wall primitive. The local exact sample
that crossed two HumanCaptcha challenges and reached CreateAccount used
`ads_safe`. Its accepted fresh PX561 had `XGhm≈87.6`, while the rejected
`b80b753` fresh finals were in the `20.4–47.2` band. Browser and egress differ,
so this scalar comparison is directional evidence rather than proof that XGhm
alone is causal.

The first implementation, source `b33b57e59f53667d9f7c4fd7875cc592927c8108`,
set the wrapper's global `--final-proof-normalizer` to `ads_safe`. Run
`29382465296` immediately disproved the assumption that the deferred JS route
hook also deferred the Python collector normalizer:

```text
40 verdicts uploaded before/while cancellation
 23 egress-denylist skips
 17 live probes
    0 accepted collector result|0
    0 strict CreateAccount
   10 collector result|-1
    6 score0/no result0
    1 pre-proof explicit riskBlock
```

The run was cancelled as soon as the regression was clear. A decrypted live
sample shows `invocation=1 handler=natural` and
`final_proof.mode=ads_safe`, followed by `result|-1`. The Python Y1NZ/final
normalizer is installed when the page is created even when the fresh runtime
JS injector is deferred. Therefore the global wrapper switch corrupted the
known-good first proof; the failure is in phase isolation, not evidence against
ADS-safe on a real fresh proof.

Source `b8cee97e0b9425603e2797052ba6b59bd75f394d` adds an explicit mutable
normalizer phase state:

```text
initial HumanCaptcha -> minimal_natural_hold
risk/verify requests fresh HumanCaptcha
-> switch Python collector normalizer to ads_safe
-> create/inject fresh challenge shell
```

The wrapper now passes both `--final-proof-normalizer minimal_natural_hold` and
`--fresh-final-proof-normalizer ads_safe`. The switch occurs in the existing
controller callback before the fresh shell is created; tests verify the shared
route state mutates in place. Post-primary final retries remain disabled, so
each fresh challenge still sends one real decisive final. The next run must
first establish the isolated ADS-safe fresh-final shape before changing hold
attempts or timing. The deadline should not be increased again.

## Phase isolation works, but ADS-safe alone does not recover fresh challenges

Run `29383097336` first used 20 slots as a smoke test for source `b8cee97`:

```text
20 dispatched
 10 egress-denylist skips
 10 live probes
    8 accepted initial result|0
    6 strict CreateAccount
    6 Graph healthy
    1 accepted proof -> explicit riskBlock
    1 accepted proof -> fresh absolute timeout
    2 pre-proof explicit riskBlock
```

The fresh slot recorded the intended transition
`minimal_natural_hold -> ads_safe`; its initial natural final returned
`result|0`. All three fresh invocations passed readiness, but none emitted a
decisive PX561. This proved the initial regression was fixed but did not yet
test an ADS-safe fresh final.

Run `29383601440` then supplied the required fresh-final sample:

```text
50 dispatched
 25 egress-denylist skips
 25 live probes
   24 accepted initial result|0
   16 strict CreateAccount
   16 Graph healthy
    3 fresh absolute timeout
    2 fresh rounds exhausted without CreateAccount
    3 accepted proof -> explicit riskBlock
    1 pre-proof explicit riskBlock
```

Rates:

```text
raw strict                 16/50 = 32.0%
live-probe strict           16/25 = 64.0%
accepted-checkpoint strict  16/24 = 66.7%
Graph after creation        16/16 = 100%
Graph healthy / run minute  16/12.62 = 1.268/min
```

All five fresh slots switched only after the accepted initial proof. Across 15
fresh invocations, all 15 readiness gates passed; 14 emitted an ADS-safe PX561
and all 14 returned `result|-1`. One invocation produced no decisive final.
There was no fresh `result|0`, `risk/verify -> continue`, or CreateAccount.

The closest rejected no-BFA packet and the accepted local exact-fresh reference
already match on event order, logical hold (`z=13500`), `r3-ui`, and seven-event
Dz shape. Their largest scalar divergence is:

```text
rejected fresh finals: XGhm=21.9..57.3, Bzt=3018..34189
accepted reference:    XGhm≈87.6,      Bzt≈517
```

Source `ae0745a95f73bec3ab24b9a5ce461bae1fa4a371` therefore tests one
new primary shape only on fresh PX561: `XGhm=84.2..90.2` plus the existing
low-Bzt/STk accepted band. It does not alter the initial natural proof, does not
increase the deadline, and does not send post-primary variants after a reject.
If this primary scalar anchor also fails, repeated fresh salvage should be
removed from the production throughput path and retained only as an explicit
research variant.

## Scalar matching fails; production should stop spending rounds on fresh challenges

Run `29384434857` tested source
`ae0745a95f73bec3ab24b9a5ce461bae1fa4a371` with the scalar anchor enabled:

```text
30 dispatched
 15 egress-denylist skips
 15 live probes
   14 accepted initial result|0
    8 strict CreateAccount
    8 Graph healthy
    4 entered a fresh HumanCaptcha
    2 accepted proof -> explicit riskBlock
    1 pre-proof explicit riskBlock
```

Rates with their denominators:

```text
raw strict                  8/30 = 26.7%
live-probe strict           8/15 = 53.3%
accepted-checkpoint strict  8/14 = 57.1%
Graph after creation         8/8 = 100%
Graph healthy / run minute        = 0.569/min
```

All four fresh slots switched from `minimal_natural_hold` to `ads_safe`
before the new challenge shell. All twelve fresh invocations passed the
readiness gate. Eight produced a decisive PX561 and all eight returned
`result|-1`; four produced no decisive final. The anchor was not merely
configured but observed on the wire:

```text
XGhm=85.2..88.7
Bzt=509.3..727.0
STk=548..776
fresh collector result|0 = 0
risk/verify continue      = 0
CreateAccount             = 0
```

This overlaps the accepted local reference (`XGhm≈87.6`, `Bzt≈517`) yet does
not change the collector verdict. Therefore XGhm/Bzt are correlated fields,
not an independent acceptance threshold. The fresh decision remains bound to
the wider session, timing, event, browser, and server-issued challenge state.
Increasing timeouts, rounds, or fitting more isolated scalars is no longer a
supported production optimization.

Source `875b0571d5b9c88b89a5bbc64f30488ee9565962` adds a production policy that
allows `OUTLOOK_SIGNUP_PROTOCOL_TAKEOVER_FRESH_RECHALLENGE_ROUNDS=0`. The new
`online_ads_ga_production_fast_fail` variant keeps the proven initial natural
path unchanged and stops immediately when Microsoft issues a fresh
HumanCaptcha. The three-round exact handler remains pinned separately as the
research variant. The same source also rerolls a generated username only when
CheckAvailable explicitly returns `isAvailable=false` or error code `1220`;
transient/unknown backend errors are not retried as username conflicts.

The production comparison must optimize the complete output metric:

```text
Graph healthy / minute
```

It must also verify that initial accepted-proof rate and Graph health after
creation do not regress. A lower wall time alone is not sufficient if it
damages the one-challenge path.

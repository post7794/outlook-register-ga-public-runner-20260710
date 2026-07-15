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

Only if the exact guards still produce repeated fresh `result|-1` should the
next isolated variable be `time-warp-attempts=2`; the deadline should not be
increased again.

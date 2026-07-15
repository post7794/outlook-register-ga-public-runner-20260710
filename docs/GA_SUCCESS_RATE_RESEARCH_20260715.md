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
private source=7c5df7beb44e9e0c1bb070a7ebabb41abce234c6
initial HumanCaptcha=unchanged natural online-ADS path
fresh HumanCaptcha=late-installed 15s logical / 6.5s wall handler
browser/config/final normalizer=unchanged online-ADS production values
```

The handler is invocation-gated: the first `handle_captcha` call always uses
the natural implementation; only a Microsoft re-issued HumanCaptcha uses the
5s primitive. This preserves the path responsible for all 29 current strict
successes while testing whether the historical primitive can convert the
fresh-round `result|-1` cluster into `result|0` without importing the old
CloakBrowser 0.3.32 identity bundle.

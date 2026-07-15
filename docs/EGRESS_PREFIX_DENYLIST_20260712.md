# GA egress prefix denylist (updated 2026-07-15)

## 2026-07-15 high-N refresh

The decrypted 100-slot runs `29338532443` and `29347583690` add 200 joined
egress/outcome samples. The newly rejected ranges remained at zero strict
success:

| prefix | n | strict | entry riskBlock | post-proof riskBlock | technical |
|--------|--:|-------:|----------------:|---------------------:|----------:|
| 4. | 10 | 0 | 9 | 1 | 0 |
| 13. | 3 | 0 | 3 | 0 | 0 |
| 40. | 8 | 0 | 8 | 0 | 0 |
| 68. | 7 | 0 | 5 | 1 | 1 |

Across the two runs, the old `20.,52.` policy admitted 110 probes: 56 strict
successes, 30 explicit risk blocks, and 24 technical failures. Applying the
expanded policy to the same observations admits 82 probes: the same 56 strict
successes, only 3 explicit risk blocks, and 23 technical failures. Conditional
strict success therefore rises from `50.9%` to `68.3%`; this is a target-safety
filter, not free throughput, so skipped runners must be backfilled.

Built from decrypted live evidence of runs:

- 29156535546 (baseline hold=3 stagger=30)
- 29159732770 (isolation fix)
- 29160529467 (repro)

Sample base: 66 IPs with safe verdicts joined.

## Hard denylist (recommended)

```text
4.,13.,20.,40.,52.,68.,74.249.
```

Evidence:

| prefix | n | entry riskBlock | strict | result0 |
|--------|---:|----------------:|-------:|--------:|
| 20. | 18 | 18 | 0 | 0 |
| 52. | 10 | 10 | 0 | 0 |

Both meet the handoff rule at high n: >=3 samples, 100% entry riskBlock, 0 result0, 0 strict.

The joined production-like runs `29338532443`, `29347583690`, `29376810902`,
`29380273787`, and `29385796706` add one narrower range that meets the same
rule without excluding the successful remainder of its `/8` family:

| prefix | n | runs | entry riskBlock | strict | result0 |
|--------|--:|-----:|----------------:|-------:|--------:|
| 74.249. | 3 | 2 | 3 | 0 | 0 |

The sibling range `74.235.` remains successful (`4/4` strict in the joined
sample), so `74.` must not be denied as a whole.

Do **not** treat this as a permanent global ban forever; refresh after each major Azure GA pool shift.

## Where success still happens

| prefix | n | strict | notes |
|--------|---:|-------:|-------|
| 172. | 13 | 7 | main success / rechallenge pool |
| 135. | 5 | 2 | mixed technical |
| 57. | 3 | 2 | good when present |
| 130./64./132./134./145. | small | some strict | keep |

## Operational recipe

1. Pass denylist into workflow input `egress_prefix_denylist=4.,13.,20.,40.,52.,68.,74.249.`
2. Over-provision candidates so skipped IPs do not starve live count:
   - target ~20 live probes
   - start ~50 matrix slots (`node_slots_json=[1..50]`)
   - keep `max_parallel=20` and stagger 10-15s
3. Skipped jobs exit before touching signup target (`ip_skipped` / `egress_denylist`).

## /16 notes (subset of 20.)

Also pure-bad with n>=3: `20.119.`, `20.163.`, `20.168.`.
These are covered by the `/8` token `20.`.

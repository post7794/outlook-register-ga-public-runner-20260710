# GA egress prefix denylist (2026-07-12)

Built from decrypted live evidence of runs:

- 29156535546 (baseline hold=3 stagger=30)
- 29159732770 (isolation fix)
- 29160529467 (repro)

Sample base: 66 IPs with safe verdicts joined.

## Hard denylist (recommended)

```text
20.,52.
```

Evidence:

| prefix | n | entry riskBlock | strict | result0 |
|--------|---:|----------------:|-------:|--------:|
| 20. | 18 | 18 | 0 | 0 |
| 52. | 10 | 10 | 0 | 0 |

Both meet the handoff rule at high n: >=3 samples, 100% entry riskBlock, 0 result0, 0 strict.

Do **not** treat this as a permanent global ban forever; refresh after each major Azure GA pool shift.

## Where success still happens

| prefix | n | strict | notes |
|--------|---:|-------:|-------|
| 172. | 13 | 7 | main success / rechallenge pool |
| 135. | 5 | 2 | mixed technical |
| 57. | 3 | 2 | good when present |
| 130./64./132./134./145. | small | some strict | keep |

## Operational recipe

1. Pass denylist into workflow input `egress_prefix_denylist=20.,52.`
2. Over-provision candidates so skipped IPs do not starve live count:
   - target ~20 live probes
   - start ~32-40 matrix slots (`node_slots_json=[1..36]`)
   - keep `max_parallel=20` and stagger 20-30s
3. Skipped jobs exit before touching signup target (`ip_skipped` / `egress_denylist`).

## /16 notes (subset of 20.)

Also pure-bad with n>=3: `20.119.`, `20.163.`, `20.168.`.
These are covered by the `/8` token `20.`.

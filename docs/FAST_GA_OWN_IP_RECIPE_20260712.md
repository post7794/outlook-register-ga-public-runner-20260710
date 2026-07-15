# Fast GA own-IP recipe (updated 2026-07-15)

## Wall-clock bottlenecks fixed

1. Denylist used to run **after** apt/python/fonts/ADS + full linear stagger.
2. Slot N slept `(N-1)*stagger` even when many earlier slots were denylisted.

## Current behavior

1. Checkout + verify source
2. **Early egress + denylist** (`should_probe`)
3. Heavy setup only if probing
4. Wave stagger: `((attempt-1) % max_parallel) * stagger_seconds`
5. Live probe

## Recommended dispatch

```text
node_slots_json=[1..50]
egress_prefix_denylist=4.,13.,20.,40.,52.,68.,74.249.
slot_stagger_seconds=12
max_parallel=20
variant=online_ads_ga_production_fast_fail
coordinator_mode=final_only
runtime_mode=prebuilt
```

Expected wall clock: roughly **12-18 min** vs previous ~34 min for 36-slot denylist runs,
assuming similar skip ratio.

## Do not cut first for speed

- hold_retries=3 (collector acceptance)
- initial natural HumanCaptcha path
- final-only coordinator
- recommended denylist (IP quality)

The three-round fresh-challenge handler is now research-only. Matched run
`29385796706` kept 8 Graph-healthy accounts while reducing wall time from
14.07 to 7.93 minutes by setting the production fresh-round budget to zero.

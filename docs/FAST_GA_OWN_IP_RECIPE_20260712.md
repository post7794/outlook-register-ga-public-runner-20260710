# Fast GA own-IP recipe (2026-07-12)

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
node_slots_json=[1..32]
egress_prefix_denylist=20.,52.
slot_stagger_seconds=12
max_parallel=24
variant=online_ads_ga_fresh_rechallenge
```

Expected wall clock: roughly **12-18 min** vs previous ~34 min for 36-slot denylist runs,
assuming similar skip ratio.

## Do not cut first for speed

- hold_retries=3 (collector acceptance)
- isolation fresh rechallenge path
- denylist 20./52. (IP quality)

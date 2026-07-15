# Target Graph-healthy GA orchestration

## Why this exists

A fixed `100`-slot matrix does not promise 100 usable accounts. Denylisted GA
egresses leave before signup, accepted proofs can receive a fresh challenge,
and CreateAccount success can still fail Graph provisioning. The business goal
is therefore expressed as:

```text
dispatch bounded batches
  -> strict CreateAccount
  -> Graph import/probe healthy
  -> stop when cumulative Graph healthy reaches the target
```

This scheduler controls output quantity; it does not relabel skipped slots as
registration failures or claim to improve per-live conversion.

## Workflow

Run `.github/workflows/ctf-ga-target-graph-healthy.yml` (`CTF GA target Graph
healthy`). It serially dispatches `ctf-ga-own-ip-pool.yml` child runs and uses
only their public-safe verdict artifacts.

Recommended starting inputs:

| input | default | meaning |
|-------|--------:|---------|
| `target_graph_healthy` | 100 | required usable-account output |
| `batch_slots` | 50 | maximum slots per child run |
| `min_batch_slots` | 5 | minimum adaptive backfill batch |
| `max_dispatched` | 400 | hard cost/safety ceiling |
| `child_ref` | main | public runner ref for child dispatches |
| `child_timeout_minutes` | 45 | parent deadline for one child run |
| `poll_seconds` | 20 | status polling interval |

Example:

```powershell
gh workflow run ctf-ga-target-graph-healthy.yml `
  -R post7794/outlook-register-ga-public-runner-20260710 `
  -f target_graph_healthy=100 `
  -f batch_slots=50 `
  -f min_batch_slots=5 `
  -f max_dispatched=400
```

The first child uses `batch_slots`. Later batches estimate the remaining slots
from cumulative raw Graph-healthy yield with a 15% safety margin, while obeying
both batch and total caps. Repeated child slot labels are safe because every
batch has a distinct run ID and public-safe `orchestration_id`.

## Decisive behavior

- Child workflow `conclusion=failure` is not treated as account failure; the
  orchestrator counts `account_lifecycle=graph_healthy` plus
  `graph_import_ok=true` in each verdict.
- Every child must publish exactly one verdict for every dispatched slot, with
  complete attempt labels and the expected orchestration marker.
- A preflight rejects overlapping active own-IP child runs, avoiding mixed
  coordinator experiments.
- The parent stops successfully once the target is met. It fails clearly with
  `max_dispatched_exhausted_before_target` if the hard cap is reached first.
- The parent has a repository concurrency group, so two target schedulers do
  not run simultaneously.

## Evidence and security

The parent downloads only `ga-safe-verdict-*`; encrypted account evidence is
left in the child runs. Its artifact contains:

```text
Results/target-healthy-summary.json
Results/ga-target/**/batch-summary.json
```

These summaries contain run IDs, counts, rates, public-safe configuration, and
coordinator timing aggregates. They contain no email, password, token, full IP,
proxy URL, cookie, request body, or decrypted evidence.

The implementation is also runnable locally:

```powershell
python tools/ga_target_healthy_orchestrator.py `
  --repo post7794/outlook-register-ga-public-runner-20260710 `
  --target-graph-healthy 10 `
  --batch-slots 20 `
  --max-dispatched 80 `
  --dry-run
```

## End-to-end validation

Two parent runs exercised both terminal branches:

| parent run | target / cap | child batches | achieved | parent decision |
|------------|-------------:|--------------:|---------:|-----------------|
| `29418596160` | 4 / 15 | 3 x 5 | 2 | failed: cap exhausted |
| `29419530072` | 1 / 15 | 1 x 5 | 1 | success: stopped immediately |

The first run's child batches produced `2, 0, 0` Graph-healthy accounts. The
last two batches still accepted all six live initial proofs, but ended in fresh
challenge or explicit risk block; the parent correctly continued and then
failed with `max_dispatched_exhausted_before_target` instead of calling a
workflow completion a success.

The second run had four denylist skips and one live slot. That one slot was
strict CreateAccount and Graph healthy, so the parent stopped after the first
batch. Both runs proved same-repository dispatch with `github.token`, child
polling, exact verdict/marker validation, safe summary upload, bounded backfill,
and target-based success evaluation.

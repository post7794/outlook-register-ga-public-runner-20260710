# GA automatic service-abuse recovery

This control plane turns the production-verified single-account recovery core
from `service-abuse-recovery-v1.0.0` into a bounded unattended queue.

## Closed loop

```text
fresh ubuntu-22.04 runner
-> reject known-bad GA egress before touching an account
-> authenticate to OutlookEmail
-> list only inactive/quarantined/service_abuse accounts
-> atomically lease one account through ga-coordinator
-> materialize credentials only in runner.temp (mode 0600)
-> production registration natural hold (9.5-12.5s, 22s warmup, one iframe attempt)
-> TierRestore 2xx
-> Graph Inbox 200
-> OutlookEmail writeback + immediate health enrollment
-> complete lease with a safe outcome
-> cleanup all private material
```

One matrix slot uses one fresh GitHub-hosted runner and at most one account.
Scheduled and ordinary manual runs default to the single slot `[1]`; a manual
batch may supply up to 20 unique slots and run them in parallel. A retry must
be a new dispatch and therefore receives a different GA runner/egress. The
repository-wide concurrency group prevents separate workflow runs from
overlapping, while per-slot request/run ids and the server lease prevent
duplicate account work inside a matrix batch.

## Coordinator contract

The existing authenticated timestamp coordinator now also exposes:

```text
POST /v1/recovery/leases
POST /v1/recovery/leases/complete
GET  /v1/recovery/stats
```

Only account ids and quarantine-generation timestamps enter coordinator state.
Mailbox addresses, passwords, refresh tokens, OutlookEmail login material, and
full egress IPs are never sent to the coordinator.

Lease properties:

- one active lease per account;
- idempotent `request_id`;
- 25-minute default TTL;
- three attempts per quarantine generation;
- 15-minute retryable cooldown;
- five-minute technical cooldown;
- six-hour exhausted-cycle cooldown;
- 24-hour terminal/success cooldown;
- a new `quarantined_at` generation resets the attempt budget.

Expired jobs consume an attempt and receive a technical cooldown instead of
silently releasing an account into a duplicate runner.

## Workflow

Public execution workflow: `.github/workflows/ctf-ga-service-abuse-auto.yml`.
It checks out the pinned private recovery-control source from
`xbox-cn/outlook-register-ga-xvfb-action-20260707` before any account work.

The browser runtime is pinned to registration production commit
`875b0571d5b9c88b89a5bbc64f30488ee9565962`. Recovery uses the same natural
hold envelope and first-hold warmup, but deliberately keeps `hold_retries=1`;
Microsoft parent-page Retry remains bounded at two and iframe Retry is never
clicked. `natural_final_proof_mode=minimal` also restores the registration
path's narrow live PX561 normalizer; `off` retains the earlier timing-only
recovery control. Neither mode rewrites a collector response. The accelerated
5s path remains available for experiments but is not
the automatic-recovery production path because it recovered 0/6 GA fresh
challenge slots in the latest registration validation.

This distinction is material: the timing-only `off` recovery baseline reached
11 natural 10s captcha challenges and received 11 live collector `result|-1`
responses. Registration success evidence was produced with `minimal`, not
`off`, so hold duration alone was not an equivalent runtime treatment.

The private repository retains the canonical recovery source and an equivalent
workflow template, but its organization currently cannot allocate hosted
runners because of an Actions billing restriction. Run `29446705922` was
rejected before checkout and before account leasing. Production execution must
therefore originate in this already-validated public runner repository; this
is a runner-allocation boundary, not a recovery result.

Manual dispatch always runs. The 15-minute schedule is fail-closed behind:

```text
SERVICE_ABUSE_AUTO_ENABLED=true
```

For a bounded 20-runner validation batch, dispatch with:

```text
job_slots_json=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]
```

The input accepts 1-20 unique integer slots in the range 1-20. Redacted
artifacts are named `ga-auto-recovery-safe-<run_id>-<slot>` so every slot can
be audited independently. Set `natural_final_proof_mode=minimal` for the
registration-equivalent treatment or `off` for the prior live-payload control.
Keep the defaults `[1]` and `minimal` for scheduled operation.

Keep the variable `false` during deployment and smoke validation. Enable it
only after one manually dispatched run proves the entire lease, recovery,
writeback, and observation-group transition.

Expected repository configuration:

```text
variable GA_COORDINATOR_URL
secret   GA_COORDINATOR_TOKEN
secret   OUTLOOK_EMAIL_WRITEBACK_CONFIG_B64
secret   SERVICE_ABUSE_EXPERIMENT_KEY
secret   SERVICE_ABUSE_BROWSER_ENV_B64
```

The OutlookEmail configuration contains its base URL and login password. It is
decoded only into `runner.temp`, is never uploaded, and is deleted in the
always-run cleanup step.

## Outcome semantics

`workflow conclusion` is not the recovery result. Expected Microsoft/egress
failures are recorded and the orchestration job can still finish cleanly.
Promotion requires the redacted verdict to show:

```text
service_abuse_cleared=true
graph_ok=true
production_writeback_ok=true
production_health_enrolled=true
outcome=success
```

Important categories remain separate:

- `LOGIN_RATE_LIMIT_IPBAN`: retry on a fresh runner;
- Microsoft parent-page service error/risk rejection/HumanCaptcha failure:
  retryable after cooldown;
- `PREFLIGHT_ACCOUNT_ALREADY_HEALTHY`: reconcile through OutlookEmail refresh
  instead of opening the browser;
- `PREFLIGHT_NOT_EXACT_SERVICE_ABUSE`: not a recovery candidate;
- missing fixture credentials: terminal for the current generation;
- missing status or coordinator/writeback failure: technical, not captcha.

Safe artifacts contain account id, attempt number, hashed lease/egress ids,
state booleans, and error category only.

## Deployment and rollback

The production coordinator source is tracked in the private recovery repository
at `tools/ga_coordinator_server.py`. Before installing it, back up both the old
source and the SQLite database. The first deployed migration backup is:

```text
/opt/ga-final-coordinator/backups/20260715T195204Z
```

Rollback restores `server.py` from that directory and restarts
`ga-final-coordinator.service`. The added SQLite tables are additive and do not
change the existing `/v1/reservations` contract.

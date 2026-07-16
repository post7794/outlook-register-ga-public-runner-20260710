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

`recovery_network_mode` defaults to `ga_own_ip`.  The manual-only
`proxy_pool` treatment consumes a gzip/base64 curated pool from
`CTF_PROXY_POOL_GZIP_B64`, selects one isolated node per matrix slot, and starts
the pinned Mihomo `v1.19.28` locally. `proxy_pool_slot_offset` defaults to `0`
and selects later non-overlapping waves without changing matrix slot ids.
Before account materialization or lease
acquisition, the runner requires two identical effective public-IP samples and
successful transport to Microsoft login, token, and Graph metadata endpoints.
The temporary browser manifest and token/Graph client then both use
`http://127.0.0.1:17890`; this prevents a browser-proxy/direct-Graph split.
Public logs and artifacts retain only mode, HTTP statuses, IP prefix, and
hashes.  Pool contents, node names, node addresses, and full IPs stay private
and are removed by the always-run cleanup step.

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

The browser/controller runtime is pinned to registration production commit
`875b0571d5b9c88b89a5bbc64f30488ee9565962`. Recovery overlays the
recovery protocol runtime blob
`6213f5a531dad34491c7860e19a7ade985a302f7`; this retains registration's
natural hold implementation while restoring the recovery-specific early-W0
pending route. Both object ids are checked before account work. Recovery uses
the same natural hold envelope and first-hold warmup, but deliberately keeps
`hold_retries=1`;
Microsoft parent-page Retry remains bounded at two and iframe Retry is never
clicked. `natural_final_proof_mode=minimal` also restores the registration
path's narrow live PX561 normalizer; `off` retains the earlier timing-only
recovery control. `ads_safe` is the recovery-shaped treatment that preserves
and narrowly normalizes BFA/final telemetry. These final-proof modes do not
rewrite the live PX561 collector result; the separately gated W0 treatments
can alter only the iframe-facing W0 response. The accelerated
5s path remains available for experiments but is not
the automatic-recovery production path because it recovered 0/6 GA fresh
challenge slots in the latest registration validation.

This distinction is material: the timing-only `off` recovery baseline reached
11 natural 10s captcha challenges and received 11 live collector `result|-1`
responses. Registration success evidence was produced with `minimal`, not
`off`, so hold duration alone was not an equivalent runtime treatment.

`natural_w0_bridge=true` is a separate bounded treatment. It keeps a rejected
final neutral long enough to exercise the same W0 handoff used by the one
verified automatic recovery, while retaining the natural 9.5-12.5s physical
hold. The bridge may alter the iframe-facing final/W0 response sequence, so a
collector `result|0` is only an intermediate signal; real
`risk/verify state=continue` and `TierRestore` 2xx remain mandatory.
When `natural_server_challenge_rounds` is above one, another hold is allowed
only after the current round records collector `result|0` and a later real
`risk/verify` response issues a new HumanCaptcha continuation. A `result|-1`,
`HumanCaptcha_Failure`, or a plain visible iframe Retry never opens a round.

The default strict rule above remains unchanged. A separate manual-only input,
`natural_force_w0_after_minus1=true`, reproduces the one historical recovery
mechanism that reached `TierRestore`: its first two live PX561 finals returned
`result|-1`, the iframe received a synthetic W0 `result|0`, Microsoft issued a
fresh HumanCaptcha each time, and the third live PX561 final returned
`result|0` before `risk/verify state=continue` and `TierRestore 200`. The input
is rejected unless `natural_w0_bridge=true` and at least two rounds are
configured. It defaults to `false`, is not enabled by the schedule, and does
not make a visible iframe Retry eligible.

`recovery_human_mode` selects the physical/protocol execution path and defaults
to `natural10`.  The manual-only `exact5s` treatment checks out the admitted
`00b6843` runtime, installs the historical 15s fake / 6.5s wall semiprotocol,
and can combine it with the same bounded force-W0-after-real-`-1` bridge.  In
this mode a live backend `result|-1` is not immediately terminal: the runner
waits at most 15 seconds for the routed synthetic W0, then requires a later real
Microsoft `risk/verify` response before another hold.  A plain iframe Retry is
still terminal.  `exact5s` is accepted only with `ads_safe`, W0 bridge enabled,
and a bounded server-round budget; scheduled operation remains `natural10`.
`exact5s_release_mode=cdp_up` preserves the locally proven input path.  The
separate `page_up` treatment changes only the release backend: pointer down/up
are paired through `page.mouse` while the dense in-hold movement remains raw
CDP.  This isolates hosted-Cloak release delivery when a hold produces no final
PX561 at all; it does not relax any result/risk/TierRestore acceptance gate.
`exact5s_move_steps` is independently bounded to `1..24` and defaults to the
historical `24`.  It exists because current hosted runners spend roughly
0.9-1.3s synchronously dispatching 24 CDP moves, versus about 0.4s in the older
GA success traces.  Lowering this count changes only in-hold sample density;
the 15s fake hold, 6.5s paced wall hold, final normalization, W0 bridge, and
host acceptance gates remain unchanged.
`exact5s_hold_attempts` defaults to one and is bounded to two, matching the old
registration wrapper only when explicitly selected.  It is a per-rendered-
challenge delivery retry, separate from `natural_server_challenge_rounds`:
real result/W0/host outcomes are still consumed in order, and a fresh server
round still requires the accepted result0 plus later host rechallenge boundary.
`exact5s_final_xghm_target` is a separate default-off (`0`) experiment.  With a
positive target, every XGhm-bearing member of the final event family is aligned
from the bounded zero-based `exact5s_final_xghm_start_index`; all other fields
and earlier finals stay live.  The current treatment uses index `1` and
`272.1`, matching the only historical real-result0 recovery final while
preserving the first live final/W0 handoff.

Run `29471147049` falsified XGhm as a sufficient cause.  Of 20 nominal slots,
9 effective GA egresses leased accounts, 7 produced complete runtime evidence,
and 2 reached the 30-minute job watchdog.  The 7 observable samples made 16
physical holds and 10 real PX561 finals; every live backend result was `-1`.
Four second finals explicitly recorded `forced_xghm_applied=true` and
`XGhm=272.1`, yet all four still returned `result|-1` and their following
synthetic-W0 host verification returned HTTP 403.  The only proven
TierRestore recovery used a separately selected stable HK proxy, so the next
controlled treatment changes network provenance while returning XGhm to live
values.

The latest GA natural run also showed why the raw round-two `PX.R3-UI`
484-630ms values were not the deciding defect: those values were logged from
the pre-normalization `before` packet. Because the same packets take the
`ads_long_fallback`, the existing normalizer already emits a 1410-1520ms tail.
The safe probe now records `ads_safe_envelope_path`, post-normalization
`after_px`, the live backend final result, and an explicit message whenever a
synthetic W0 result is forced after a real `result|-1`.

Run `29461411836` then isolated the next state-transfer bug. Of 20 slots, 8
egresses were admitted and all 8 obtained an account/hold. Five iframe-facing
W0 responses carried `result|0`; two were explicitly forced after a live
`result|-1`. One of those two received a later real Microsoft
`risk/verify 200` HumanCaptcha continuation, but no round two started because
Playwright's passive response listener did not observe the route-fulfilled W0
body. The risk/verify gate had already recorded the same scoped result and
timestamp. Fresh-round proof selection now merges both sources and chooses the
newest terminal result, so a route-fulfilled W0 cannot be lost while stale
results from earlier holds remain excluded.

The overlay is required by runtime evidence: the registration-only protocol
blob fulfilled W0-before-final immediately as neutral, so only 1/6 natural W0
bridge attempts reached `result|0`. The recovery release keeps that actual W0
request pending until the final handler can resolve it, without changing the
9.5-12.5s physical hold.

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
registration-equivalent treatment, `ads_safe` for the recovery-shaped BFA
treatment, or `off` for the prior live-payload control.
Keep the defaults `[1]`, `minimal`, `natural_w0_bridge=false`, and
`natural_force_w0_after_minus1=false` for scheduled operation;
`natural_server_challenge_rounds` also defaults to `1`, and
`recovery_network_mode` remains `ga_own_ip`. Use a bounded value
such as `3` only for the W0/fresh-round treatment until it proves the complete
TierRestore/writeback loop.

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
secret   CTF_PROXY_POOL_GZIP_B64             # proxy_pool experiments only
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

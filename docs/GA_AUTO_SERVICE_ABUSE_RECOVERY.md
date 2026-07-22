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

`runner` defaults to `ubuntu-22.04`, including every scheduled run.  Manual
experiments may select `windows-2022`; that path uses native Windows fonts and
Cloak Chromium without Xvfb, the pinned Windows Mihomo binary, and the same
egress admission, coordinator lease, writeback, verdict, and cleanup contract.
No other runner labels are accepted.

`recovery_network_mode` defaults to `ga_own_ip`.  The manual-only
`proxy_pool` treatment consumes a gzip/base64 curated pool from
`CTF_PROXY_POOL_GZIP_B64`, selects one isolated node per matrix slot, and starts
the pinned Mihomo `v1.19.28` locally. `proxy_pool_slot_offset` defaults to `0`
and selects later non-overlapping waves without changing matrix slot ids.
`proxy_pool_profile=unseen` is the normal multi-slot treatment.  The separate
`known_success` positive control reads
`CTF_PROXY_KNOWN_SUCCESS_GZIP_B64` and is fail-closed to exactly
`job_slots_json=[1]`, offset zero, and proxy mode, so the one previously
TierRestore-proven node can never be fanned out concurrently. Admission also
requires its effective egress hash to match
`CTF_PROXY_KNOWN_SUCCESS_EGRESS_SHA16`; matching a node configuration alone
is not treated as matching the proven network path.
Before account materialization or lease
acquisition, the runner requires two identical effective public-IP samples and
successful transport to Microsoft login, token, and Graph metadata endpoints.
All three Microsoft checks use the same local proxy.  The token check is an
intentionally credentialless POST, so either HTTP 400 or 401 is the expected
OAuth-layer rejection; redirects, transport failures, and other statuses are
not admitted.
The temporary browser manifest and token/Graph client then both use
`http://127.0.0.1:17890`; this prevents a browser-proxy/direct-Graph split.
Public logs and artifacts retain only mode, HTTP statuses, IP prefix, and
hashes.  Pool contents, node names, node addresses, and full IPs stay private
and are removed by the always-run cleanup step.

Run `29492836765` was a gate-only invalid trial, not a recovery result.  It
leased zero accounts: 13/20 proxy exits were stable and 18/20 reached the three
Microsoft probes with HTTP `200/401/200`, but the first gate required token
HTTP 400 exactly.  The corrected gate keeps all Microsoft probes on the same
selected proxy and accepts the observed OAuth-layer 400/401 rejection.

Run `29496089427` proved why the egress-hash gate is necessary. The
previously successful node started correctly on GA and passed all three
Microsoft transport probes, but its effective exit differed from the local
TierRestore-success exit because the provider routes by ingress region. No
account was leased, and that run is not a captcha result.

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
the imported handler at `hold_retries=1`;
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
When `natural_server_challenge_rounds` is above one, another server round is
allowed only after the current round records collector `result|0` and a later
real `risk/verify` response issues a new HumanCaptcha continuation. A
`result|-1`, `HumanCaptcha_Failure`, or a plain visible iframe Retry never
opens a fresh server round. The one exception is narrower and does not open a
server round: the exact registration-equivalent same-challenge arm may scope
the failure telemetry from the just-finished hold as expected retry evidence
when the hold-scoped collector/real final is `-1` (or still absent) and the
unchanged controller explicitly reports actionable `retry`.
`natural_same_challenge_hold_attempts` is a separate outer-hold budget and
defaults to `1`. Value `2` is accepted only for the registration-overlay
natural10 bridge+force three-round treatment. It authorizes one second hold
only when the first hold reaches its proof deadline without a final result or
host transition and the unchanged challenge is still actionable. This guarded
no-evidence retry does not match registration's three-hold retry budget, so
`registration_retry_budget_equivalent` remains false.

Value `3` is a separate registration-equivalent arm. It requires the 875b057
registration overlay, `natural10`, `minimal_natural_hold`, both W0 options
disabled, a three-round hold budget, and `ubuntu-22.04`. The imported handler
remains one-shot, while the outer state machine reproduces up to three physical
holds with registration's motion, 9.5-12.5s hold envelope, first-hold warmup,
and per-hold 16s proof wait. A stable live `result|-1` or no final can authorize
the next same-challenge hold. Only this exact arm may continue after a
hold-scoped `HumanCaptcha_Failure`;
the collector/real final must remain `-1` (or absent), and the controller
must still report actionable `retry` on the unchanged challenge. The
observed registration-shaped tuple is `-1 + HumanCaptcha_Failure + retry`.
The ordinary one-shot and guarded W0 arms still fail closed on any
`HumanCaptcha_Failure`; so does a failure with no `retry` state, a new failure
after a retry token was issued, `result|0`, a risk generation or verify-count
change, host transition, HumanCaptcha success, or `TierRestore`. Each retry uses
a one-use token bound to the risk generation, verify request/response counters,
and the monotonic failure count observed at issuance. Any later failure event
invalidates the token before mouse-down. The token is checked again immediately
before mouse-down, and the second and third confirmed mouse-downs are recorded
separately in the safe verdict. The public runner applies the same narrow,
hash-verified controller patch to the exact 875b057 runtime for both multi-hold
arms; it does not replace that runtime with the current controller.

### Canary evidence: run 29953150800

Run `29953150800` was a three-slot registration-equivalent canary. It is
evidence about retry-state handling, not an unblock success or a captcha-rate
estimate.

- Slot 1 passed egress admission and obtained a lease. The first hold produced
  a live collector/real final `-1`, then `HumanCaptcha_Failure` and an iframe
  Retry state. The run ended with `HUMAN_CAPTCHA_FAILURE_NO_RETRY` before a
  second mouse-down (`natural_same_challenge_second_hold_executed=false`).
  This is the pre-fix proof that a global sticky failure flag prevented the
  registration-shaped retry sequence.
- Slot 3 passed admission and obtained a lease. The first hold had no final;
  the same-challenge guard entered the second-hold attempt/movement path, but
  the log has no retry-token-consumed, mouse-down-confirmed, or holding-for
  evidence. The later collector `result|0` and `HumanCaptcha_Success`
  therefore cannot be attributed to a second physical press. The subsequent
  `risk/verify` returned HTTP 403 and the process hit the watchdog
  (`RECOVERY_PROCESS_WATCHDOG_TIMEOUT`) before host continue or TierRestore.
  Its timeout-safe verdict correctly left the second-hold execution fields
  false, so it is not a countable strict sample.
- Slot 1's completion call also returned a transient coordinator 404. The
  completion artifact was missing and did not prove operation-lease release;
  this is a coordinator/cleanup observation independent of the captcha result.
  Slot 3 later completed through the same path with
  `outlook_operation_lease_released=true` and an empty release error, which
  supports treating the slot 1 404 as transient until reproduced otherwise.

The default strict rule for ordinary one-shot runs remains unchanged. Both
multi-hold arms require ordered real-final/host/TierRestore evidence before
they can report `strict_run_succeeded`. A separate manual-only input,
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

The recovery subprocess also has an OS-level watchdog independent of the
30-minute Actions job ceiling.  On Linux, at 900 seconds it receives TERM,
followed by KILL after a 15-second grace period.  Windows terminates the whole
Python/Chrome process tree at the same deadline because it has no equivalent
reliable POSIX TERM boundary.  Exit 124/137 is classified as
`RECOVERY_PROCESS_WATCHDOG_TIMEOUT` only when the runtime did not already
write a safe status, so a more specific completed result is never overwritten.
Partial redacted probe output remains available, and the always-run completion
step can release the lease and apply the normal retry classification instead of
ending with `STATUS_FILE_MISSING`.

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
be audited independently. Set `natural_final_proof_mode=minimal_natural_hold`
with `registration_natural_overlay=true` for the registration-runtime arms,
`ads_safe` for the recovery-shaped BFA treatment, or `off` for the prior
live-payload control.
Keep the defaults `[1]`, `minimal`, `natural_w0_bridge=false`, and
`natural_force_w0_after_minus1=false` for scheduled operation;
`natural_server_challenge_rounds` and
`natural_same_challenge_hold_attempts` also default to `1`, and
`recovery_network_mode` remains `ga_own_ip`. Use `2` only for the guarded
W0/fresh-round treatment and `3` only for the registration-equivalent arm
until either treatment proves the complete TierRestore/writeback loop.

Keep the two multi-hold mechanisms in separate dispatches:

```text
guarded W0 arm:             holds=2, bridge=true,  force=true,  rounds=3
registration-equivalent:   holds=3, bridge=false, force=false, rounds=3
```

Both require `registration_natural_overlay=true`, `natural10`,
`minimal_natural_hold`, and `ubuntu-22.04`.

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
secret   CTF_PROXY_KNOWN_SUCCESS_GZIP_B64     # single-slot positive control
secret   CTF_PROXY_KNOWN_SUCCESS_EGRESS_SHA16 # expected anonymized egress id
```

The OutlookEmail configuration contains its base URL and login password. It is
decoded only into `runner.temp`, is never uploaded, and is deleted in the
always-run cleanup step.

## Outcome semantics

`workflow conclusion` is not the recovery result. Expected Microsoft/egress
failures are recorded and the orchestration job can still finish cleanly.
Promotion requires the redacted verdict to show:

```text
natural_real_final_results[-1]="0"
natural_host_continue=true
natural_tier_restore_success=true
natural_evidence_ordered=true
service_abuse_cleared=true
graph_ok=true
production_writeback_attempted=true
production_writeback_ok=true
production_health_enrolled=true
strict_run_succeeded=true
completed=true
outcome=success
outlook_operation_lease_released=true
outlook_operation_lease_release_error=""
```

For either same-challenge treatment, count only slots with
`egress_admitted=true`, `leased=true`, and
`natural_same_challenge_second_hold_executed=true` as experimental samples.
The registration-equivalent arm additionally requires
`natural_same_challenge_third_hold_executed=true` for a three-hold sample.
Configured attempts or `natural_holds_used` alone do not prove that the
generation-bound second or third mouse-down occurred.

A `HumanCaptcha_Failure` in a safe artifact is not, by itself, proof that a
retry hold was authorized. Only the exact registration-equivalent arm may
continue after the current hold when its scoped final is `-1` (or absent) and
the unchanged challenge reports `retry`; all other failure events remain
fail-closed for that run and may only be retried after the normal cooldown.

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

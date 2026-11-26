# Intel charge control feasibility and security design

Issue #3; target MacBookPro11,5, Intel, macOS 12.7.6 (21H1320).
Decision: conditional GO for backend development; NO-GO for production writes until gates below pass. This document does not authorize writes.

## Evidence (2026-11-26)

- AppleSMC gen 2, firmware 2.30f2. Battery 4552/8600 mAh (~52.9% retention), service warning, PermanentFailureStatus 0 at baseline. SIP enabled. Do not force discharge or calibrate.
- bclm 0.1.0 installed by Homebrew. AlDente active: BCLM 15; graceful quit: 76 (earlier 77); app/helper absent from process listing. No bclm persistence detected in checked paths and system launchctl.
- Owner-approved 76 → 75 → 76: both writes read back correctly. 76 → 82 → 76: previously not charging at macOS 79%, then reported charging within first 10-second sample (1232 mA, 30.15°C, 12.101 V). Rollback readback 76; still charging at 10 seconds, subsequently stopped. Six later observations at 09:57:26–09:58:16 CET: 0 mA, not charging, 3462/4552 mAh (~76.05% raw), macOS 80%. Identical samples may be cached; exact transition latency unknown.
- One sleep/wake cycle retained 76; restart with AlDente autostart enabled returned 15 and competing processes. Repeat restart without AlDente retained 76, AC attached, 79%, not charging.
- These tests establish response to the upstream Intel write operation, not isolated BCLM-only causality or complete controller rollback. No other model validated. No serial numbers retained.

## Source and licensing review

Reviewed exact tag [bclm v0.1.0](https://github.com/zackelia/bclm/tree/v0.1.0): [LICENSE](https://github.com/zackelia/bclm/blob/v0.1.0/LICENSE), [main.swift](https://github.com/zackelia/bclm/blob/v0.1.0/Sources/bclm/main.swift), [SMC.swift](https://github.com/zackelia/bclm/blob/v0.1.0/Sources/bclm/SMC.swift), Package.swift and README. Homebrew [formula](https://github.com/zackelia/homebrew-formulae/blob/main/Formula/bclm.rb) references release v0.1.0; installed binary not independently hash-verified.
- MIT, Zack Elia (2020); embedded SMCKit code MIT, beltex (2014–2017). Compatible with Durly MIT provided notices accompany copied substantial portions. Review transitive dependencies if reused; no code copied in this PR.
- Intel CLI validates 50–100 and root privileges, writes BCLM as one byte, then attempts BFCL = value minus 5 (missing BFCL ignored); may update persistence plist. BFCL is associated with charge indicator according to source comments. Errors in run() are printed, not consistently propagated. Exit success alone is insufficient.
- **Correction to earlier test interpretation:** BFCL may have changed in both tests; original BFCL was not captured. Restoring BCLM to 76 does not establish BFCL restoration. Do not guess original BFCL or write it now.
- SMC transport uses private AppleSMC IOKit interface and an 80-byte request structure; not a supported public charge-control API. Validate metadata, size, return codes and readback. Upstream README notes displayed charge can overshoot configured value; no fixed conversion promised.
- Apple Silicon CHWA is separate and unverified; exclude from scope. No reuse of proprietary AlDente code.

## Proposed architecture for #6

Unprivileged UI → portable PowerControl protocol → capability/safety coordinator → authenticated narrow IPC → isolated privileged helper → native Intel BCLM transport.
ReadOnlyBackend is always available; no root UI, no shell execution, no user-writable Homebrew executable launched as root, no arbitrary key or byte write interface. Only query capability/status, apply validated limit and restore recorded baseline. BFCL excluded from write allowlist; read-only metadata probe may investigate it. BCLM-only behavior must be separately verified on hardware before enabling. If coupled operation is necessary, stop and require new design review, full baseline capture and specific authorization.

Monterey candidate: SMJobBless with Authorization Services and mutually specified code-signing requirements (see [Apple SMJobBless](https://developer.apple.com/documentation/servicemanagement/smjobbless%28_%3A_%3A_%3A%29?language=objc)). Installation authorization is not IPC authentication. Use authenticated peer identity tied to the connection (not caller-supplied PID, name or path); validate both endpoints and protocol version. Public supported mechanism on Monterey and CLT-only signing/build must be demonstrated before adoption. If unavailable, remain read-only; do not weaken checks or use deprecated arbitrary privileged execution. No signing identity assumed available. Root-owned immutable helper and state directory; restrictive permissions, no symlink traversal, authenticated explicit enablement, no secrets in logs. Reject malformed requests, unauthorized clients, replay/stale requests and out-of-range values. Serialize operations and rate-limit requests; no network. Verify installation, update and uninstall paths.

## Transaction and recovery contract

1. Explicit opt-in separate from installation, target model/OS/architecture allowlist, fresh telemetry, AC present, stable health/temperature checks, compatible key metadata, known reversible baseline, no competing controller or unresolved transaction. Service warning blocks unattended control pending documented safety review; no discharge/calibration.
2. Persist root-owned recovery record atomically before write: version, device compatibility context, original value, expected value, transaction ID and state. If record cannot be persisted, do not write. Compare live value immediately before write; process/service checks and drift detection reduce risk, do not prove exclusive ownership.
3. Apply one scoped operation, check transport result and independent readback; distinguish requested, verified register and observed charging state. On mismatch, suspend and inspect. No blind retries or automatic escalation.
4. Pause/quit/uninstall request restore recorded baseline only if ownership and current state match expected values, safety checks permit and baseline is validated. Never assume 100 is original/default. On external drift, unknown ownership or failed restoration: stop writes, retain record, show actionable recovery state and manual administrator guidance. No fighting AlDente.
5. Crash/restart/wake: inspect record and live state first, never silently reapply. Restore only under verified safe ownership conditions; otherwise latch read-only. A crash/power loss may leave limit active; UI and docs must disclose this. Uninstall must not erase unresolved recovery evidence. No automatic persistence daemon writing on boot.
6. Monitor actual power response asynchronously with bounded observation and cooldown; no promise of exact threshold or immediate stop. Any conflicting controller, stale telemetry, permission loss, abnormal sensor values or unexpected key changes disables control.

## Gates and test plan

| Gate | Status |
|---|---|
| Target read-only telemetry and upstream CLI response | Observed |
| BCLM register write/readback/restore | Observed |
| BFCL baseline and isolated BCLM behavior | Not verified |
| Sleep/wake and restart retention | Observed once each without detected competitor |
| Signed helper installation and authenticated IPC on Monterey | Not verified |
| Failure recovery, concurrent controller and uninstall | Not verified |
| Production activation | NO-GO |

#6 may implement portable interfaces, mocks, capability detection and disabled backend. Before real writes: independently review native transport, validate BCLM-only operation with bounded owner-approved test and recovery plan, establish supported authenticated helper mechanism and signing, define conservative safety gate for service-warning battery. Test permission denial, malformed request, unsupported model/key metadata, stale/missing telemetry, drift, failed write/readback, failed rollback, journal corruption/crash at each transaction stage, sleep/restart and uninstall. Linux CI portable tests only; native build and physical tests local with evidence. Never enable unverified control or automatically merge safety-sensitive changes.

No further hardware operations required for this documentation PR. Issue #3 historical acceptance criterion about documenting helper security before writes was only partially satisfied (bounded shell rollback documented; production helper architecture follows the tests); record this sequencing exception rather than claiming it was met retroactively.

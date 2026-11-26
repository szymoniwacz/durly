# Power control backend — issue #6

Dependency preflight: #3 and #4 closed; main includes the feasibility report and telemetry.
Scope: portable contract, capability classification, read-only production implementation, pure transaction rules and tests. No privileged executable, native SMC transport, or hardware writes in this increment.

Production capability never returns writable: the exact researched target is unverified for isolated BCLM and authenticated helper; all other devices are unsupported. No user setting can bypass this. The UI remains read-only and reports the distinction. No external dependency.

Transaction rules are pure and have no production write caller. They reject permission denial, suspected/unknown competitor state, absent/stale/future telemetry, non-AC power, missing state, non-normal health, out-of-range limits and invalid baseline. The 15-second age and 10–40°C band are conservative provisional test constraints, not validated physical safety thresholds. A service warning blocks this path. Restore uses the captured baseline only when the live value still matches the expected value. Never guess a default of 100.

Future helper must independently enforce authentication, scope, fresh telemetry, device identity, journal durability, live compare/readback, and crash recovery. The planner does not prove ownership or provide a durable journal. No production transport or signing path is implemented. An injected simulation coordinator exercises journal-before-write, readback, failure latch and baseline restoration with in-memory test doubles. It has no native transport or production caller. Recovery is not proven on physical hardware. See [feasibility report](intel-charge-control-feasibility.md).

Validation: SwiftPM and standalone runner on Linux; native CLT build and UI locally. No hardware writes needed. Issue #6 stays open until the isolated native transport and authenticated helper/recovery gate are resolved or a deliberate NO-GO fallback-only outcome is accepted.

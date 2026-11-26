# Durly Roadmap

See [product requirements](../../docs/product-requirements.md) and [scope](scope.md).

## Completed foundations
- #2 readiness; #3 conditional SMC feasibility (not production authorization); #4 telemetry; #5 native UI.
- #16 and #17 merged partial #6: portable simulation and manual read-only SMC diagnostics.

## Active — v0.1.0 Monitoring & Analytics
1. #19 Persistent history and battery identity — first priority, new battery planned 2026-11-27.
2. #20 Extended read-only telemetry (independent of #19; additive history integration).
3. #21 Analytics and anomaly detection (depends on #19 and #20).
4. #22 Alerts and recommendations (depends on #21).
5. #23 Dashboard and usage insights (depends on #21 and #22).
6. #8 Diagnostics/export and optional startup (depends on #5, #19, #20).
7. #9 Physical monitoring acceptance (depends on #8, #19–#23).
8. #10 Monitoring-only release (depends on #9; owner approval).

## Later — proposed v0.2.0 Manual Battery Care
- #6 secure verified backend, explicit user-triggered operations only; draft PR #18 paused and preserved. Requires new battery baseline, security and recovery evidence and owner authorization. No unattended writes.

## Later — proposed v0.3.0 Smart Battery Care
- #7 policy/hysteresis; first shadow-mode simulation, then separately authorized automatic control after validation.
- Advanced profiles, scheduling, optional discharge/calibration, additional platform support remain deferred.

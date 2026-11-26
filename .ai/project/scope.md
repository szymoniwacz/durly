# Scope

## Active milestone: v0.1.0

- Read-only native menu bar app on MacBookPro11,5 / macOS Monterey 12.7.6.
- Battery telemetry, capability detection, settings, diagnostics and local Release .app.
- Persistent per-battery history, expanded read-only telemetry, analytics, anomaly detection, alerts, recommendations and dashboard (#19–#23). No manual or automatic charge control in v0.1.0; no privileged helper required.
- Optional opt-in launch at login if compatible and time permits.
- Issues #2–#5, #8–#10 and #19–#23 define the monitoring milestone; #6–#7 deferred.

## Constraints

SwiftPM and Command Line Tools; no full Xcode, Codex or Cursor. Linux-only CI; native builds and physical checks locally. Product implementation follows readiness and dependency gates.

## Deferred

Apple Silicon, older macOS releases, adaptive profiles, full Sailing Mode, forced discharge, calibration, thermal control, manual and automatic charging control, scheduling, broad distribution and notarization. Revisit after validated MVP. Never enable unsupported controls.

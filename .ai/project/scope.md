# Scope

## Active milestone: v0.1.0

- Read-only native menu bar app on MacBookPro11,5 / macOS Monterey 12.7.6.
- Battery telemetry, capability detection, settings, diagnostics and local Release .app.
- Verified, reversible charge limiting and basic hysteresis only after issue #3 establishes safe support and owner approves hardware testing.
- Optional opt-in launch at login if compatible and time permits.
- Issues #2–#10 define acceptance and dependencies.

## Constraints

SwiftPM and Command Line Tools; no full Xcode, Codex or Cursor. Linux-only CI; native builds and physical checks locally. Product implementation follows readiness and dependency gates.

## Deferred

Apple Silicon, older macOS releases, adaptive profiles, full Sailing Mode, forced discharge, calibration, thermal control, history, scheduling, broad distribution and notarization. Revisit after validated MVP. Never enable unsupported controls.

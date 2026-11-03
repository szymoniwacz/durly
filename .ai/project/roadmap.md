# Durly Roadmap

See [product requirements](../../docs/product-requirements.md) for acceptance criteria and detailed scope.

## Current — Phase 0: Research
- [ ] Verify battery telemetry via IOKit on MacBookPro11,5 + macOS 12.7.6.
- [ ] Investigate minimum deployment target (Monterey baseline; Big Sur and Catalina if feasible).
- [ ] Research safe Intel SMC/BCLM control and test reversibility.
- [ ] Identify Apple's silicon-specific capabilities and constraints.
- [ ] Establish model/OS/feature compatibility matrix.
- [ ] Select signing, helper security and distribution strategy.

## Next — Phase 1: Safe native MVP
- [ ] Native SwiftUI/AppKit menu bar application.
- [ ] Display percentage, source, cycles, health and capacity.
- [ ] Capability detection with read-only fallback.
- [ ] Verified charge limiting with safe stop/recovery where supported.
- [ ] Basic diagnostics export and user-facing status/errors.
- [ ] Unit and integration tests with mock battery backend.

## Later
- [ ] Smart Battery Care profiles and automatic policy engine.
- [ ] Sailing range, optional safe discharge, Top Up and schedules.
- [ ] Temperature protection, history, alerts, storage mode.
- [ ] Cautious, conditional battery-gauge calibration.
- [ ] CLI, Shortcuts and model-dependent MagSafe LED.
- [ ] Validated Apple Silicon support and expanded older macOS matrix.

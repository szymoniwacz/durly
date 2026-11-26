# Project Decisions

- D-01: Native Swift 5.7-compatible code, SwiftUI/AppKit, IOKit, Command Line Tools with direct swiftc builds on the validated Intel Mac; SwiftPM/XCTest for portable Linux CI. The target CLT lacks usable PackageDescription and XCTest; local tests use a standalone runner. Owner explicitly excluded full Xcode, Codex and Cursor. Initial deployment target macOS 12 / Intel.
- D-02: Linux-only CI. Native builds and device validation locally; owner explicitly excluded macOS CI runners.
- D-03: First milestone issues #2–#10. Read-only fallback if safe reversible charging cannot be demonstrated. No forced discharge or calibration during MVP.
- D-04: Product remains offline, local-first and MIT licensed per existing LICENSE.
- D-05: Follow existing branch/PR workflow; owner review and merge, especially for hardware/security-sensitive work.
- D-06: Application commands established in #4 and documented in README; use the local build/test scripts.
- Open: model-specific control, privileged helper/security and recovery architecture require issue #3 evidence and owner approval before control implementation. Signing/notarization beyond local build deferred to distribution.

- D-07 (2026-11-26, owner reprioritization): v0.1.0 is monitoring and analytics only. History and per-battery identity first, then telemetry, analytics, alerts and dashboard. #6/#7 deferred; #18 retained as draft. Manual control is a later gated milestone; automatic control later still, preceded by shadow simulation. No privileged access needed for active scope.
- D-08 (proposed implementation defaults): local SQLite history, random per-battery epoch IDs, explicit replacement confirmation on ambiguous identity, no raw serials in exports, no wake scheduling or invented sleep data. Validate storage and schema design in #19. No automatic history deletion in first increment; retention remains configurable future work.

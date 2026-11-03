# Durly — Product Requirements Specification

**Status:** Proposed · **Version:** 0.1 · **Date:** 2026-11-03  
**Product:** Durly — Smart Battery Care for Mac  
**Source of truth:** This document defines the intended product, not a claim that features already work.

## 1. Vision and success criteria

Durly is a **native, lightweight, free and open-source macOS application** that helps users **maximize the useful lifetime of their MacBook battery**—preferably years before replacement—while keeping the computer practical to use.

This is **not** primarily a tool for getting the longest runtime on a single charge. It is a battery-longevity manager: minimize avoidable chemical aging, protect the battery from unfavorable conditions, track degradation and intervene only when beneficial.

**Product principles**
1. **Longevity first:** avoid unnecessarily high state of charge, heat, deep discharge and cycling.
2. **Set it and forget it:** one understandable automatic care mode; manual controls remain available.
3. **Safety first:** never sacrifice hardware safety for a configured percentage or a calibration schedule.
4. **Native and lightweight:** a real macOS menu bar app—not Electron, a web wrapper or a cloud-dependent service.
5. **Older Macs matter:** support compatible Intel MacBooks and older macOS releases, as far as APIs and hardware permit.
6. **Evidence over promises:** prefer documented battery behavior and real diagnostics to invented health scores.
7. **Privacy and transparency:** local-first data; clearly explain what is measured versus estimated.

**Outcome indicators (not guarantees):** changes in measured full-charge capacity over time; time spent at high charge and high temperature; user overrides; unexpected shutdowns; successful control actions; CPU, memory and energy footprint. No promised number of extra battery years.

## 2. Supported platforms and compatibility

### Platform requirements
- Native **macOS app**, written primarily in **Swift**, with **SwiftUI** where compatible and **AppKit** for older macOS menu bar integration (e.g. `NSStatusItem`).
- Support **Intel MacBooks** including a specific validation target: **MacBook Pro (Retina, 15-inch, Mid 2015), MacBookPro11,5, macOS Monterey 12.7.6**.
- Aspire to support compatible **Apple Silicon MacBooks** with a separate capability implementation, not by assuming Intel SMC behavior applies.
- **macOS 12 Monterey is a baseline validation target, not a reason to require macOS 13+.**
- Aim to support **macOS 11 Big Sur** and investigate **macOS 10.15 Catalina** where technically feasible. Final minimum deployment target is determined after API, build-toolchain, helper and real-device testing.
- Newer macOS releases must be evaluated independently; design for capability detection rather than OS-version guesses.
- Never advertise a model/OS/feature combination as supported until verified with tests or reliable implementation evidence.

### Capability matrix (initial research, not promises)

| Capability | Intel / older macOS | Apple Silicon | Policy |
| --- | --- | --- | --- |
| Read battery charge, cycles and capacity | Investigate via IOKit | Investigate via supported APIs | Read-only first |
| Charge limit | Verify model-specific SMC behavior | Separate implementation required | Enable only after validation |
| Stop/resume charging | Verify SMC interfaces | Separate implementation required | Must be reversible |
| Force discharge while plugged in | Hardware-dependent, may be unavailable | Hardware-dependent, may be unavailable | Optional; disabled by default |
| Temperature measurements | Source-dependent | Source-dependent | Report sensor/source limitations |
| Sleep/reboot persistence | Test helper and event behavior | Test separately | Restore only when safe |
| MagSafe LED | Hardware-dependent | Hardware-dependent | Optional |

An unsupported control must be hidden or clearly disabled with an explanation; read-only monitoring should still work.

## 3. Personas and main workflows

- **Desk user:** MacBook plugged in most of the day. Keep the battery in a conservative, configurable state-of-charge range without adding unnecessary cycles.
- **Mixed user:** Alternates desk and battery use. Balance mobility with battery longevity.
- **Mobile user:** Needs a higher charge for work or travel; temporarily prioritize runtime.
- **Older-Mac user:** Wants visibility and safe improvements even without recent macOS features.
- **Technical user:** Wants data, history, CLI, diagnostics and explicit control.

### First-run experience
1. Detect Mac model, macOS version, battery telemetry, available control features and limitations.
2. Explain the objective: **long-term battery health**, not maximum hours per charge.
3. Offer **Smart Battery Care** as the sensible default and manual mode for advanced users.
4. Ask permission for privileged actions only when actually needed, and explain why.
5. Never silently write unsupported SMC keys or begin a discharge cycle.
6. Offer a read-only mode if control cannot be safely established.

## 4. Functional requirements

Priority key: **P0** = MVP/core; **P1** = planned; **P2** = exploratory or hardware-dependent.

### 4.1 Battery monitoring — P0
- Show current charge percentage, AC/battery power source, charging state and configured limit.
- Show cycle count, full-charge capacity, design capacity where exposed, and **estimated** capacity retention (with provenance and uncertainty).
- Show voltage, current/power and temperature **only when a reliable source exists**; distinguish raw data, estimates and missing fields.
- Show battery/service health warnings, including macOS "Service Recommended" when reported.
- Be resilient to missing keys, stale values, unexpected sensor readings and battery replacement.
- Avoid treating the macOS percentage indicator as a precise measure of stored energy.

### 4.2 Charge limit — P0, hardware permitting
- Allow a configurable upper charge limit (e.g. 80%) and optionally an adjustable lower bound.
- Stop charging at the chosen threshold and resume according to safe, tested hysteresis behavior.
- Provide clear state: charging / holding / discharging / on AC / unsupported / error.
- Provide a visible one-click **Pause / Resume Durly control** and safe recovery.
- A configured limit must not imply a guarantee that physical charging stops on every Mac model, especially while sleeping or powered off.

### 4.3 Smart Battery Care — P0/P1
- One-toggle mode that selects a conservative policy based on profile and observed usage, without surprising the user.
- Profiles: **Desk**, **Mixed**, **Mobile**, and **Manual**.
- Example starting limits of **70%, 80%, 90%** are *illustrative*, not universally optimal. Configurable and subject to validation.
- Learn patterns from **local** signals (AC connection, charge, time, temperature, user-selected schedule). No requirement for accounts or remote inference.
- Limit unnecessary mode switching and avoid micro-cycling; define a minimum hysteresis and action cooldown.
- Let user override automatic decisions; show why a change was made.
- Model future battery demand conservatively rather than claiming to predict travel.

### 4.4 Temperature protection — P0/P1
- Monitor relevant battery temperature where available; otherwise state that temperature protection is unavailable.
- Suspend or limit charging where verified safe when a configured safety threshold is crossed.
- Restore regular policy with hysteresis after cooling.
- Avoid claiming the app can physically cool a battery or override Apple's internal protection.
- Never rely on Durly as a replacement for hardware safeguards.

### 4.5 Sailing / holding range — P1
- Maintain an upper/lower state-of-charge band where the platform supports it.
- Prefer holding battery level without deliberate cycling when possible.
- Bound frequency of charge/discharge changes.
- Show whether the current Mac can actually implement the requested behavior.

### 4.6 Controlled discharge — P1, opt-in only
- If supported, optionally run the computer from the battery while AC stays attached, to return from a high level to a configured target.
- **Never default to automatic discharge solely to reach 80%.**
- Abort on low charge, abnormal voltage/telemetry, thermal warnings, shutdown symptoms, battery-service warnings or unknown controller state.
- Provide an explicit stop button, timeout, progress display and post-reboot recovery.
- Disable discharge and calibration when battery health is suspect, including erratic percentages or unexpected shutdowns.

### 4.7 Top Up / Travel mode — P1
- One-click temporary charge-to-100% (or configurable temporary target) when needed.
- Optional scheduled deadline, with clear limits about prediction reliability.
- Automatically return to the previous longevity profile after an explicit expiration or completed use case.
- Never continue a temporary override indefinitely without indication.

### 4.8 Calibration and gauge maintenance — P1
- Explain clearly that **calibration corrects state-of-charge estimation; it does not chemically restore lost battery capacity**.
- Do not schedule routine full charge/discharge cycles by default.
- Suggest calibration only when evidence warrants it and only where the procedure is safe and compatible.
- Require confirmation, assess battery health first, and warn of cycle cost, interruption risk and reduced mobility.
- Do not perform calibration on batteries reporting service needs, unexpected shutdowns, severe percentage jumps, or other safety concerns.
- If impossible to safely automate, provide read-only guidance rather than forcing an operation.

### 4.9 Diagnostics, alerts and history — P1
- Record periodic local snapshots (time, source, charge, cycles, capacity, charging state, available temperature/voltage).
- Display capacity trend and estimated degradation over weeks/months; highlight measurement uncertainty, recalibration and battery replacement.
- Notify only on actionable events: abnormal capacity changes, temperature, service condition, charge-control failure, repeated shutdown symptoms.
- Export user-readable diagnostics (Markdown, JSON or CSV). Include OS/model/control capability and **optional**, privacy-aware hardware identifiers.
- Make it obvious when a detected issue is a hypothesis rather than a diagnosed fault.

### 4.10 Storage / long idle mode — P1
- Offer guidance and supported controls for long-term storage at a moderate charge level, with power-off and periodic check reminders when appropriate.
- Never autonomously deplete a battery into a dangerously low state.

### 4.11 Automation and integration — P1/P2
- Scheduled profiles, configurable notifications and launch-at-login.
- Optional CLI and macOS Shortcuts actions: inspect status, change profile, temporary top-up, pause/resume.
- Optional MagSafe LED behavior only where hardware explicitly supports it.
- Optional process energy-consumption information where permitted by macOS APIs; show limitations rather than overclaiming accuracy.

## 5. UX and design

- **Menu bar first:** compact status indicator and a readable popover with charge, limit, mode and state.
- **Simple default view:** battery percentage, health summary, active policy, one clear action.
- **Advanced settings:** manual limits, ranges, temperature rules, calibration, diagnostics and integrations.
- Clear labels; do not overload the user with raw SMC terminology unless in a diagnostics section.
- Dark/light appearance, accessibility, keyboard navigation, VoiceOver, appropriate contrast and localization-ready strings.
- Low notification noise; provide explanatory tooltips for potentially risky actions.
- The app must work without a persistent Dock window; optional dedicated settings/history window.
- Do not copy AlDente branding, UI assets or proprietary code.

## 6. Architecture and implementation

Suggested modules (subject to design review):

```text
DurlyApp (SwiftUI + AppKit status item)
  ├── BatteryTelemetry (IOKit / supported power APIs)
  ├── CapabilityDetector (Mac model, OS, controller)
  ├── BatteryPolicyEngine (profiles, hysteresis, scheduling)
  ├── SafetyController (guardrails and emergency stop)
  ├── BatteryHistoryStore (local persistence)
  ├── DiagnosticsExporter
  └── PowerControl abstraction
          ├── IntelSMCBackend (research/verify per model)
          ├── AppleSiliconBackend (research/verify separately)
          └── ReadOnlyBackend (always-safe fallback)
                  ↕
          Privileged helper (only where required)
```

- Use **Swift** / **SwiftUI**, supplement with **AppKit** on older macOS. Use IOKit or supported system APIs for telemetry.
- Treat **SMC, BCLM and similar controller keys as investigational**, not universal, documented public APIs.
- Never assume AlDente or `bclm` internals directly apply to every supported hardware model.
- Prefer a small, scoped privileged helper with authenticated IPC (e.g. XPC), least privilege and explicit user authorization; use `launchd` only where necessary.
- Keep the battery-control backend isolated so failures cannot crash the UI or silently change policy.
- Reapply state after login/wake/reboot only when appropriate, with verification of current hardware conditions.
- Safe state on helper failure, uninstall, restart or unsupported hardware: do not leave unexplained hidden charge controls active.
- Local settings and database; no mandatory account, telemetry upload, background cloud service or subscription.
- License intended to be open source; confirm repository licensing and third-party dependencies.

## 7. Safety and hard requirements

1. **No unsupported writes:** capability validation required before modifying power-controller state.
2. **Fail safe:** on unexpected telemetry, bad battery health, power disruption or app crash, disable risky actions and surface an actionable message.
3. **No deep discharge:** do not intentionally target 0%; never pursue a threshold at the expense of shutdown risk.
4. **Bad-battery guard:** disable forced discharge/calibration after sudden shutdown, severe state-of-charge jumps or service warning.
5. **Charging safeguards:** preserve hardware/OS thermal and charge protections; never bypass protections.
6. **Explicit user agency:** no hidden calibration, forced discharge or irreversible state changes.
7. **Explain uncertainty:** distinguish battery gauge accuracy, chemical capacity, cycle count and aging.
8. **No false guarantees:** longer battery life depends on chemistry, temperature, age, manufacturing and usage.
9. **Uninstall/recovery:** document how to stop control, remove helper and restore supported defaults.
10. **Data protection:** minimize collected identifiers and sanitize diagnostic exports.

## 8. Non-functional requirements

- **Compatibility:** older supported macOS releases and Intel are first-class; deployable target selected only after build and real-device validation.
- **Efficiency:** minimal CPU wakeups and polling; event-driven monitoring where possible; measurable low energy use.
- **Reliability:** safe operation through sleep/wake, lid close/open, AC changes, restarts, crash recovery and battery replacement.
- **Maintainability:** testable policy engine separated from privileged and hardware-specific code.
- **Testability:** mocked battery provider, simulated hardware failures and state transitions; automated tests plus device test matrix.
- **Observability:** local debug logs with configurable verbosity and sensitive values removed on export.
- **Security:** signed/notarized distribution as feasible; privileged helper with minimized attack surface and safe updates.
- **Offline functionality:** all core functionality works without internet.

## 9. Explicit non-goals

- Rejuvenating damaged battery chemistry, repairing batteries or claiming accurate remaining lifetime predictions.
- Replacing macOS battery safety protections or promising prevention of every unexpected shutdown.
- Supporting every Mac model identically.
- Forcing full discharge as routine maintenance.
- Requiring an online account, monetization, cloud service or cross-platform UI framework.

## 10. Delivery plan and acceptance criteria

### Phase 0 — Research and feasibility
- Document Apple APIs, Intel SMC/BCLM options, existing open-source prior art and license obligations.
- Validate model/OS compatibility, ideally first on **MacBookPro11,5 / Monterey 12.7.6**.
- Build a proof of concept for telemetry, then carefully test whether charge limiting is supported.
- Produce an explicit **supported-features matrix**, with evidence per feature.

### Phase 1 — Safe, native MVP
- Launch as menu bar app on the validated oldest target macOS.
- Read battery charge, capacity, cycles, health state and external power.
- Display clear availability and errors, support read-only fallback and export basic diagnostics.
- Implement a verified charging limit for at least one hardware/OS combination **only if** safe, reversible control is proven.
- Include pause/resume and recovery guidance.

### Phase 2 — Longevity engine
- Smart Battery Care, Desk/Mixed/Mobile profiles, configurable limits and hysteresis.
- Reliable sleep/wake and restart behavior, low-overhead history and alerts.
- Temperature-aware charging only where sensor/control reliability is validated.

### Phase 3 — Advanced care
- Top Up / travel scheduling, holding band, supported optional discharge, cautious calibration guidance, storage mode.
- CLI/Shortcuts integration, historical trends and richer diagnostics.

### Phase 4 — Wider hardware coverage
- Expand verified Intel/macOS combinations.
- Research and implement Apple Silicon backend; adapt capabilities rather than copying Intel control paths.
- Accessibility, localization, documentation and distribution hardening.

**Release acceptance:** never ship a hardware-control feature without (a) an explicit support declaration, (b) tested rollback/recovery, (c) failure-mode tests, (d) clear UI indication and (e) meaningful documentation.

## 11. Open research questions

- Which Intel generations/SMC keys actually support charge limiting, hold and forced discharge?
- Which methods work on macOS 10.15, 11, 12 and newer versions without prohibited or unstable dependencies?
- What architecture is needed for Apple Silicon charge control, if feasible?
- What changes during sleep, full shutdown, AC reconnect, firmware reset and battery swap?
- Which battery temperature and controller telemetry sources are reliable per model?
- What thresholds and hysteresis best balance calendar aging against extra cycling, and what is the evidence?
- What is the safe, user-controlled calibration procedure for various battery generations?
- What packaging, permissions and signing model is appropriate for the chosen oldest supported macOS?

## 12. References / inspirations

- [Apple — Battery information and care](https://www.apple.com/batteries/)
- [AlDente](https://apphousekitchen.com/)
- [AlDente original open-source repository](https://github.com/davidwernhart/AlDente)
- [bclm project](https://github.com/zackelia/bclm)

References are for research and inspiration, **not** proof of compatibility or permission to copy protected assets. Review current code licenses and hardware documentation before implementation.

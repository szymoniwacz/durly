# Project Requirements

## Summary

Durly is a free, native macOS menu bar battery-longevity tool for MacBook owners, initially targeting validation on Intel Monterey. The detailed product specification is [docs/product-requirements.md](../../docs/product-requirements.md). The active milestone is [scope](../project/scope.md); future features in the product specification are not MVP commitments.

## Users and outcomes

Desk and mixed-use MacBook owners need reliable battery visibility, safe charging limits where supported and predictable recovery. Success is a locally runnable application with accurate available telemetry, explicit limitations and no unverified control.

## Core workflows

Launch → detect hardware → display telemetry and support state → adjust settings → optionally enable validated charge control → pause or recover → export sanitized diagnostics.

## Functional requirements

| ID | Requirement | Priority | Evidence/issue |
|---|---|---|---|
| FR-001 | Read available charge, source, cycles, capacity, health and optional reliable sensors | must | #4 |
| FR-002 | Native menu bar UI and persisted settings | must | #5 |
| FR-003 | Detect support and use read-only fallback | must | #3, #6 |
| FR-004 | Verified reversible charge limit, pause and basic hysteresis | conditional on GO | #3, #6, #7 |
| FR-005 | Sanitized diagnostics and recovery documentation | must | #8 |
| FR-006 | Opt-in launch at login | optional | #8 |
| FR-007 | Local tests, safety gate and runnable Release app | must | #9, #10 |

## Inputs, outputs and integrations

IOKit telemetry and user preferences are inputs; menu bar status, local settings and sanitized diagnostics are outputs. SMC is a conditional integration, isolated behind a control abstraction. Missing or stale data is explicit; errors disable unsafe control. No network or account needed.

## Technical preferences and constraints

Swift 5.7-compatible SwiftPM, SwiftUI/AppKit, IOKit, Command Line Tools, macOS 12 deployment target. No full Xcode, Codex or Cursor. Linux-only CI. Native compilation and hardware acceptance locally. Avoid unnecessary dependencies. The application stack profile is project-specific; reusable profiles are not assumed applicable. See decisions and README. Application build, run, test and packaging commands are recorded in README; macOS execution requires local validation.

## Quality, security and privacy

Mockable providers and deterministic policy tests; accurate missing-data handling; no serial numbers in default diagnostics; no arbitrary privileged commands or unsupported SMC writes. Preserve OS safeguards. Explicit owner approval and verified recovery before hardware write tests. Review safety-sensitive changes manually. Do not force discharge or calibrate. Low resource usage; measure locally, do not claim unmeasured performance.

## Risks and assumptions

| Item | Mitigation or verification |
|---|---|
| SMC support unknown | #3 establishes GO/NO-GO, fallback on uncertainty |
| Battery service warning and low reported capacity | Read-only first; no forced discharge or calibration |
| Local SDK 13.1 and Swift 5.7 toolchain | Import smoke test passed; full app build in #4 |
| Crash/sleep/reboot behavior unknown | #9 validates before enabling release control |
| One-day delivery target | Reduce to safe monitoring-only build rather than bypass gates |

## First useful version and later versions

See [scope](../project/scope.md) and [roadmap](../project/roadmap.md). Release gate #9/#10 requires positive evidence; public tag/release requires owner approval.

## Project decision status

| Area | Status | Value / notes | Link / location / return trigger |
|---|---|---|---|
| Product purpose | decided | Battery longevity manager | vision; product spec §1 |
| Users | decided | MacBook owners, desk/mixed/mobile | product spec §3 |
| Outcomes | decided | Reliable telemetry and safe control | FR-001–007 |
| Success criteria | decided | Local app and evidence-backed release gate | #9, #10 |
| First useful version | decided | Monitoring plus conditional verified charge limit | scope |
| Non-goals | decided | No rejuvenation, unsafe discharge or broad compatibility claims | scope; spec §9 |
| Interfaces | decided | Menu bar, preferences, diagnostics | FR-001–005 |
| Inputs and outputs | decided | Local battery telemetry, preferences, export | Inputs section |
| Architecture shape | decided | UI, telemetry, policy, isolated backend and fallback | spec §6; #3 for helper choice |
| Boundaries | decided | OS safeguards retained; no unsupported writes | spec §7 |
| Storage and data ownership | decided | Local settings and explicit diagnostics; user owns data | spec §6 |
| Retention and migrations | deferred | No history database in MVP; migration design not needed for research/scaffold | Revisit before persistent history or incompatible settings schema |
| Integrations and failure handling | decided | IOKit; conditional SMC; fail-safe fallback | #3, #6 |
| Authentication and authorization | deferred | No app accounts; privileged helper choice requires device evidence; does not block read-only research | #3 before any privileged control |
| Secrets, privacy, and sensitive data | decided | Offline; omit identifiers; private workflow not committed | spec §§6–7 |
| Language, framework, and dependencies | decided | Swift 5.7, SwiftPM, SwiftUI/AppKit, IOKit, CLT | D-01 |
| Environments and deployment | decided | Local Monterey build, Linux CI, local Release app | D-01, D-02 |
| Configuration | decided | Local preferences, validated thresholds, opt-in control | #5, #7 |
| Logging, monitoring, and errors | decided | Local visible errors and sanitized diagnostics | #8 |
| Tests, lint, typecheck, performance | decided | Local Swift build/tests, portable Linux checks, measure footprint locally | #4, #9 |
| Scale, reliability, and cost | decided | Single local user, no server, minimal resource use | spec §8 |
| Supported platforms and compatibility | decided | Intel MacBookPro11,5 / Monterey 12.7.6 first | D-01; #3 |
| Accessibility and localization | decided | Native accessible controls and localization-ready strings; translations later | spec §5 |
| Compliance, backup, and recovery | decided | No cloud data; documented safe restore/uninstall; MIT obligations | spec §7; #6, #8 |
| Branching, CI, release, and rollback | decided | Scoped PRs, owner review, Linux CI, recovery gate | D-02, D-05; #9, #10 |
| License, ownership, and documentation expectations | decided | Existing MIT license and copyright retained; accurate docs | ../../LICENSE |

## Project readiness

| Check | Result | Notes |
|---|---|---|
| Definition coverage complete | recorded | 26 areas classified; reviewed against project definition contract |
| No `blocking-question` remains | recorded | Control-specific questions deferred to #3; no control implementation before resolution |
| All `deferred` items have reason and return trigger | recorded | See decision status |
| Template customization complete | pass | Project-owned overlay, README and AGENTS customized; local doctor and leak check passed at c750a03 |
| Stack profile selected or marked N/A | N/A | Project-specific stack guidance above |
| Real project commands recorded | recorded | README; native execution pending local owner validation |
| Root README describes the product | recorded | README |
| `AGENTS.md` describes repository role | recorded | AGENTS.md |
| Bootstrap markers removed | pass | Reviewed tracked project definition files; no bootstrap placeholders remain in changed project documents |
| License and ownership decided | recorded | Existing LICENSE |
| CI, branch rules, and approvals decided | pass | #11 merged; Linux-only CI and owner review/merge rules recorded |
| Project ready for first product task | pass | Bootstrap CI passed, PR #12 merged and #2 closed; hardware control remains gated by #3 |

Product implementation is not authorized by this document alone. Readiness must be confirmed before product work.

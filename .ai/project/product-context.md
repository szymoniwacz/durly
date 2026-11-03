# Product Context

## Product

- **Name:** Durly
- **Purpose:** Native macOS battery longevity manager and a simpler, intelligent alternative to AlDente.
- **Users:** MacBook owners (including older Intel MacBooks), primarily users who want to preserve battery capacity over years.
- **Primary outcome:** Maximize **useful battery lifespan**, not just runtime per charge.
- **Specification:** [docs/product-requirements.md](../../docs/product-requirements.md)

## Repository

- **Main stack (planned):** Swift, SwiftUI, AppKit for older systems, IOKit, model-specific power-control backends.
- **Interface:** lightweight menu bar app.
- **Development status:** requirements and research, not an implemented product.
- **Important boundaries:** model-dependent charge control; verify SMC behavior; smallest privileged helper possible; local-first.

## Constraints

- Native macOS, no Electron/web wrapper.
- Monterey 12.7.6 on MacBookPro11,5 is an explicit validation target.
- Investigate macOS 11 and 10.15, with supported deployment target determined by feasibility.
- Intel support first, Apple Silicon as separate research/implementation track.
- Open-source, free, lightweight and fully usable offline.
- No forced discharge or calibration when battery condition is unsafe.

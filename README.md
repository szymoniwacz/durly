# Durly

**Smart Battery Care for Mac**

Durly is a planned **native, free and open-source macOS menu bar app** focused on **maximizing MacBook battery lifespan** through intelligent charging, monitoring and safe battery care. It is intended to be a simpler, more automated alternative to AlDente—not merely a charge limiter.

- **Native macOS:** Swift, SwiftUI and AppKit where needed for older versions; no Electron.
- **Older Macs first:** initial validation target is **MacBook Pro 15-inch Mid 2015 (MacBookPro11,5) on macOS Monterey 12.7.6**. Big Sur and Catalina compatibility will be investigated rather than assumed.
- **Intel and Apple Silicon:** hardware-specific capability detection; unsupported controls fall back to read-only operation.
- **Battery longevity:** configurable charging limits, smart profiles, cautious holding/discharge controls, thermal protection, diagnostics and capacity history.
- **Safety:** no forced discharge or calibration on a battery reporting faults or unexpected shutdowns.
- **Local-first:** offline core functionality, minimal resource use, no account required.

> **Project status:** Read-only native monitoring works on the validated Intel Monterey target. v0.1.0 focuses on persistent history, analytics and alerts (#19–#23); charging control is deferred. Planned features are not claims of current support.

**[Read the detailed product requirements](docs/product-requirements.md)** · **[Roadmap](.ai/project/roadmap.md)**


## Development

Initial target: Intel macOS 12.7.6. Use Swift 5.7-compatible Command Line Tools locally and SwiftPM in Linux CI, without full Xcode, Codex or Cursor. Linux-only CI checks repository contracts and portable code; native builds and device tests run locally. The read-only menu bar popover shows battery status, health warnings and optional diagnostics. Its display settings are saved locally; charging control is not implemented.

For maintainers with private workflow access:

```bash
./scripts/setup-ai-workflow.sh
./scripts/ai-workflow-doctor.sh
bash tests/test-adapter.sh
./scripts/check-workflow-leak.sh
```

Do not commit reusable private workflow files. See [development setup](docs/setup.md) and [active scope](.ai/project/scope.md).

### Build and run locally (Intel Mac, Monterey 12.7.6 validated)

```bash
# Quit any running Durly instance before rebuilding.
bash scripts/test-local.sh
bash scripts/build-app.sh
open dist/Durly.app
```

The build script targets x86_64 macOS 12.0; other models and OS versions are not yet validated. The app uses an ad-hoc local signature, not notarized distribution. Local scripts use swiftc directly because the target CLT lacks the PackageDescription module and XCTest. Linux runs the portable core tests (`swift test` and `bash scripts/test-local.sh`); it does not compile AppKit or IOKit. No hardware writes, root access or bclm dependency.

## License

MIT; see [LICENSE](LICENSE).

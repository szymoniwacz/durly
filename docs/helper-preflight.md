# Privileged helper preflight — issue #6

Status: candidate architecture only; production remains read-only. Dependencies #3 and #4 closed; native manual SMC reads validated in #17. Owner reported zero valid code signing identities on 2026-11-26.

## Candidate and evidence

- [Apple XPC guidance](https://developer.apple.com/forums/thread/681053): C XPC peer code signing requirement available on macOS 12; NSXPCConnection equivalent requires macOS 13. Use C XPC candidate rather than private audit-token APIs or PID/path authentication.
- [SMJobBless](https://developer.apple.com/documentation/servicemanagement/smjobbless%28_%3A_%3A_%3A%29?language=objc): candidate installation mechanism for Monterey. Deprecated on newer systems; SMAppService is not the Monterey solution. Requires mutually specified signing requirements, embedded helper plists and explicit installation authorization.
- [Apple code signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html): self-signed identities are suitable for internal testing, not public distribution. Exact leaf certificate pin plus distinct code identifier is the proposed local requirement. Common name alone, identifier alone, ad-hoc signing, and caller-supplied identity are not sufficient. Actual acceptance by SMJobBless and XPC on target remains unverified.

## Staged implementation plan

1. Run `bash scripts/check-helper-prerequisites.sh` on the target. It compiles and links an inert C fixture against the local SDK targeting macOS 12; never executes it. Reports only signing identity count. No root or keychain modifications.
2. If compilation succeeds, owner creates a dedicated local code-signing identity via Keychain Access Certificate Assistant (Code Signing, self-signed root), restricted to development. Keep private key local, never export or commit it. No global trust changes or disabling OS protections. If signing or validation requires weakening safeguards, stop.
3. Prepare separate inert client/helper fixture with distinct identifiers (candidate com.durly.app and com.durly.helper), pinned exact leaf certificate requirements in both directions, hardened runtime without debug entitlement, no IOKit/SMC or privileged operations. First prove positive and negative peer authentication in unprivileged test context. Set requirement before activating connections; reject configuration failure; validate messages on both endpoints. Test wrong signer, same CN with different key, wrong identifier, ad-hoc, unsigned, malformed, incompatible version, and disconnect. Do not treat compile/link as runtime proof.
4. Only after human security review and explicit installation approval, test SMJobBless using an inert status-only helper; verify root ownership, launchd configuration, mutual requirements, update and uninstall. No arbitrary commands, no writable executable path, no SMC access. If unavailable, keep read-only.
5. Separately design authenticated authorization, replay prevention, rate limiting, durable root-owned journal, recovery and independent hardware safety gate under the existing feasibility contract. No production write path until all gates and specific physical-test approval are satisfied.

The current increment adds only a read-only compile/link preflight, not a privileged helper, certificate generator, installer or IPC implementation. Existing application packaging and behavior remain unchanged. No signing credentials stored. See [feasibility](intel-charge-control-feasibility.md) and [native read evidence](smc-read-probe.md).

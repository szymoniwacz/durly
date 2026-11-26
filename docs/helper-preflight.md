# Privileged helper preflight — issue #6

Status: candidate architecture only; production remains read-only. Dependencies #3 and #4 closed; native manual SMC reads validated in #17. Owner initially reported zero valid code signing identities on 2026-11-26; local development signing has since been demonstrated.

## Candidate and evidence

- [Apple XPC guidance](https://developer.apple.com/forums/thread/681053): C XPC peer code signing requirement available on macOS 12; NSXPCConnection equivalent requires macOS 13. Use C XPC candidate rather than private audit-token APIs or PID/path authentication.
- [SMJobBless](https://developer.apple.com/documentation/servicemanagement/smjobbless%28_%3A_%3A_%3A%29?language=objc): candidate installation mechanism for Monterey. Deprecated on newer systems; SMAppService is not the Monterey solution. Requires mutually specified signing requirements, embedded helper plists and explicit installation authorization.
- [Apple code signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html): self-signed identities are suitable for internal testing, not public distribution. Exact leaf certificate pin plus distinct code identifier is the proposed local requirement. Common name alone, identifier alone, ad-hoc signing, and caller-supplied identity are not sufficient. Actual acceptance by SMJobBless and XPC on target remains unverified.

## Local evidence — 2026-11-26

- Owner ran the prerequisite script on macOS 12.7.6 / SDK 13.1: XPC peer requirement and SMJobBless compiled and linked for macOS 12. Initially zero valid identities.
- Dedicated self-signed development identity created in login keychain. Initially CSSMERR_TP_NOT_TRUSTED; owner configured trust for Code Signing only, other policies unspecified. No system-wide trust change. One valid identity subsequently reported. This is user-scoped code-signing trust, not proof of root-domain acceptance.
- Owner signed a temporary copy of /usr/bin/true with the development identity, distinct com.durly.signing-probe identifier, --options runtime and --timestamp=none. Strict verification reported valid on disk and satisfies its Designated Requirement; execution succeeded. Temporary copy removed. No original system file modified, no helper installed, no SMC access.
- This validates local signing and execution only. Peer authentication, exact pinned requirement enforcement, root installation and recovery still need independent evidence. Certificate fingerprint, subject personal details and private key are intentionally not recorded.

## Staged implementation plan

1. Run `bash scripts/check-helper-prerequisites.sh` on the target. It compiles and links an inert C fixture against the local SDK targeting macOS 12; never executes it. Reports only signing identity count. No root or keychain modifications.
2. If compilation succeeds, owner creates a dedicated local code-signing identity via Keychain Access Certificate Assistant (Code Signing, self-signed root), restricted to development. Keep private key local, never export or commit it. For this self-signed identity, user-scoped Code Signing trust only was required; do not set trust for unrelated policies or system-wide trust, and do not disable OS protections. If signing or validation requires weakening safeguards, stop.
3. Prepare separate inert client/helper fixture with distinct identifiers (candidate com.durly.app and com.durly.helper), pinned exact leaf certificate requirements in both directions, hardened runtime without debug entitlement, no IOKit/SMC or privileged operations. First prove positive and negative peer authentication in unprivileged test context. Set requirement before activating connections; reject configuration failure; validate messages on both endpoints. Test wrong signer, same CN with different key, wrong identifier, ad-hoc, unsigned, malformed, incompatible version, and disconnect. Do not treat compile/link as runtime proof.
4. Only after human security review and explicit installation approval, test SMJobBless using an inert status-only helper; verify root ownership, launchd configuration, mutual requirements, update and uninstall. No arbitrary commands, no writable executable path, no SMC access. If unavailable, keep read-only.
5. Separately design authenticated authorization, replay prevention, rate limiting, durable root-owned journal, recovery and independent hardware safety gate under the existing feasibility contract. No production write path until all gates and specific physical-test approval are satisfied.

The current increment adds only a read-only compile/link preflight, not a privileged helper, certificate generator, installer or IPC implementation. Existing application packaging and behavior remain unchanged. No signing credentials stored. See [feasibility](intel-charge-control-feasibility.md) and [native read evidence](smc-read-probe.md).

#!/usr/bin/env bash
# Read-only SDK/toolchain probe. No certificate creation, signing, or installation.
set -euo pipefail
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
  echo "Requires Intel macOS." >&2
  exit 1
fi
sdk="$(xcrun --sdk macosx --show-sdk-path)"
echo "macOS: $(sw_vers -productVersion)"
echo "SDK: $(xcrun --sdk macosx --show-sdk-version)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/probe.c" <<'EOF'
#include <xpc/xpc.h>
#include <ServiceManagement/ServiceManagement.h>
#include <Security/Security.h>
int main(void) {
    // Compile/link only. Never execute this binary.
    int (*volatile peer)(xpc_connection_t, const char *) =
        xpc_connection_set_peer_code_signing_requirement;
    Boolean (*volatile bless)(CFStringRef, CFStringRef, AuthorizationRef, CFErrorRef *) =
        SMJobBless;
    return peer == 0 || bless == 0;
}
EOF
xcrun --sdk macosx clang -isysroot "$sdk" -arch x86_64 \
  -mmacosx-version-min=12.0 -Werror=unguarded-availability-new \
  -Wno-deprecated-declarations "$tmp/probe.c" \
  -framework ServiceManagement -framework Security -o "$tmp/probe"
echo "PASS: Monterey XPC peer requirement and SMJobBless compile/link"
# Print only the count, never identity names or hashes.
identities="$(security find-identity -v -p codesigning)"
printf '%s\n' "$identities" | awk '/^[[:space:]]*[0-9]+ valid identities found[[:space:]]*$/ { print; found=1 } END { if (!found) exit 1 }'
echo "No helper installed; no SMC access. Runtime authentication remains unverified."

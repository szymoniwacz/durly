#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build="$PWD/.build/manual-tests"
mkdir -p "$build"
swiftc -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name DurlyCore -emit-module-path "$build/DurlyCore.swiftmodule" \
  Sources/DurlyCore/*.swift -o "$build/DurlyCore.o"
# Generate the standalone entry point from the XCTest method declarations.
# Keep the supported test convention explicit: one BatteryTests class, synchronous
# zero-argument test methods on their own declaration lines.
runner="$build/GeneratedRunner.swift"
methods="$(sed -nE 's/^[[:space:]]*func (test[A-Za-z0-9_]+)\(\)[[:space:]]*\{[[:space:]]*$/\1/p' Tests/DurlyCoreTests/BatteryTests.swift)"
declared="$(grep -Ec 'func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\(' Tests/DurlyCoreTests/*.swift | awk -F: '{sum += $NF} END {print sum+0}')"
count="$(printf '%s\n' "$methods" | grep -c '^test' || true)"
if [[ "$count" -eq 0 || "$count" -ne "$declared" ]]; then
  echo "Unsupported test declaration; update standalone discovery." >&2
  exit 1
fi
{
  printf '%s\n' '@main' 'struct GeneratedRunner {' '  static func main() {' '    let tests = BatteryTests()'
  while IFS= read -r method; do printf '    tests.%s()\n' "$method"; done <<< "$methods"
  printf '    print("PASS: %s Durly core tests")\n' "$count"
  printf '%s\n' '  }' '}'
} > "$runner"
swiftc -D MANUAL_TESTS -parse-as-library -I "$build" \
  Tests/DurlyCoreTests/*.swift "$runner" "$build/DurlyCore.o" -o "$build/tests"
"$build/tests"

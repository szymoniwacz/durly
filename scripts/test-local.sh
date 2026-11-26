#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build="$PWD/.build/manual-tests"
mkdir -p "$build"
swiftc -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name DurlyCore -emit-module-path "$build/DurlyCore.swiftmodule" \
  Sources/DurlyCore/*.swift -o "$build/DurlyCore.o"
swiftc -D MANUAL_TESTS -parse-as-library -I "$build" \
  Tests/DurlyCoreTests/*.swift "$build/DurlyCore.o" -o "$build/tests"
"$build/tests"

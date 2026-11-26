#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
  echo "This local build targets Intel macOS." >&2
  exit 1
fi
build="$PWD/.build/manual"
mkdir -p "$build"
swiftc -target x86_64-apple-macos12.0 -O -parse-as-library \
  -whole-module-optimization -emit-object -emit-module -module-name DurlyCore \
  -emit-module-path "$build/DurlyCore.swiftmodule" \
  Sources/DurlyCore/*.swift -o "$build/DurlyCore.o"
swiftc -target x86_64-apple-macos12.0 -O -I "$build" \
  Sources/Durly/*.swift "$build/DurlyCore.o" \
  -framework IOKit -framework AppKit -o "$build/Durly"
app="$PWD/dist/Durly.app"
mkdir -p "$app/Contents/MacOS"
cp "$build/Durly" "$app/Contents/MacOS/Durly"
cp packaging/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$app"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Durly.app must be built locally on macOS." >&2
  exit 1
fi
swift build -c release --product Durly
bin_path="$(swift build -c release --show-bin-path)"
app="$PWD/dist/Durly.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/Durly" "$app/Contents/MacOS/Durly"
cp packaging/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$app"

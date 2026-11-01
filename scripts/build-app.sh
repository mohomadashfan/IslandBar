#!/usr/bin/env bash
# Builds IslandBar and assembles a runnable, ad-hoc signed IslandBar.app.
#
# Usage: scripts/build-app.sh [debug|release]   (default: debug)
# Output: build/<config>/IslandBar.app
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/toolchain.sh

config="${1:-debug}"
case "$config" in
    debug|release) ;;
    *) echo "usage: $0 [debug|release]" >&2; exit 64 ;;
esac

swift build -c "$config" --product IslandBar
bin_dir="$(swift build -c "$config" --show-bin-path)"

app="build/$config/IslandBar.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/IslandBar" "$app/Contents/MacOS/IslandBar"
cp Support/Info.plist "$app/Contents/Info.plist"
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Support/PrivacyInfo.xcprivacy "$app/Contents/Resources/PrivacyInfo.xcprivacy"

# Ad-hoc signature with the hardened runtime: no Apple Developer account needed, and the same
# runtime protections and entitlements as a distributed build. See docs/BUILDING.md for
# Gatekeeper implications when sharing builds.
codesign --force --sign - --timestamp=none --options runtime \
    --entitlements Support/IslandBar.entitlements "$app"
codesign --verify --strict "$app"

echo "Built $app"

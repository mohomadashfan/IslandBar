#!/usr/bin/env bash
# Builds a release IslandBar.app and a distributable zip.
#
# Usage: scripts/package-release.sh [version]
#   version defaults to the CFBundleShortVersionString in Support/Info.plist.
#   Set UNIVERSAL=1 to build for both arm64 and x86_64.
#   Set SIGN_IDENTITY to a Developer ID to sign for distribution (default: ad-hoc "-").
#
# Output: dist/IslandBar-<version>.zip and its SHA-256 checksum.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/toolchain.sh

version="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)}"
version="${version#v}"
build_number="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
identity="${SIGN_IDENTITY:--}"

arch_flags=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c release --product IslandBar "${arch_flags[@]}"
bin_dir="$(swift build -c release --show-bin-path "${arch_flags[@]}")"

app="dist/IslandBar.app"
rm -rf dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/IslandBar" "$app/Contents/MacOS/IslandBar"
cp Support/Info.plist "$app/Contents/Info.plist"
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Support/PrivacyInfo.xcprivacy "$app/Contents/Resources/PrivacyInfo.xcprivacy"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"

if [[ "$identity" == "-" ]]; then
    codesign --force --sign - --timestamp=none --options runtime \
        --entitlements Support/IslandBar.entitlements "$app"
else
    # Developer ID builds use the hardened runtime, which notarization requires.
    codesign --force --sign "$identity" --options runtime --timestamp \
        --entitlements Support/IslandBar.entitlements "$app"
fi
codesign --verify --strict --verbose=2 "$app"

zip="dist/IslandBar-$version.zip"
ditto -c -k --keepParent "$app" "$zip"
shasum -a 256 "$zip" | tee "$zip.sha256"
echo "Packaged $zip ($(lipo -archs "$app/Contents/MacOS/IslandBar"))"

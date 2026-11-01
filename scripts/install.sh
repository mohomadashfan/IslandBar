#!/usr/bin/env bash
# Installs IslandBar into /Applications so it appears in Finder, Launchpad and Spotlight and can
# be added as a login item.
#
# Usage:
#   scripts/install.sh            build a release copy and install (or update) it
#   scripts/install.sh uninstall  quit IslandBar and remove the installed copy
#
# Falls back to ~/Applications if /Applications is not writable. Your settings and data in
# ~/Library/Application Support/IslandBar are kept in both cases.
set -euo pipefail

cd "$(dirname "$0")/.."

action="${1:-install}"
bundle_id="io.github.islandbar.IslandBar"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

destination_dir="/Applications"
if [[ ! -w "$destination_dir" ]]; then
    destination_dir="$HOME/Applications"
    mkdir -p "$destination_dir"
fi
destination="$destination_dir/IslandBar.app"

quit_running() {
    if pgrep -x IslandBar >/dev/null; then
        echo "Quitting the running IslandBar…"
        pkill -x IslandBar || true
        for _ in $(seq 1 40); do
            pgrep -x IslandBar >/dev/null || return 0
            sleep 0.25
        done
        pkill -9 -x IslandBar || true
    fi
}

case "$action" in
    install)
        scripts/build-app.sh release
        quit_running

        echo "Installing to ${destination}…"
        rm -rf "$destination"
        ditto build/release/IslandBar.app "$destination"
        codesign --verify --strict "$destination"

        # Make Finder, Launchpad and Spotlight aware of the installed copy, and forget the
        # development builds so the app is not listed twice.
        "$lsregister" -f "$destination"
        for development_copy in build/debug/IslandBar.app build/release/IslandBar.app; do
            [[ -d "$development_copy" ]] && "$lsregister" -u "$development_copy" 2>/dev/null || true
        done

        open "$destination"
        echo "Installed $destination ($bundle_id)."
        echo "To start it at login: IslandBar menu › Settings… › General › Launch IslandBar at login."
        ;;
    uninstall)
        quit_running
        if [[ -d "$destination" ]]; then
            "$lsregister" -u "$destination" 2>/dev/null || true
            rm -rf "$destination"
            echo "Removed $destination."
        else
            echo "IslandBar is not installed in $destination_dir."
        fi
        echo "If you had turned on Launch at login, remove IslandBar from System Settings › General › Login Items."
        echo "Your data is still in ~/Library/Application Support/IslandBar (delete it there, or use Erase All IslandBar Data first)."
        ;;
    *)
        echo "usage: $0 [install|uninstall]" >&2
        exit 64
        ;;
esac

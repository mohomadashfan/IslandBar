# Building IslandBar

## Requirements

- macOS 14 or later.
- **Xcode 16 or later.** It provides the Swift 6 compiler, the macOS SDK and XCTest. Building
  with Xcode 26 or later enables the system Liquid Glass material on macOS 26; older SDKs fall
  back to an equivalent blur.

No paid Apple Developer membership is required for anything in this document except notarized
distribution.

### Command Line Tools vs Xcode

The standalone Command Line Tools include Swift but **not XCTest**. The scripts in `scripts/`
handle this: if `xcode-select` points at the Command Line Tools and Xcode is installed, they use
Xcode's toolchain for that command only. To make Xcode the default everywhere:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

## Commands

| Command | Result |
| --- | --- |
| `scripts/build-app.sh` | Debug build, assembled into `build/debug/IslandBar.app` (ad-hoc signed) |
| `scripts/build-app.sh release` | Optimised build in `build/release/IslandBar.app` |
| `scripts/test.sh` | Runs all XCTest suites (pass extra `swift test` flags through, e.g. `--filter Focus`) |
| `swift run IslandBar` | Runs the bare executable; login items and macOS notifications are unavailable without a bundle |
| `scripts/package-release.sh [version]` | Release `.app` and `dist/IslandBar-<version>.zip` (set `UNIVERSAL=1` for arm64 + x86_64) |

## Reviewing the UI without a pointer

Debug builds listen for a local notification that expands the island to a given page, which is
handy for screenshots and design review. Release builds do not include it.

```sh
scripts/debug-island.sh expand media      # any page id: focus, systemMonitor, bluetooth, ...
scripts/debug-island.sh collapse
```

## Visual Studio Code

Install the **Swift** extension (`swiftlang.swift-vscode`), which also installs LLDB DAP. Open
the repository folder; the extension discovers `Package.swift`, provides code completion, and can
build, test and debug the `IslandBar` target.

When debugging from VS Code you run the bare executable, which behaves like `swift run`. To debug
the bundled app instead, build it with `scripts/build-app.sh` and attach to the running
`IslandBar` process.

## Signing and Gatekeeper

Local builds are **ad-hoc signed** (`codesign --sign -`):

- They run on the Mac that built them.
- macOS may ask again for Automation or folder access after each rebuild, because the signature
  changes. See [PERMISSIONS.md](PERMISSIONS.md#signing-and-permission-resets).
- **On another Mac,** an ad-hoc signed app downloaded from the internet is quarantined and
  Gatekeeper refuses to open it. The recipient can allow it under System Settings › Privacy &
  Security › *Open Anyway*. Alternatively, they can remove the quarantine attribute:
  `xattr -dr com.apple.quarantine IslandBar.app`. Only do this for builds you trust.

For frictionless distribution, sign with a Developer ID certificate and notarize. This requires a
paid membership; see [RELEASING.md](RELEASING.md).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `no such module 'XCTest'` | Xcode is not installed or not selected; see above |
| The island does not appear | Check that **Show Island** is ticked in the menu bar menu and that the display is enabled in Settings › Displays |
| Media shows nothing | Music and Spotify work out of the box. For browsers, turn on Settings › Media › Web Browsers and follow the status shown next to each browser |
| Controls do nothing | Grant Automation in Settings › Permissions, or reset with `tccutil reset AppleEvents io.github.islandbar.IslandBar` |
| The shortcut does not work | Another app owns that combination; choose a different one in Settings › General |

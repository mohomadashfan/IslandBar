# Contributing to IslandBar

Thanks for helping. IslandBar values a small, reliable, private app over a long feature list, so
please open an issue to discuss larger changes before writing them.

## Getting started

```sh
git clone <your fork>
cd IslandBar
scripts/test.sh                 # all tests must pass
scripts/build-app.sh && open build/debug/IslandBar.app
```

See [docs/BUILDING.md](docs/BUILDING.md) for toolchain details and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing structure.

## Ground rules

- **Public APIs only.** Do not add private frameworks or undocumented selectors. If a feature
  cannot be built with public APIs, document the limitation instead.
- **Privacy first.**
  - No telemetry, analytics or network calls by default.
  - New permissions must be requested only when the user turns on the feature that needs them.
  - Document every new permission in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).
- **Idle means idle.** No polling while nothing is visible. Prefer notifications, FSEvents and
  observation. Cancel tasks when a module is deactivated.
- **Swift 6 strict concurrency.** The package builds in Swift 6 mode with no warnings; keep it
  that way. Do not reach for `@unchecked Sendable` or `nonisolated(unsafe)` without a comment
  explaining why it is safe.
- **No new dependencies** without discussion.
- **Module boundaries.** Feature modules depend only on `IslandCore` and `IslandDesign`. Put pure
  logic (parsing, maths, state machines) in plain types so it can be unit-tested.

## Adding a feature module

1. Create `Sources/FeatureX/` with a `@MainActor @Observable` class conforming to `IslandModule`.
2. Add its settings struct to `IslandCore/Settings/FeatureSettings.swift`, with defaults for every
   property.
3. Register it in `AppEnvironment` and add a settings pane.
4. Add the target to `Package.swift` and tests to `Tests/FeatureTests`.

## Pull requests

- Keep each pull request focused, and describe what you tested manually. The checklist in
  [docs/TESTING.md](docs/TESTING.md) helps.
- Add or update tests for logic changes.
- Run `scripts/test.sh` and check there are no new compiler warnings.
- Do not commit build output, `.vscode/` settings, signing material or personal data.

By contributing you agree that your contributions are licensed under the MIT License and that you
will follow the [Code of Conduct](CODE_OF_CONDUCT.md).

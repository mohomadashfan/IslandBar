# Architecture

IslandBar is a Swift Package with one executable and a set of libraries. Dependencies only point
downwards; feature modules never depend on each other.

```
                         IslandBarApp  (composition root, menu bar, settings UI)
             ┌──────────────┬──────┴───────┬───────────────────────────┐
       IslandWindows   IslandDesign   Feature modules (Media, FileShelf, Focus,
             │              │          SystemMonitor, Developer, Notifications)
             │              └──────┬───────┘
             └──────────── IslandCore ─────────────┘
```

| Target | Responsibility | Frameworks |
| --- | --- | --- |
| `IslandCore` | Settings model and store, JSON persistence, island state machine, activity center, feature registry. | Foundation, Observation |
| `IslandDesign` | Theme resolution, island shape, surfaces (blur / Liquid Glass), animation engine, shared components, the `IslandModule` UI contract. | SwiftUI, AppKit |
| `IslandPlatform` | Shared platform integrations: typed Core Audio queries and listeners, audio process list, running-app resolution. | CoreAudio, AppKit |
| `IslandAudioDSP` | The real-time mixer and equaliser, in C: no allocation, locks or Swift runtime on the audio thread; parameters published with a sequence lock. | CoreAudio |
| `IslandWindows` | Display detection, notch geometry, positioning, `NSPanel` lifecycle, hover/drag/keyboard handling. | AppKit, SwiftUI |
| `Feature*` | One module per feature, each with its own state, platform adapters and views. | varies |
| `IslandBarApp` | Builds everything, propagates settings, island root view, settings window, global shortcut. | SwiftUI, AppKit, Carbon |

## Key flows

### Settings

`SettingsStore` (`@MainActor @Observable`) is the single source of truth. Every change goes
through `update(_:)`. Writes are coalesced (300 ms) and flushed on quit.

`AppEnvironment` observes the store with `withObservationTracking`. On each change it:

- calls `apply(_:)` on every module;
- enables or disables modules through `FeatureRegistry`;
- reconfigures `IslandManager`.

Settings files are decoded by merging them over the defaults (`JSONMerge`), so adding an option
never invalidates an existing file. A file that cannot be decoded is moved aside to
`settings.json.corrupt-<timestamp>`; it is never silently overwritten.

Only use `JSONMerge` for structs and raw-value enums. Enums with associated values encode as
single-key objects, and merging two different cases produces an object that cannot be decoded.
For that reason the Focus state is decoded without merging.

### Island presentation

```
pointer / drag / click / Escape / shortcut
        │
IslandViewModel (per display: applies hover & collapse delays)
        │  IslandEvent
IslandInteraction.reduce  (pure state machine: compact ↔ expanded(reason))
        │  IslandPresentation
IslandPresenter.contentMode  → idle | liveActivity | banner | expanded
        │
IslandGeometry.islandSize / windowFrame  (pure maths)
        │
IslandWindowController  (resizes the NSPanel: grow first, shrink after the animation)
```

**Why the window resizes.** The panel is only as large as the island currently needs, so a
compact island never blocks clicks on the menu bar. When expanding, the panel grows instantly
and SwiftUI animates the island outward inside it. When collapsing, the panel shrinks only after
the animation has finished.

**Hover.** Hover uses an `NSTrackingArea` with `.activeAlways`, because SwiftUI's hover tracking
does not fire for an app that is never frontmost.

**Clicking outside.** A global mouse-down monitor detects clicks outside the island. Mouse
monitors need no permission.

**Keyboard focus.** The panel is a non-activating `NSPanel`. It becomes key only when expanded
by a click or the shortcut, which is when Escape and text input are useful. This means IslandBar
never steals activation from the app you are using.

### Displays

`DisplayMonitor` turns `NSScreen.screens` into value snapshots (`DisplayDescriptor`), so no
`NSScreen` is retained after a display disconnects.

**Notch.** The notch is derived from the screen's top safe-area inset and the unobscured
auxiliary areas either side of it. No coordinates are hard-coded.

**Refreshing.** Snapshots are refreshed when screen parameters change, on wake and on Space
changes. Each refresh runs twice, the second time 600 ms later, because displays report stale
geometry while waking.

**Display identity.** Each display is identified by its CoreGraphics UUID, so per-display
choices survive reconnecting.

### Modules

A module conforms to `IslandModule` (from `IslandDesign`, which refines `IslandFeature` from
`IslandCore`):

- `activate()` and `deactivate()` are synchronous. A module starts its own `Task`s and
  cancels them on deactivation, so the registry has no reentrancy problems when a module is
  toggled rapidly.
- `liveActivityPriority` claims the compact island. The highest priority wins: Camera & Mic (50),
  Focus (40), Developer (30), Media (20), then the system indicator (10).
- The `make…View()` methods supply the compact and expanded UI.
- A module that accepts dropped files also conforms to `IslandDropTarget`.

Modules post user-visible events to `ActivityCenter`, which queues banners, keeps the history
and forwards events to the Notifications module.

## Concurrency

The code builds in the Swift 6 language mode with complete checking.

**Main actor.** UI state, models and modules are `@MainActor`.

**Off the main thread:**

- System sampling runs in an actor (`SystemSampler`).
- `git` runs on a background queue.
- Automation permission checks run in detached tasks, because they can block on a consent
  dialog.

**Callbacks.** These are scheduled on the main queue and use `MainActor.assumeIsolated`:

- FSEvents
- dispatch sources
- distributed notifications
- the Carbon hot-key handler

**Timing.** Nothing relies on timer callbacks arriving on time:

- The Focus timer is computed from wall-clock timestamps and re-checked on wake.
- Media progress is extrapolated from the last known position.

## Performance

When nothing is happening, IslandBar does no periodic work. It is driven by events: pointer
tracking, notifications, file-system events and display changes.

Measured idle cost on Apple Silicon:

- 0.0% CPU
- 0 idle wake-ups
- about 20 MB of memory

Some work happens only while needed:

- **System metrics:** sampled only while their page is visible, or while you have chosen a
  compact indicator.
- **Countdowns and progress bars:** they use `TimelineView` at 1 Hz, and only while running.
- **Git status:** rate-limited to once per 3 seconds per repository.

## Persistence

All data lives in `~/Library/Application Support/IslandBar/`:

| File | Contents |
| --- | --- |
| `settings.json` | All settings |
| `focus.json` | Timer state and quick notes |
| `shelf.json` | Shelf entries (bookmark data, names, dates) |
| `events/` | Inbox for local developer events (mode 0700) |

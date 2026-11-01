# Testing

## Automated

```sh
scripts/test.sh
```

| Suite | Covers |
| --- | --- |
| `IslandCoreTests` | Settings defaults and tolerant decoding, persistence and corruption handling, debounced saving, island state machine, activity queue, feature registration and lifecycle, theme configuration |
| `IslandWindowsTests` | Notch detection (global and screen-local coordinates), menu bar height, anchors, window frames and clamping, island sizes, per-display selection |
| `FeatureTests` | Focus timer maths, sleep and restart catch-up, persistence; shelf expiry, de-duplication, moved and missing files; media parsing; metric maths and live sampling; developer event validation, activity log, git parsing, real `git` status, inbox processing |

## Manual checklist

Run through this before a release. Note the macOS version and hardware.

### Displays
- [ ] **MacBook built-in display:** the compact island exactly covers the notch, at default and at "More Space" scaling.
- [ ] **External display:** a virtual island appears top-centre; attached and floating styles both work; the horizontal offset moves it.
- [ ] **Two or more external displays:** each has its own island; per-display toggles persist after unplugging and replugging.
- [ ] **Change the resolution or arrangement in System Settings:** the island repositions without restarting.
- [ ] **Disconnect the display that has an expanded island:** no crash, and the remaining islands are unaffected.
- [ ] **Sleep and wake:** the island is in the right place after wake, and a running Focus timer shows the correct remaining time.

### Interaction
- [ ] Hover expands after the delay and leaving collapses it; clicking keeps it open.
- [ ] Escape closes an island opened by a click; typing in Focus notes works; afterwards the previous app still receives keystrokes.
- [ ] Clicking another app collapses the island (when enabled).
- [ ] ⌃⌥Space toggles the island on the display under the pointer.
- [ ] The menu bar items next to the notch remain clickable while the island is compact.

### Spaces and full screen
- [ ] The island appears on every Space.
- [ ] Over a full-screen app it is hidden by default, and shown when *Show over full-screen apps* is on.

### Features
- [ ] **Music and Spotify:** the track appears, artwork loads after granting Automation, and play/pause/next/previous work. With Automation denied, metadata still appears.
- [ ] **Browsers:**
  - Turn on browser media and allow Automation for Chrome.
  - With JavaScript from Apple Events off, the island shows the setup hint.
  - After turning it on, a YouTube video shows its title and channel, the progress moves, and play/pause and next work.
  - Muted hover previews on the YouTube home page are not shown.
  - Repeat in Safari.
  - With nothing playing, CPU stays low while the browser is open.
- [ ] **File Shelf:** dragging files onto the compact island expands it to the shelf; thumbnails appear; dragging a file back out to Finder works; the shelf survives a restart; expiry removes items.
- [ ] **Focus:** start it, quit IslandBar, wait, relaunch — the time is correct. A completion banner appears.
- [ ] **System:** values roughly match Activity Monitor; CPU is near zero when the page is closed and no indicator is set.
- [ ] **Developer:** an added repository shows its branch and changes, and updates after editing a file; `scripts/islandbar-event` shows a live activity and then a banner.
- [ ] **Camera & Mic:**
  - Join a call (FaceTime, Zoom or a browser meeting). The compact island shows the camera and microphone lights, and the microphone app's name.
  - A banner appears when each turns on.
  - The lights clear when the call ends.
  - "Hey Siri" alone does not trigger the microphone light.
- [ ] **Mirror:**
  - The first "Turn On Camera" shows the macOS camera prompt, and the preview appears.
  - Flip and switch-camera work.
  - Collapsing the island turns the camera light off.
  - With two displays, only one island shows the preview.
  - With access denied, the page explains how to re-enable it.
- [ ] **Sound:**
  - Turn it on and accept the System Audio Recording prompt.
  - Lower Spotify or Chrome to 30%; only that app gets quieter.
  - 0% and mute silence it; 150% is louder without distortion.
  - Pick Bass Boost and hear the difference.
  - Change output device (for example to AirPods); adjustments carry over.
  - Turn Sound off or quit IslandBar; every app returns to normal immediately.
  - Deny the permission; no app is left silent and the page explains how to allow it.
- [ ] **Bluetooth:**
  - Connect and disconnect headphones and a mouse; banners appear.
  - An Apple keyboard, mouse or trackpad shows its battery.
  - No banners flood in at launch or after wake.
- [ ] **Keep Awake:**
  - The cup in the header toggles it; holding it shows durations.
  - `pmset -g assertions` lists "IslandBar Keep Awake" while it is on.
  - A timed session ends with a banner.
- [ ] **Notifications:** with *Also send to Notification Center* on, the permission prompt appears and events are mirrored.

### Settings and appearance
- [ ] Every theme renders. Liquid Glass uses the system material on macOS 26 and later.
- [ ] Custom theme edits apply live; size sliders resize the island.
- [ ] With Reduce Motion on, transitions become cross-fades.
- [ ] Restore Defaults resets every section; settings persist across restarts.

### Privacy
- [ ] **Fresh install, first launch:** no permission prompts at all.
- [ ] **Shelf:** with a file from Downloads on the shelf, relaunching IslandBar shows no folder prompt until the shelf page is opened.
- [ ] **Screen capture:** with *Hide the island from screenshots* on, `screencapture` and screen sharing do not show the expanded island.
- [ ] **Data folder:** `stat` shows the data folder as `drwx------` and its files as `-rw-------`.
- [ ] **Erase:** *Erase All IslandBar Data* removes the folder and quits; the next launch starts fresh.
- [ ] **Network:** with no opt-in features on, Little Snitch or `nettop` shows no connections from IslandBar.

### Performance
- [ ] After a minute idle, Activity Monitor shows about 0% CPU and few idle wake-ups for IslandBar.

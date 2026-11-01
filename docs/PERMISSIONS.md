# Permissions and Privacy

IslandBar asks for as little as possible, and only when you use the feature that needs it.

## Summary

| Permission | When it is requested | Why | Without it |
| --- | --- | --- | --- |
| **Automation → Music / Spotify** | First time you use media controls, or click **Allow access** | Play/pause/skip; read playback position and Music artwork | Track title, artist and album still appear; no controls or artwork |
| **Automation → Chrome / Safari / Edge / Brave** | Only if you turn on *Show media playing in web browsers*, when you click **Allow Access** | List tab addresses and read media state in media-site tabs | Browser playback is not shown |
| **Camera** | Only when you tap *Turn On Camera* on the Mirror page | Live mirror preview (never recorded, never sent anywhere) | Mirror is unavailable; everything else works |
| **System Audio Recording** | Only when you turn on per-app volume in Settings › Sound | Route apps' audio through IslandBar's mixer to change volume and apply the equaliser (never recorded or saved) | Sound is unavailable; audio plays normally |
| **Notifications** | Only if you enable *Also send to Notification Center* | Mirror IslandBar's own activity | Banners in the island still work |
| **Login Items** | When you enable *Launch at login* | Start at login | Start IslandBar manually |
| **Files & Folders** (Desktop/Documents/Downloads) | Possibly once, when a shelf item from those folders is reopened after a restart | macOS protects these folders | That item shows as unavailable |

IslandBar never requests any of the following:

- Accessibility
- Input Monitoring
- Screen Recording
- Full Disk Access
- Location
- Microphone
- Contacts

The global shortcut uses `RegisterEventHotKey`, and click-outside detection uses a mouse-only
event monitor. Neither needs Accessibility.

## Media

macOS has no public API that exposes system-wide "Now Playing" metadata. Apps that show
everything use the private MediaRemote framework. Apple restricts it, and since macOS 15.4 it is
off-limits to third-party apps without workarounds. IslandBar does not use private APIs.

Instead, IslandBar supports specific players:

- **Metadata:** Music and Spotify broadcast track changes as distributed notifications
  (`com.apple.Music.playerInfo` and `com.spotify.client.PlaybackStateChanged`). These need no
  permission.
- **Controls and artwork:** these use each player's AppleScript dictionary, after you grant
  Automation permission.
- **Spotify artwork:** it is only available as a URL. Downloading it, from `*.scdn.co` over HTTPS,
  is **off by default**.

### Web browsers (opt-in)

With **Settings › Media › Show media playing in web browsers** on, IslandBar reads playback in
Chrome, Safari, Edge and Brave. This covers YouTube, YouTube Music, SoundCloud, Spotify Web and
similar sites. Each browser needs two things, once:

1. **Automation permission.** macOS asks when you click *Allow Access*.
2. **The browser's "Allow JavaScript from Apple Events" setting.**
   - Chrome, Edge, Brave: *View › Developer › Allow JavaScript from Apple Events*.
   - Safari: *Settings › Advanced › Show features for web developers*, then *Develop › Allow
     JavaScript from Apple Events*.

What happens while a browser is running:

- **Finding tabs:** one Apple Event lists the addresses of the open tabs.
- **Which tabs are probed:** only tabs on the site list (editable in Settings) receive a short
  script. It reports whether a non-muted `<video>` or `<audio>` element is playing, along with
  its title, artist, position and duration, and the page's Media Session artwork address.
- **What is never read:** page content, form fields, cookies and storage.
- **Controls:** play/pause, next and previous run equally small scripts in that tab.
- **Timing:** polling happens every 2 s while something plays, otherwise every 4 s, and stops
  when the browser quits.

**Trade-off to be aware of:** the browser setting is not specific to IslandBar. It allows *any*
app you have granted Automation access to that browser to run JavaScript in your pages. Turn it
on only if you are comfortable with that. You can see the list of such apps in System Settings ›
Privacy & Security › Automation.

Firefox (no AppleScript support), Arc and other players are not supported.

## Camera and microphone

**The indicator needs no permission.** The camera and microphone indicator never captures audio
or video. It listens for device-state changes that macOS publishes to every app:

- **Microphone:** CoreAudio reports which client processes are capturing input. On macOS 14.2 and
  later this is per process, so IslandBar can name the app. On 14.0 and 14.1 it can only tell that
  an input device is running.
- **Camera:** CoreMediaIO reports whether each camera is running. macOS does not reveal which app
  is using a camera.
- **Ignored:** always-on system listeners such as "Hey Siri" detection and Sound Recognition are
  ignored, consistent with macOS's own indicator.

**Mirror is the only feature that uses the camera.**

- **Permission:** it asks for camera permission the first time you tap *Turn On Camera*.
- **When it runs:** only while the Mirror page is on screen. It stops when you switch pages or
  the island closes.
- **Automatic start:** starting the camera automatically when the page opens is an opt-in setting.
- **Privacy:** frames are shown live and are never recorded, stored or sent anywhere.

## Sound (per-app volume and equaliser)

Off by default. When you change an app's volume or turn on the equaliser:

- **Capture:** IslandBar creates a *private* Core Audio process tap for that app, with "muted when
  tapped". The app's own output is then silenced while IslandBar plays an adjusted copy.
- **Playback:** the copy goes to your current output device through a private aggregate device.
- **Untouched apps:** apps you have not changed keep playing directly.
- **Never recorded:** processing is live and in memory only.
- **Safe failure:** private taps and aggregate devices vanish if IslandBar quits or crashes, so
  normal audio is restored automatically. If macOS refuses the permission, IslandBar removes its
  taps rather than leaving any app silent.
- **No feedback loop:** with the equaliser on, IslandBar uses one global tap for "everything
  else". It builds that tap only when it can exclude its own process, so its output never loops
  back into itself.

## Bluetooth devices

No Bluetooth permission is used:

- **Input devices:** keyboards, mice, trackpads and game controllers are read from the IORegistry.
- **Audio devices:** headphones and speakers are read from Core Audio's device list.
- **Battery levels:** shown where devices publish them (Apple peripherals do). macOS does not
  share AirPods battery levels with other apps.

## Files

**Bookmarks, not copies.** The File Shelf stores bookmark data for each file. It never stores the
file or copies it. Bookmarks keep working if you move or rename a file.

**No sandbox, so no security scope.** IslandBar does not run in the App Sandbox (see below), so
it uses ordinary bookmarks. Security-scoped bookmarks would only be needed inside the sandbox.

**Safe removal.** Removing an item from the shelf, or letting it expire, never deletes the file.

## Developer activity

**Repositories.** IslandBar reads only the repositories you add in Settings. It runs read-only
git commands with `GIT_OPTIONAL_LOCKS=0`, so it never takes the index lock.

**Local events.** This is off by default. Events from your tools arrive only through files that
your own tools write into `~/Library/Application Support/IslandBar/events/`. IslandBar creates that
folder, with mode 0700, only while the setting is on.

**Untrusted input.** IslandBar treats event files as untrusted:

- Files are limited to 16 KB.
- At most 100 events are read per batch.
- Text is cut to a single line of 200 characters at most.
- Files are deleted after reading.
- Event content is only ever displayed as text.

## Stored data

All data lives in one folder: the folder is mode 0700 and its files are mode 0600. *Erase All
IslandBar Data* (Settings › Privacy & Permissions) deletes it and quits. The File Shelf does not
touch any file until you open the shelf, so it never causes a folder-access prompt at launch.

## Screen capture

By default the island panel uses `NSWindow.sharingType = .none`. This asks macOS to omit it from
screenshots, screen recordings and screen sharing. It is verified with `screencapture`; other
capture tools may not honour it. You can turn this off in Settings › General.

## Code signing

Every build, local ones included, is signed with the hardened runtime and exactly these
entitlements: Apple Events, camera, and audio input (needed by Core Audio process taps; it grants
nothing by itself). The bundle includes a privacy manifest (`PrivacyInfo.xcprivacy`) declaring
no tracking, no collected data, and the reason for each required-reason API used.

## Network

IslandBar makes no network requests, with one exception: artwork downloads for Spotify and web
players, if you enable them. These go over HTTPS, and only to known media image servers such as
`i.scdn.co` and `i.ytimg.com`. There is no telemetry, no analytics, no update check and no account.

## Why no App Sandbox

IslandBar is not sandboxed for these reasons:

- Developer Activity watches arbitrary repositories that you choose, and runs `/usr/bin/git`.
- Inside the sandbox, the event inbox could not be written to by your command-line tools.

These features are all opt-in and scoped to what you configure. A sandboxed build could be
offered later with reduced Developer features.

## Signing and permission resets

macOS remembers Automation and folder permissions per code signature. Local builds are ad-hoc
signed, and each rebuild produces a new signature, so **macOS may ask again after you rebuild**.
This does not happen with a stably signed (Developer ID) release.

To reset the Automation decision for testing:

```sh
tccutil reset AppleEvents io.github.islandbar.IslandBar
```

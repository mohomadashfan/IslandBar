# IslandBar Privacy Statement

IslandBar is built to respect your privacy and your Mac's security rules. In short: **IslandBar
collects nothing, sends nothing, and only touches what you turn on.**

## What we never do

- No accounts, telemetry, analytics, advertising or tracking. There are no servers to send data to.
- No private macOS APIs and no workarounds that sidestep macOS permissions.
- We never read other apps' notifications, messages, keystrokes or screen contents.
- We never record audio or video.
- We never ask for permissions up front. Each one is requested only when you use the feature that
  needs it, and you can say no without breaking the rest of the app.

## What stays on your Mac

Everything IslandBar stores lives in one folder that only your user account can read:
`~/Library/Application Support/IslandBar/`

| File | Contents |
| --- | --- |
| `settings.json` | Your preferences, including Git repository paths and app volumes you set |
| `focus.json` | Focus timer state and quick notes |
| `shelf.json` | References (bookmarks) to files you placed on the shelf; never the files themselves |
| `events/` | Only if you turn on developer events: short status messages from your own tools, deleted once read |

Recent activity (banners and history) is kept in memory only and disappears when IslandBar quits.

**Erase everything:** Settings › Privacy & Permissions › *Erase All IslandBar Data*. This deletes the
folder above, turns off launch at login, and quits IslandBar.

## Network

IslandBar makes no network requests by default. The only exception is one setting you control:
*Download artwork from the web* (Settings › Media). With it on, album artwork is fetched over HTTPS,
and only from the image servers of supported music services, such as `i.scdn.co` and `i.ytimg.com`.

## Permissions, and when they are asked for

| Permission | Asked when | Used for |
| --- | --- | --- |
| Automation (Music, Spotify) | You first use play/pause/skip | Controls, playback position, Music artwork |
| Automation (browsers) | You turn on browser media and click *Allow Access* | Reading what media-site tabs are playing |
| Camera | You tap *Turn On Camera* in Mirror | The live preview. Never recorded. |
| System Audio Recording | You turn on per-app volume | Changing app volumes and applying the equaliser, live. Never recorded. |
| Notifications | You turn on *Also send to Notification Center* | Mirroring IslandBar's own events |
| Login Items | You turn on *Launch at login* | Starting at login |

IslandBar never requests Accessibility, Input Monitoring, Screen Recording, Full Disk Access,
Location, Microphone, Contacts, Calendars, Photos or Bluetooth.

Features that work **without any permission**:

- the camera and microphone in-use indicator;
- Bluetooth device alerts;
- System Monitor;
- Keep Awake;
- the File Shelf, for files you drop on it.

Each of them reads only state that macOS makes available to every app.

## Screen sharing

By default, IslandBar asks macOS to leave the island out of screenshots, screen recordings and
screen sharing, so your notes, notifications and track titles are not shown to an audience. You
can change this in Settings › General. Some capture tools may not honour the request.

## Browser media

Off by default. If you turn it on:

- **Which tabs:** IslandBar only looks at tabs on sites in your list (editable in Settings).
- **What it reads:** whether audio or video is playing, its title and artist, position and
  duration. It never reads page content, form fields, cookies or storage.
- **Trade-off:** it requires the browser's "Allow JavaScript from Apple Events" setting. That
  setting lets *any* app you have allowed to control the browser run scripts in your pages, so
  consider that before turning it on.

## Revoking access

Permissions belong to macOS. Revoke them any time in System Settings › Privacy & Security, or reset
all of IslandBar's at once:

```sh
tccutil reset All io.github.islandbar.IslandBar
```

## Reporting a problem

If you believe IslandBar handles data in a way this statement does not describe, please report it
privately as described in [SECURITY.md](SECURITY.md).

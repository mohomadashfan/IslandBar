# Developer Integrations

IslandBar never watches other applications on its own. Tools report activity by **writing small
JSON files** into IslandBar's events folder. This is explicit, local and easy to audit.

```
~/Library/Application Support/IslandBar/events/
```

This is **off by default**. While it is on, any program running under your account can put text on
the island, so turn it on only if you use it: **Settings › Developer › Accept events from local
tools**. The folder exists only while this is on. If the folder is missing, the helper below
quietly does nothing.

## Event format

```json
{
  "source": "vscode",
  "kind": "build",
  "state": "running",
  "title": "swift build",
  "detail": "Compiling 42 files",
  "progress": 0.4,
  "session": "build-1",
  "timestamp": "2026-11-01T10:00:00Z"
}
```

| Field | Required | Values |
| --- | --- | --- |
| `source` | yes | Free text, e.g. `vscode`, `claude-code`, `make` |
| `title` | yes | Free text, shown in the island |
| `kind` | no | `build`, `test`, `agent`, `task`, `deploy`, `custom` (default) |
| `state` | no | `started`, `running`, `waiting`, `succeeded`, `failed`, `cancelled`, `info` (default) |
| `detail` | no | Free text |
| `progress` | no | `0.0`–`1.0` |
| `session` | no | Groups updates into one activity; defaults to `kind` |
| `timestamp` | no | ISO 8601; defaults to the time IslandBar reads the file |

**Grouping.** Events with the same `source` and `session` update one activity.

**Banners.** A transition into `succeeded`, `failed` or `cancelled` shows a banner. You can turn
these banners off in Settings › Notifications.

**Stale activities.** A running activity that receives no update for 30 minutes (configurable)
is marked as cancelled.

**Limits.** Files over 16 KB, files that are not valid JSON, and events without `source` or
`title` are discarded. Write files atomically: write to a temporary name in the same folder,
then rename it to `*.json`.

## The helper script

`scripts/islandbar-event` writes valid events for you:

```sh
scripts/islandbar-event --source make --kind build --state running --title "make all" --session make
scripts/islandbar-event --source make --kind build --state succeeded --title "make all" --session make
```

Copy it onto your `PATH` (for example `~/bin/islandbar-event`) to use it from anywhere.

## Recipes

### Wrap any command

```sh
run() {
  local id="run-$$"
  islandbar-event --source shell --kind task --state running --title "$*" --session "$id"
  if "$@"; then
    islandbar-event --source shell --kind task --state succeeded --title "$*" --session "$id"
  else
    local code=$?
    islandbar-event --source shell --kind task --state failed --title "$*" --session "$id"
    return $code
  fi
}
run swift test
```

### VS Code task

```jsonc
// .vscode/tasks.json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build (IslandBar)",
      "type": "shell",
      "command": "islandbar-event --source vscode --kind build --state running --title 'swift build' --session vscode-build && swift build && islandbar-event --source vscode --kind build --state succeeded --title 'swift build' --session vscode-build || (islandbar-event --source vscode --kind build --state failed --title 'swift build' --session vscode-build; exit 1)",
      "group": "build"
    }
  ]
}
```

### Claude Code hooks

In `~/.claude/settings.json` (or a project's `.claude/settings.json`):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "islandbar-event --source claude-code --kind agent --state running --title 'Claude is working' --session claude" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "islandbar-event --source claude-code --kind agent --state succeeded --title 'Claude finished' --session claude" }] }
    ],
    "Notification": [
      { "hooks": [{ "type": "command", "command": "islandbar-event --source claude-code --kind agent --state waiting --title 'Claude needs input' --session claude" }] }
    ]
  }
}
```

### Git repositories

Add repositories in **Settings › Developer**. IslandBar watches each one with FSEvents and shows:

- the branch
- staged, modified, untracked and conflicted counts
- commits ahead of and behind the upstream
- the last commit

It runs `git status` at most once every 3 seconds per repository. It never fetches, pulls or
writes.

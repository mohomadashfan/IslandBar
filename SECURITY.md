# Security Policy

## Supported versions

Security fixes are made for the latest release only.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's private
vulnerability reporting instead: open the repository's **Security** tab and choose **Report a
vulnerability**.

Include:

- the IslandBar version and macOS version;
- steps to reproduce, or a proof of concept;
- the impact you believe it has.

You should receive an acknowledgement within 7 days. We will keep you informed while a fix is
prepared, and will credit you in the release notes unless you prefer otherwise.

## Scope

Areas of particular interest:

- **The developer events folder.** Event files are untrusted input. Report anything that leads
  to more than displaying text.
- **Git integration.** It must only run read-only commands on repositories the user added.
- **AppleScript and browser scripts.** IslandBar should only run its own fixed scripts: against
  Music and Spotify, and (when opted in) read-only media probes in browser tabs on the user's site
  list.
- **Unexpected network access.** IslandBar should make none, except opt-in artwork downloads from
  known media image servers.
- **Persisted data.** Bookmarks and notes should never leave the Mac, and the data folder must stay
  owner-only (0700, with 0600 files).
- **Permissions.** IslandBar should never cause a permission prompt the user did not start.

Out of scope:

- Gatekeeper warnings on unsigned or ad-hoc signed builds. These are expected; see
  [docs/BUILDING.md](docs/BUILDING.md).

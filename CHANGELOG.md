# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.0.2] - 2026-10-01

- Zombies: "Quit <parent>" is never offered for system processes (loginwindow, WindowServer, Dock, Finder and friends) or Mac Daddy himself, asks before quitting, re-checks the process is still the same one, and shows a ⚠ line if macOS refuses
- The process count no longer needs to start `ps`, so it keeps working (and Mac Daddy keeps sweating) when the process table is full; it now counts exactly what `ps -u $USER` and the per-user limit count
- Downloads counts a file's age from the later of when it was modified and when it arrived in Downloads, so freshly unzipped or copied old files are no longer trashed straight away
- Godot Reaper only looks at your own processes
- The installer no longer aborts if you press Ctrl-D at the Start at Login question
- README and design notes describe the Zombies action as it really works

## [1.0.1] - 2026-10-01

- The installer no longer stops halfway if the old godot-headless-reaper script can't be moved to the Trash; it tells you to delete it by hand
- The installer leaves a real (non-link) copy of an old app alone with a warning, and warns when an old app's login item can't be turned off
- README: Downloads sweep timing explained (checked every 30 minutes, swept at most once a day), and the uninstall steps now turn Start at Login off first

## [1.0.0] - 2026-10-01

- First release. One menu-bar app in place of Media Tracking Killer, Download Recycler and Process Monitor, plus the godot-headless-reaper agent
- Mac Daddy's suit and sweat follow your process count; he tips his hat or flashes his chain after a sweep and sleeps when every cleanup is paused
- Settings carry over from Media Tracking Killer and Download Recycler on first launch

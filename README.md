# Mac Daddy

<p align="center"><img src="docs/mascot.png" width="160" alt="Mac Daddy mascot, from the Menubarn widget library"></p>

<p align="center">Part of the <a href="https://widgets.nicksmith.software">Menubarn</a> widget library.</p>

Keeps your Mac in line: kills Apple's media trackers, trashes stale downloads, finds orphaned processes burning CPU, and sweats when your process count climbs. Built on
[StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit).

**Version 1.1.2** · [Changelog](https://github.com/nicholaspsmith/mac-daddy-menubar/releases)

![The menu-bar icon](docs/menubar-icon.png)

Mac Daddy is the dapper mascot you see above, and he is also the app icon. His mood is your process count:

- **Cool, in a purple suit** — plenty of headroom
- **Sweating, in an amber suit** — the process count is climbing toward the per-user limit
- **Red-hot, in a red suit** — close to the limit: popped collar, two drops of sweat
- **Hat tip** — for two seconds after the media-tracker killer or Lost Souls ends something
- **Chain glint** — for two seconds after the Downloads sweep trashes files
- **Asleep, grey, with a "z"** — every cleanup is paused

Prefer a plain symbol? **menu ▸ Icon ▸ Plain symbol**.

## Menu

| Item | Purpose |
|---|---|
| Processes | live count against the per-UID limit, a two-minute sparkline, crash-looping processes, Top Spawners (each opens a detail window), Zombies (when one of your own, non-system processes is holding zombies: "Quit <parent> to reap N", which asks before quitting it), Open Activity Monitor |
| Media Tracking ▸ Enabled / Kill Now / Interval / Processes | kills Apple's media analysis daemons every 5 / 15 / 30 / 60 s; one toggle per daemon |
| Downloads ▸ Enabled / Sweep Now / Keep Files For / Open Log | checks every 30 minutes and sweeps at most once a day (once 24 h have passed since the last sweep), moving files older than 7 / 14 / 30 / 60 / 90 days from `~/Downloads` to the Trash (restorable, never a hard delete); Sweep Now runs one immediately |
| Lost Souls ▸ Enabled / each soul ▸ End, Spare / Banish Automatically | samples your processes every 30 s; a *lost soul* is one of yours that launchd adopted (parent PID 1) and that averaged over 50% CPU for 10 minutes — a hung headless test run, a script whose terminal closed. Apps, launchd jobs, XPC services and app extensions (Safari tabs, virtual machines), macOS's own programs, helpers a background service or their own app is responsible for, normally orphaned daemons (cfprefsd, mds, tmux, ollama, …) and souls you Spare are left out. Time asleep doesn't count. Mac Daddy notifies you once and lists it as `name [pid] — X% for M min` (the 8 hungriest, then "and N more…"; "None wandering" when there are none); **End** checks it is still the same process, sends SIGTERM, then SIGKILL after 5 s. Nothing is ended unless you click End or turn on **Banish Automatically** (off by default), which ends a soul once it has qualified continuously for 30 minutes |
| Icon | Mac Daddy or plain symbol |
| Start at Login | SMAppService — no launchd agent |

A failing duty shows a warning with the reason directly under its heading. Settings persist in `defaults` domain `com.nicholaspsmith.MacDaddy`, and are carried over from Media Tracking Killer and Download Recycler on first launch.

## What it replaced

`install.sh` retires each of these for you:

| Replaced | What `install.sh` does |
|---|---|
| Media Tracking Killer | quits it, turns its login item off, removes its `~/Applications` link |
| Download Recycler | quits it, turns its login item off, removes its `~/Applications` link |
| Process Monitor | quits it, turns its login item off, removes its `~/Applications` link |
| godot-headless-reaper (launchd agent) | boots it out, removes its plist, moves its script to the Trash (Lost Souls does its job, for any program) |

## Requirements

- macOS 13+ (SMAppService), Swift 5.9 / Xcode Command Line Tools
- [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) checked out
  as a **sibling** directory (local SPM path dependency)
- First run prompts for **Downloads folder access** (TCC) — allow it

## Install

```sh
cd ~/Code
git clone https://github.com/nicholaspsmith/StatusItemKit.git
git clone https://github.com/nicholaspsmith/mac-daddy-menubar.git
cd mac-daddy-menubar
./install.sh
```

`install.sh` builds the app, symlinks it into `~/Applications`, retires the apps and agent above, offers Start at Login (only when run in a terminal), and launches it.

### Start at Login

Toggle it from the menu, or from the shell:

```sh
"$HOME/Applications/Mac Daddy.app/Contents/MacOS/MacDaddy" --login on       # or: off, status
```

Start at Login is `SMAppService.mainApp`, which can only register the calling
process's own bundle, so the command has to be the *installed* binary. A bare
`--login`, or `--login status`, only reports the current state.

## Uninstall

```sh
"$HOME/Applications/Mac Daddy.app/Contents/MacOS/MacDaddy" --login off
osascript -e 'quit app "Mac Daddy"'
rm "$HOME/Applications/Mac Daddy.app"
defaults delete com.nicholaspsmith.MacDaddy
```

(Turning Start at Login off first matters: do it before removing the link. Otherwise remove the entry under
System Settings ▸ General ▸ Login Items.)

## Why not a SwiftBar plugin?

This is a standalone `.app` built on [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit), not a script under a plugin host: no SwiftBar to install, a real AppKit menu instead of rendered stdout, event-driven updates instead of a re-run timer, and an icon that keeps its place in the bar. It replaced three apps and a launchd agent; now the schedules, the Trash-only sweep and Start at Login are one app with no host. The full comparison is in [StatusItemKit's README](https://github.com/nicholaspsmith/StatusItemKit#why-not-swiftbar).

## The menu-bar suite

Part of a suite of macOS menu-bar apps that share one framework, one
build-and-sign script, and one installer. They are designed to sit in the
same bar together: consistent menus, a common **Icon** picker for shape and
colour, and cooperative hiding so no icon strands another.

| App | What it does |
|---|---|
| [Claude Usage](https://github.com/nicholaspsmith/claude-usage-menubar) | Claude Code plan limits, resets, and live agent sessions |
| [Apollo Monitor](https://github.com/nicholaspsmith/apollo-monitor-menubar) | Apollo audio-interface monitor level, plus a mixer-process watchdog |
| [Battery Time](https://github.com/nicholaspsmith/battery-time-menubar) | Time remaining, power mode, and 24h usage |
| [VPN & DNS](https://github.com/nicholaspsmith/vpn-dns-menubar) | A chameleon for Mullvad + Tailscale state, with a DNS watcher |
| **Mac Daddy** | Process-count watch, media-tracker killer, Downloads sweeper and lost-soul finder, in one app |
| [KeyLight](https://github.com/nicholaspsmith/keylight-menubar) | Ctrl+brightness keys remapped to keyboard backlight |
| [MacRecorder](https://github.com/nicholaspsmith/MacRecorder) | Screen recording with system audio |
| [Barn](https://github.com/nicholaspsmith/menubar-barn) | Sunset: macOS 26 and earlier only. Hid a block of status icons by width; on macOS 27 use System Settings ▸ Menu Bar |

| Framework | |
|---|---|
| [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) | Status-item lifecycle, polling, menus, meter icons, the shared Icon picker |
| [HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit) | CGEventTap engine for intercepting and remapping global keys |

Install the whole suite on a fresh Mac with
[macOS Dev Environment Setup](https://github.com/nicholaspsmith/MacOS-Dev-Environment-Setup):

```bash
git clone https://github.com/nicholaspsmith/MacOS-Dev-Environment-Setup.git
cd MacOS-Dev-Environment-Setup && ./bootstrap.sh --all
```

## Releasing

Every push to `main` is a release. Before pushing, add a dated
`## [X.Y.Z] - YYYY-MM-DD` section to the top of [`CHANGELOG.md`](CHANGELOG.md)
(minor for features, patch for fixes; turn a waiting `## [Unreleased]` into
it). When it reaches `main`, GitHub tags `vX.Y.Z` and publishes the section as
a release titled `vX.Y.Z`. Without a new version:

- a push is refused locally by the `pre-push` hook;
- a pull request **cannot merge** — `release / check` is required on `main`;
- a push that reaches `main` anyway fails the release workflow.

The one exception is `[no release]` in the tip commit's message, for changes
nothing a user runs (setup, CI, developer docs): it passes every check with no
version bump and no tag. Never tag or create a release by hand, and never
`gh pr merge --admin` past a failing check — fix the PR. After merging, `git pull` for the tag and rebuild. `install.sh` re-arms the hook on a fresh clone.
See [StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one) for the whole rule.

## License

Copyright (c) 2026 Nicholas Smith. Licensed under the
[Mozilla Public License 2.0](LICENSE). You may use, modify, sell and
redistribute this software, including inside proprietary products, provided
the copyright notice and license stay on these files and any modified
versions of them are made available under the same license.

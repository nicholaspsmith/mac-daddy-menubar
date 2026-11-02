# Mac Daddy

<p align="center"><img src="docs/mascot.png" width="160" alt="Menu Pimp, Mac Daddy's menu-bar character, on its app icon"></p>

<p align="center">Part of <strong><a href="https://menumon.nicksmith.software">Menumon</a></strong>.</p>

<p align="center"><img src="docs/animation.png" alt="Menu Pimp grinning, a gold gleam crossing his teeth"></p>

A macOS menu-bar app that looks after your processes and files. It kills
Apple's media-analysis daemons, trashes stale downloads, finds orphaned
processes burning CPU, learns which CPU hogs you force-quit and quits them for
you, and warns as your process count nears the per-user limit. Turn on the
**Pimp Cane** (Launcher) and ⌘Space also opens apps, does arithmetic, converts
units and finds emoji; it was Menu Crane until 1.17.0. Built on
[StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) and
[HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit).

It has two vocabularies: **Pimp Mode** (the default) and **Normal Mode** (see
[Mode](#mode)). This README uses the Pimp Mode names with the Normal Mode name
in brackets the first time.

**Version 1.18.0** · [Changelog](https://github.com/nicholaspsmith/mac-daddy-menubar/releases)

![The menu-bar icon](docs/menubar-icon.png)

In Pimp Mode the icon is the mascot, Menu Pimp. His hat shows the process count:

- **Purple hat, cool** — plenty of headroom
- **Amber hat, one drop of sweat** — the count is climbing toward the per-user limit
- **Red hat, two drops of sweat** — close to the limit
- **Hat tip** — for two seconds after the media-tracker killer or Hoes kills something
- **Chain glint** — for two seconds after the Downloads sweep trashes files
- **Asleep, grey, eyes closed, with a "z"** — every duty is paused (the hat keeps its warning colour)

Now and then he grins and a gold gleam crosses his teeth (550 ms). When
several Menumon mascots are running they take turns, a second apart:
Archimedes (Claude Usage), Menu Pimp (Mac Daddy), Carol (SoundChain),
Iguanamous (VPN & DNS), then Armonitor (Panes), counting only the
ones that are running. Skipped when Reduce Motion is on.

In Normal Mode the icon is a plain sparkles symbol in the same colours.

## Menu

Processes sits at the top. Each other duty is one summary line ("Downloads —
swept 10/1/26", "Hoes — 1 on the clock (running hot) · 1 suggestion") with its
controls in a submenu. The line goes bold when something needs you, and red
when the duty is failing; the submenu then starts with the reason. With the
launcher on, **Open Pimp Cane** follows. App-wide settings are in the
**Settings…** window (⌘,) at the foot of the menu, above Quit.

| Item | Purpose |
|---|---|
| Processes | Live count against the per-UID limit, a two-minute sparkline, crash-looping processes, Skanky Ass Hoes (Top Spawners), zombies, Open Activity Monitor |
| Media Tracking ▸ Enabled / Pimp Slap Now / Interval / Processes | Kills Apple's media-analysis daemons every 5 / 15 / 30 / 60 s; one toggle per daemon |
| Downloads ▸ Enabled / Sweep Now / Keep Files For / Open Log | Moves files older than 7 / 14 / 30 / 60 / 90 days from `~/Downloads` to the Trash |
| Hoes (CPU Hogs) ▸ … | Third-party CPU hogs, hoes with no pimp (orphaned processes), and learned kill rules — see below |
| Open Pimp Cane (Open Launcher) | Opens the launcher panel; shown only while the launcher is on, with "⚠ Hotkey unavailable" above it when another app holds the hotkey |
| Settings… | The Settings window, below |
| Quit Mac Daddy | ⌘Q |

Settings live in the `defaults` domain `com.nicholaspsmith.MacDaddy`.

### Settings

**Settings…** (⌘,) opens one window. It replaced the old Settings submenu:

- **General**: **Mode** (Pimp Mode / Normal Mode) and **Start at Login**
  (`SMAppService`, no launchd agent)
- **Pimp Cane** (Launcher): **Use the Pimp Cane** turns the launcher on and
  off (off on a new install), then its **Hotkey** (**Record…**), **Units**,
  **Emoji skin tone**, **Edit Emoji Aliases…** and **Panel position ▸ Reset**
- the running build's version

The window closes with ⌘W or Esc.

### Processes

Skanky Ass Hoes (Top Spawners) lists the processes with the most descendants.
Each opens a detail window with **Pimp Slap** (SIGTERM) and **Pimp Slap Hard**
(Force Quit), which asks first and sends SIGKILL. When one of your own
non-system processes is holding zombies, the menu offers "Pimp Slap
`<parent>` to reap N", which also asks first.

### Downloads

Checks every 30 minutes and sweeps at most once every 24 hours. **Sweep Now**
runs one immediately. Files go to the Trash and can be restored; nothing is
deleted outright.

### Hoes (CPU Hogs)

Samples your processes every 30 s. A *hoe* is a third-party process (anything
not signed by Apple as part of macOS) at 80% CPU or more for 2 minutes. Each is
listed as `name [pid] — X% for M min` with **Pimp Slap** and **Ignore**;
being listed alone sends no notification.

**Hoes with no pimp (orphaned processes).** Street Walkers (Lost Souls) until
1.18.0. One of your own processes that launchd adopted (parent PID 1) is a hoe
at a lower bar: over 50% CPU on average for 10 minutes, whoever signed it. Think
of a hung headless test run, or a script whose terminal closed. Time asleep
doesn't count. Left out: apps, launchd jobs, XPC services and app extensions
(Safari tabs, virtual machines), macOS's system daemons, helpers that a
background service or their own app is responsible for, normally orphaned
daemons (`cfprefsd`, `mds`, `tmux`, `ollama`, …), and anything you **Spare**.
Its row ends in "· no pimp" ("· orphaned"), with **Pimp Slap** and **Spare**,
and unlike other hoes it notifies you once. **Pimp Slap** checks it is still
the same process, sends SIGTERM, then SIGKILL after 5 s. **Auto Pimp Slap Hoes
With No Pimp** (Auto-End Orphaned Processes; off by default) ends one once it
has qualified continuously for 30 minutes. A process that is both kinds of hoe
is listed once, as a hoe, with the tag.

**Learned rules.** When a hoe disappears while still hot — you force-quit it,
or killed it here — Mac Daddy guesses a rule and asks once, e.g. "Auto pimp
slap spin? (≥90% for 5 min)". The guess is its mean CPU less 10, rounded to
the nearest 5 and clamped to 80–98%, for half as long as it ran hot (2–30
min). Activity Monitor or the Force Quit window being frontmost, or launchd
restarting the process, count as extra evidence. An app vanishing hot is
enough on its own; a command-line program needs that evidence, because one
that simply finished its work (an `ffmpeg` encode, a build) vanishes hot too.
**Yes** creates the rule,
**Adjust** edits the guess first, **No** never asks again for that program.
Force-quitting it again tightens its rule.

Under **Rules** each rule has Threshold, Duration (or on sight), Restart After
Pimp Slap (when its launchd job is known), Skip While In Front (on for apps),
Paused and Delete. A rule sends SIGTERM, then SIGKILL after 5 s, and notifies
you. Never touched: macOS's own programs, Mac Daddy itself, and anything under
**Ignored**.

**Universal Audio watchdog.** On a Mac with Universal Audio software there are
three built-in rules that SIGKILL at once and restart the mixer engine so
Apollo audio comes back: an orphaned `UA Mixer Helper` at 80% on sight,
`UA Mixer Engine` at 98% for 2 min, and any other UA process at 90% for
1 min. Built-ins can be adjusted or paused, not deleted. They log to
`~/.local/state/ua-watchdog.log` (summarised at the foot of **Rules**);
everything else logs to `~/Library/Logs/MacDaddy/hoes.log`. Hoes runs only
while Mac Daddy is running.

### Pimp Cane (Launcher)

Menu Crane, folded into Mac Daddy in 1.17.0. **⌘Space** opens a panel over the
frontmost app, including a full-screen one. Drag the panel's background to
move it; it reopens where you left it, as long as that spot is still on a
connected screen. Turning the launcher off releases the hotkey.

| Key | Does |
|---|---|
| ⌘Space | Open the panel; press again to close it |
| ↑ / ↓, ⌃N / ⌃P | Move the selection |
| ↩ | Run the selected row's default action |
| ⌥↩ | Run its alternate action: reveal an app in Finder, copy a conversion with its unit |
| ⌘↩ | Search in Spotlight: close the panel and type the query into the system Spotlight panel |
| ⌘1 … ⌘9 | Run that numbered row directly |
| Esc | Clear the query, then close the panel |
| ⌘W | Close the panel |
| ⌘, | Open Settings |

**Search in Spotlight.** ⌘↩ hands exactly what you typed to macOS's own
Spotlight panel (Siri's "Search or Ask" on macOS 27): the panel closes,
Spotlight opens with its shortcut (read from System Settings ▸ Keyboard ▸
Keyboard Shortcuts ▸ Spotlight, ⌥Space if unset), and the query is typed into
its field. It never presses Return. This posts keystrokes, so it needs Mac
Daddy allowed in **System Settings ▸ Privacy & Security ▸ Accessibility**.
Without that, or if Spotlight's shortcut is off or its panel doesn't appear
within 3 s, the query stays in the panel with the reason in the footer.

**Hotkey.** **Record…** in Settings, then press the shortcut (it needs ⌘, ⌥,
⌃ or ⇧). If another app holds it, Settings shows a red warning, the previous
hotkey stays active, and the menu shows **⚠ Hotkey unavailable**; Mac Daddy
retries every 5 s until it is free.

**Emoji.** Type `e` or `emoji` and press ↩ to open the grid, most recently
used first. ↩ or a click copies the selected emoji and closes the panel. ⌘K
edits the selected emoji's aliases inline; ⌘⇧S cycles the default skin tone.
Esc, ⌫ on an empty search, or the **‹ Back** chip return to the main list. A
query matches regardless of word order (`fingers crossed`, `crossed fingers`,
`cross fing` and `luck` all find 🤞), and your own aliases outrank Unicode's
names.

**Math.** `+ - * /` and `x` as a synonym for `*`, with parentheses, decimals
and a leading minus. ↩ copies the bare answer.

**Conversions.** `72f to c`, `12 fl oz in pt`, `100 km/h`: temperature, mass,
volume, length, speed and acceleration. An explicit `to <unit>` always wins.
Otherwise a bare value follows **Units**: **US Imperial** (the default)
converts metric values to US customary and US values with a natural metric
pairing to metric (`72f` → °C, `100 km/h` → mph); **Metric** converts US
values to metric and leaves bare metric values alone. ⌥↩ copies the answer
with its unit.

**Files.** `~/Library/Application Support/MacDaddy/Launcher/aliases.json`
holds your emoji aliases (`{ "🤓": ["nerd"] }`; hand-editable, reloaded
live), and `usage.json` beside it app launch counts and recent emoji, for
ranking. Everything else is in the `launcher.` keys of the defaults domain.
No network calls.

## Mode

**Pimp Mode** shows Menu Pimp and uses his words. **Normal Mode** shows the
sparkles symbol and uses standard terms. Switching in **Settings… ▸ Mode** applies at
once to the icon, the menu, notifications and the process window. Log files,
defaults keys and code use the same names in either mode.

| Pimp Mode | Normal Mode |
|---|---|
| Hoes, on the clock | CPU Hogs, running hot |
| Hoe with no pimp | Orphaned process |
| Skanky Ass Hoes | Top Spawners |
| Pimp Slap, pimp slapped | End / Kill / Quit, ended / killed |
| Pimp Slap Hard | Force Quit |
| Pimp Slap Now, Restart After Pimp Slap, Auto Pimp Slap Hoes With No Pimp | Kill Now, Restart After Kill, Auto-End Orphaned Processes |
| Auto pimp slap …?, Last pimp slap, Pimp slaps today | Auto-kill …?, Last kill, Kills today |
| Pimp Cane | Launcher |

## Requirements

- macOS 13+, Swift 5.9 / Xcode Command Line Tools
- [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) and
  [HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit) checked out as
  **sibling** directories (local SPM path dependencies)
- On first run, allow **Downloads folder access** when prompted
- **Accessibility** only for the launcher's ⌘↩ (Search in Spotlight)

## Install

```sh
cd ~/Code
git clone https://github.com/nicholaspsmith/StatusItemKit.git
git clone https://github.com/nicholaspsmith/HotkeyKit.git
git clone https://github.com/nicholaspsmith/mac-daddy-menubar.git
cd mac-daddy-menubar
./install.sh
```

`install.sh` builds the app, symlinks it into `~/Applications`, retires the
older tools below, offers Start at Login (only when run in a terminal), and
launches it.

### Retired tools

Mac Daddy does the work of several older apps and agents. `install.sh` removes
them if present:

| Retired | What `install.sh` does |
|---|---|
| Media Tracking Killer, Download Recycler, Process Monitor | quits it, turns its login item off, removes its `~/Applications` link |
| godot-headless-reaper (launchd agent) | boots it out, removes its plist, moves its script to the Trash |
| Menu Crane | Mac Daddy itself, on every launch: quits it and turns its login item off. Its link and bundle are left for parity or you to remove |
| ua-watchdog (launchd agent, from Apollo Monitor) | boots it out, removes its plist, heartbeat and state files, moves its script to the Trash, keeps its log. If the agent was disabled, the built-in UA rules start paused |

On first launch Mac Daddy imports the Media Tracking Killer and Download
Recycler settings, and a previous choice of the plain icon becomes Normal Mode.
If Menu Crane is installed or left settings behind, Mac Daddy also copies its
hotkey, units, skin tone, panel position, aliases and usage (never over its
own) and turns the launcher on.

### Start at Login

Toggle it in Settings… ▸ Start at Login, or from the shell:

```sh
"$HOME/Applications/Mac Daddy.app/Contents/MacOS/MacDaddy" --login on       # or: off, status
```

Start at Login is `SMAppService.mainApp`, which can only register the calling
process's own bundle, so the command must be the *installed* binary. A bare
`--login`, or `--login status`, only reports the current state.

## Uninstall

```sh
"$HOME/Applications/Mac Daddy.app/Contents/MacOS/MacDaddy" --login off
osascript -e 'quit app "Mac Daddy"'
rm "$HOME/Applications/Mac Daddy.app"
defaults delete com.nicholaspsmith.MacDaddy
rm -r "$HOME/Library/Application Support/MacDaddy"   # the launcher's aliases and usage
```

Turn Start at Login off before removing the link; otherwise remove the entry
under System Settings ▸ General ▸ Login Items.

## Development

```sh
swift build
swift test               # MacDaddyCore and LauncherCore
scripts/build-app.sh     # builds build/Mac Daddy.app
```

`MacDaddyCore` holds the detection and rule logic with no AppKit dependency;
`LauncherCore` the launcher's (query parsing, matching, calculator, converter,
emoji and alias stores, usage ranking, panel placement, the Menu Crane
migration); the `MacDaddy` target is the menu, icon, duties, Settings window
and the launcher's panel (`Sources/MacDaddy/Launcher`).

To update the emoji data (`Resources/bundle/emoji.json`, committed; never
fetched at runtime), bump the pinned versions and run
`EMOJI_VERSION=16.0 CLDR_TAG=release-46 scripts/update-emoji-data.sh`.

## The menu-bar suite

Part of a suite of macOS menu-bar apps that share one framework, one
build-and-sign script, and one installer. They are designed to sit in the
same bar together: consistent menus, a common **Icon** picker for shape and
colour (in Mac Daddy, **Mode** picks the icon and the wording together), and
cooperative hiding so no icon strands another.

| App | What it does |
|---|---|
| [Claude Usage](https://github.com/nicholaspsmith/claude-usage-menubar) | Claude Code plan limits, resets, and live agent sessions |
| [Apollo Monitor](https://github.com/nicholaspsmith/apollo-monitor-menubar) | Apollo audio-interface monitor level |
| [Battery Time](https://github.com/nicholaspsmith/battery-time-menubar) | Time remaining, power mode, and 24h usage |
| [VPN & DNS](https://github.com/nicholaspsmith/vpn-dns-menubar) | An iguana for Mullvad + Tailscale state, with a DNS watcher |
| **Mac Daddy** | Kills media trackers, trashes stale downloads, reaps hung processes, watches the UA mixer engine, sweats as your process count climbs, and (optionally) a ⌘Space launcher for apps, arithmetic, unit conversions and emoji |
| [KeyLight](https://github.com/nicholaspsmith/keylight-menubar) | Ctrl+brightness keys remapped to keyboard backlight |
| [Homestead](https://github.com/nicholaspsmith/home-assistant-menubar) | Home Assistant dashboards and device controls in the menu |
| [Panes](https://github.com/nicholaspsmith/panes-menubar) | Window shortcuts, a layout grid and edge snapping, plus external-monitor brightness and contrast, the built-in screen from dimmer than macOS allows to XDR, and Night Shift |
| [SoundChain](https://github.com/nicholaspsmith/soundchain-menubar) | One chain of Audio Unit effects over all system audio |
| [MacRecorder](https://github.com/nicholaspsmith/MacRecorder) | Screen recording with system audio |
| [Barn](https://github.com/nicholaspsmith/menubar-barn) | macOS 26 and earlier only: hides a block of status icons by width (on macOS 27, use System Settings ▸ Menu Bar) |

| Framework | |
|---|---|
| [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) | Status-item lifecycle, polling, menus, meter and mascot icons, the shared Icon picker |
| [HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit) | Global keyboard and media-key bindings |
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

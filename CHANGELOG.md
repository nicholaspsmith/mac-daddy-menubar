# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.6.2] - 2026-10-06

- Ticking a checkbox in the menu no longer closes it: each duty's Enabled, the tracker Processes, Banish Automatically (Pimp Slap Automatically), and a rule's Restart After Kill, Skip While In Front and Paused, plus Settings ▸ Start at Login. The duty's line and the rule's "(paused)" update as you tick

## [1.6.1] - 2026-10-05

- New app icon: Menu Pimp as he looks in the menu bar

## [1.6.0] - 2026-10-05

- feat: a Settings submenu at the foot of the menu holds Mode along with Start at Login and the version, the same Settings submenu every Menumon app now has. Quit stays below it

## [1.5.0] - 2026-10-02

- New **Mode** setting (menu ▸ Mode) in place of the Icon picker. **Pimp Mode**, the default, shows Menu Pimp and speaks his language everywhere — menus, notifications, alerts and the process window: Hoes (CPU Hogs) are on the clock (running hot), Street Walkers (Lost Souls) are on the street (wandering), the busiest spawners are Skanky Ass Hoes (Top Spawners), and anything ended gets a Pimp Slap (Kill): Pimp Slap Now, Pimp Slap Hard (Force Quit), Restart After Pimp Slap, Pimp Slap Automatically (Banish Automatically), "Auto pimp slap …?" suggestions, "Pimp slapped runaway …" and the UA pimp-slap counts. **Normal Mode** shows the plain symbol and uses the standard terms in parentheses above. If you had picked the plain symbol icon, you start in Normal Mode. Log files read the same in either mode
- The menu is shorter: Media Tracking, Downloads, Street Walkers and Hoes are each one summary line ("Street Walkers — 2 on the street") with their controls in a submenu. A line goes bold when something is waiting on you and red when that duty is failing. Processes stays at the top, and its Zombies line only appears when there are some

## [1.4.0] - 2026-10-02

- New **Hoes** duty: lists third-party processes working the CPU (80% or more for 2 minutes) with **End** and **Ignore**. When you force-quit one while it's still hot, Mac Daddy suggests a rule to end it for you next time, guessing the threshold and duration from what it saw; **Yes**, **Adjust** or **No**. Force-quit it again and the rule tightens. Rules can be adjusted, paused, set to restart a launchd job, or skipped while the app is in front. macOS's own programs are never touched
- The `ua-watchdog` launchd agent from Apollo Monitor is now three built-in Hoes rules (shown only when Universal Audio software is installed): an orphaned UA Mixer Helper at 80% is killed at once, the UA Mixer Engine at 98% for 2 minutes, anything else UA at 90% for 1 minute, and the mixer engine is kickstarted so Apollo audio comes back. The installer and Mac Daddy retire the agent, its log carries on, and if you had disabled it the rules start paused. Unlike the agent, they only run while Mac Daddy is running

## [1.3.0] - 2026-10-02

- feat: once a minute Menu Pimp grins, showing white teeth with a gold gleam sweeping across them, in turn with the other animated Menumon mascots
- Mascot renamed: Mac Daddy (the app) is run by Menu Pimp, the Mac Daddy of the menu bar

## [1.2.0] - 2026-10-01

- Mac Daddy's menu-bar icon is now his illustrated mascot; the hat turns amber then red as the process count climbs

## [1.1.2] - 2026-10-01

- Mac Daddy keeps working if a private macOS function it uses goes away (Lost Souls then skips only its responsible-process check)

## [1.1.1] - 2026-10-01

- Lost Souls no longer flags Safari/WebKit tabs, virtual machines, other XPC services, app extensions or macOS's own background programs, and leaves alone helpers that a background service or their own app is responsible for
- Time asleep (or with Lost Souls turned off) no longer counts toward the 10 minutes; turning Lost Souls off and on starts afresh
- End works on programs that rename themselves, and checks it is still the very same process (start time, no parent, yours) before each signal; if it isn't, a ⚠ says so instead of ending something else
- The "Not allowed to end …" warning clears once that process is gone, after a later End works, or when Lost Souls is toggled
- Several lost souls at once get one notification; the menu lists the 8 hungriest plus "and N more…"; Banish Automatically notifies once per process

## [1.1.0] - 2026-10-01

- New **Lost Souls** duty: spots any of your own processes that has been orphaned (no parent) and burning more than 50% CPU for 10 minutes, notifies you once, and lists it in the menu with **End** and **Spare**. Apps, launchd jobs and normal background daemons are left out
- **Banish Automatically** (off by default) ends a lost soul once it has been listed for 30 minutes, and tells you it did
- The Godot-specific reaper is gone, replaced by this general version (a hung headless Godot run is just another lost soul); your Godot Reaper on/off setting carries over

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

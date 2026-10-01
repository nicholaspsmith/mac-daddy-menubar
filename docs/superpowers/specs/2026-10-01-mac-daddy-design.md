# Mac Daddy — design

Status: approved in conversation 2026-10-01; awaiting spec review.

## Intent

One menu-bar app that keeps the Mac in line, replacing three icons with one on
a bar that already overflows past the notch:

- **Media Tracking Killer** — stops Apple's media-analysis daemons.
- **Download Recycler** — moves old files from `~/Downloads` to the Trash.
- **Process Monitor** — watches the per-user process count against
  `kern.maxprocperuid`.

Plus two jobs that today live outside the suite:

- **godot-headless-reaper** — launchd agent + `~/.local/bin` script that
  SIGKILLed hung headless Godot test runs. Since 1.1.0 its job is done by the
  general **Lost Souls** duty (see "Lost Souls (1.1.0)" below).
- **Zombie count** — a general "zombies: N" reading with a "Quit <parent> to reap N" action (the
  Pioneer `FwUpdateManagerd` leak that motivated it is gone, but the next
  leaker will show up here first).

Success: Mac Daddy does everything the three apps and the reaper agent did,
with the same settings, from one 24pt icon; the old apps, their login items and
the reaper agent are gone from both Macs; the site and READMEs list Mac Daddy
instead.

Not in scope: UA watchdog (stays in Apollo Monitor), the Mullvad/Tailscale DNS
watcher (moves into VPN & DNS separately), anything display-related (Monitor
Lizard), the suite rename away from "Menubarn" (separate project; Mac Daddy's
README uses whatever name that lands on, "Menubarn" until then).

## Structure

Repo `~/Code/mac-daddy-menubar`, public at
`github.com/nicholaspsmith/mac-daddy-menubar`. App `Mac Daddy.app`, bundle id
`com.nicholaspsmith.MacDaddy`, `LSUIElement`, built on StatusItemKit with
`make-app.sh`, symlinked into `~/Applications`, Start at Login via
SMAppService (offered by `install.sh`, never turned on unasked). Runs a
`YieldClient` like the other StatusItemKit apps.

### `MacDaddyCore` (library, no AppKit UI, fully unit-tested)

- `CountHistory`, `ProcRec`, `RespawnDetector`, `TopSpawners` — moved from
  `ProcessMonitorCore` unchanged, with their tests.
- `Mood` — pure function from inputs to the icon state:
  - inputs: process fraction (`Double?`; nil = unreadable), `anyCleanupEnabled`
    (`Bool`), last flourish (`Flourish?` + timestamp), now.
  - output: `level` (`.cool` < 0.60 ≤ `.sweating` < 0.85 ≤ `.redHot`; nil
    fraction → `.cool`), `asleep` (= !anyCleanupEnabled), `flourish`
    (`.hatTip` / `.chainGlint` while < 2.0 s old, else none).
- `SettingsMigration` — copies old defaults domains into Mac Daddy's
  (see Migration); pure over a `[String: Any]` source/target abstraction so it
  is testable without touching real defaults.
- `LostSouls` — tracks orphaned processes' CPU over a rolling window and
  says which qualify (see "Lost Souls (1.1.0)"). Replaced `ReapRule`.
- `ZombieCount` — parses `ps -axo stat=` output, counts states starting `Z`,
  and offers the parent with the most zombies for quitting — only one of
  your own, never PID 1, Mac Daddy itself, or a system process
  (loginwindow, WindowServer, Dock, Finder, SystemUIServer, ControlCenter,
  launchd).
- `DownloadAge` — given file URLs + modification/added dates + days-to-keep,
  returns the ones to trash.

### `Duties/` (app target, one file each)

Each duty owns its settings (namespaced keys), its timer, its menu section, and
reports to the app through two callbacks: `onSweep(Flourish)` and
`onError(String?)`.

| Duty | Does | Timer | Settings (namespace) |
|---|---|---|---|
| `TrackerKiller` | SIGINT to `mediaanalysisd`, `mediaanalysisd-access`, `photoanalysisd` (each toggleable) | 5/15/30/60 s, default 15 | `tracker.enabled`, `tracker.intervalSeconds`, `tracker.target.<name>` |
| `DownloadSweeper` | `FileManager.trashItem` for files older than N days in `~/Downloads`; notifies with the count; appends to `~/Library/Logs/download-recycler.log` (path kept so the audit trail stays continuous) | checks every 30 min, sweeps once 24 h have passed since `lastSweep` (as Download Recycler does today) | `downloads.enabled`, `downloads.daysToKeep` (7/14/30/60/90, default 30), `downloads.lastSweep` |
| `ProcessWatch` | per-UID process count vs `kern.maxprocperuid`, mirroring `ps -u $USER \| wc -l` but counted with `sysctl(KERN_PROC_RUID)` so a full process table cannot blind it (a failed read at ≥ 85 % holds the last fraction); notifies once when crossing 85 % (re-arms below 80 %); zombie count; sparkline, crash-loop detection and top spawners as Process Monitor has them; detail window (moved from `ProcessDetailWindow.swift`) | 5 s | none (always on) |
| `LostSoulsDuty` | notify about, and on request end, lost souls per `LostSouls` | samples every 30 s | `lostSouls.enabled` (default on), `lostSouls.autoBanish` (default off) |

`TrackerKiller` emits `.hatTip` on a kill that hit at least one live process;
`DownloadSweeper` emits `.chainGlint` when it trashed at least one file;
`LostSoulsDuty` emits `.hatTip` when it ended a soul. `ProcessWatch` emits no
flourish; it feeds the fraction.

### App (`main.swift`)

Builds the status item through StatusItemKit's `StatusItemController`,
collects duty callbacks, recomputes `Mood`, and redraws. `anyCleanupEnabled` =
tracker or downloads or Lost Souls enabled.

## Menu

```
Processes  1234 / 2666 (46%)
  ▁▂▃▅▃▂  1180→1240                 (sparkline, ~2 min)
  ⚠ Crash-looping (N) ▸             (only when present)
  Top Spawners ▸                    → each opens the detail window
  Zombies  0
    Quit <parent> [pid] to reap N   (only for one of your own, non-system
                                     processes; asks to confirm first)
  Open Activity Monitor
────────────
Media Tracking
  ✓ Enabled
    Kill Now
    Interval ▸            5 / 15 / 30 / 60 s
    Processes ▸           one toggle per daemon
Downloads
  ✓ Enabled
    Sweep Now
    Keep Files For ▸      7 / 14 / 30 / 60 / 90 days
    Open Log
Lost Souls
  ✓ Enabled
    <name> [pid]  —  X% for M min ▸   End / Spare   (one row per soul;
                                     "None wandering" when there are none)
    Banish Automatically
────────────
Icon ▸                    Mac Daddy / Plain symbol
Start at Login
Version X.Y.Z
Quit Mac Daddy
```

Headings are disabled bold items, their items indented — no submenus for the
primary actions. A failing duty shows `⚠ <reason>` directly under its heading.
Process Monitor's eight display modes are dropped; the count lives in the
first row.

## Lost Souls (1.1.0)

Replaces the Godot-only reaper with a general duty. A **lost soul** is a
process that is owned by you, has PPID 1 (adopted by launchd), and has
averaged more than 50 % CPU over a rolling window of at least 10 minutes,
unless it is:

- a real app: its executable is inside `*.app/Contents/MacOS/` **and**
  `NSRunningApplication(processIdentifier:)` reports a `.regular` or
  `.accessory` app (headless Godot runs from `Godot.app/Contents/MacOS/Godot`
  but has no running-application entry, so it still counts);
- a launchd job (its PID is in `launchctl list`'s PID column);
- an XPC service, app extension or OS binary (1.1.1): its real path
  (`proc_pidpath`, not `ps` comm) contains `.xpc/` or `.appex/`, or starts
  with `/System/`, `/usr/libexec/`, `/usr/sbin/` or `/Library/Apple/` —
  these are not even tracked;
- held by macOS to be the responsibility (1.1.1,
  `responsibility_get_pid_responsible_for_pid`) of a different process that
  is a launchd job with a non-`application.*` label (a daemon/agent), or of a
  running app whose `.app` bundle contains this executable. A responsible
  app alone does **not** exclude: every orphan started from a terminal is
  attributed to the terminal app (iTerm2), and GUI apps are themselves
  `application.*` launchd jobs, so the literal "responsible is an app or a
  launchd job" rule would exclude every real lost soul;
- on the built-in allowlist of basenames that are normally orphaned
  (`launchd`, `loginwindow`, `WindowServer`, `cfprefsd`, `distnoted`,
  `mdworker`, `mdworker_shared`, `mds`, `mds_stores`, `trustd`,
  `nsurlsessiond`, `UserEventAgent`, `secd`, `coreaudiod`, `ssh-agent`,
  `gpg-agent`, `tmux`, `screen`, `mosh-server`, `ollama`, `MacDaddy`);
- spared by you (until it exits; a new process reusing the PID is not).

**Sampling.** Every 30 s, off the main thread:
`ps -U <uid> -o pid=,ppid=,%cpu=,etime=,comm= -ww` and `launchctl list`.
`LostSouls` (core, unit-tested) keeps samples only for orphans, keyed by PID
with the comm and start time (now − etime, ±3 s) as identity, so a reused PID
starts over; it keeps just enough samples to span the window and forgets PIDs
that exit or stop being orphans. A soul qualifies when its samples span ≥ the
window, there are at least 80 % of the samples a fully covered window would
have, and their mean is > 50 %. A track whose last sample is older than 3
sample intervals (sleep) starts over; turning the duty off discards all
tracks. Since 1.1.1 identity is the exact start time from
`proc_pidinfo(PROC_PIDTBSDINFO)`, samples are stamped when `ps` returned, and
names/allowlist use the real path's basename.

**Behaviour.** Never kills by default. The first time a soul qualifies:
notification "`<name>` (pid N) has been burning X% CPU for M min with no
parent". **End** re-checks, before SIGTERM and again before the SIGKILL 5 s
later, that the PID still has the soul's start time (within 1 s), PPID 1 and
your UID (no name comparison, so self-renaming processes work); if not, a ⚠
"<name> changed — not ended". Hat tip on success. EPERM shows a ⚠ line under
the heading, cleared when that soul is gone, after a later successful End, or
on toggling; ESRCH is not an error. Spare keys on pid + start time.
**Banish Automatically** (off by default) ends, by the same path, any soul
that has qualified continuously for 30 minutes, notifying once per process.
Several new souls in one round get one summary notification; the menu shows
the 8 hungriest plus "and N more…".

**Migration.** `migration.version` 2 copies `reaper.enabled` into
`lostSouls.enabled` if set and of the right type, never overwriting. The
launch-time `launchctl bootout` of the old reaper agent stays as a backstop.

## The icon

`CharacterIcon.macDaddy(level:asleep:flourish:)` in StatusItemKit (minor
release), drawn in the caterpillar/raccoon style — ink outlines, shading, a
face. 24×22 pt in every state; the silhouette is the wide hat brim and
feather.

| State | Drawing |
|---|---|
| `.cool` | half-lidded eyes, purple suit, gold chain |
| `.sweating` | sweat drop, eyes open, suit shading toward amber |
| `.redHot` | collar tug, wide eyes, red suit |
| `asleep` | eyes shut, a "z", greyed — but `.sweating`/`.redHot` cues still drawn |
| `.hatTip` | hat raised off the head for 2 s |
| `.chainGlint` | sparkle on the chain for 2 s |

**Icon ▸ Plain symbol** swaps him for an SF Symbol (`sparkles` or similar,
chosen at build) tinted by the level colours. The choice persists
(`iconStyle`).

App icon (`Resources/bundle/AppIcon.icns`) and README mascot come from the
site's `art/gen_icons.py mac-daddy`; Nick approves the mascot before anything is
pushed public. Glyph images come from `art/glyphs/render-glyphs.sh`.

## Migration from the old apps

On first launch (`migration.version` absent), copy, never overwriting a key
already set in Mac Daddy's domain:

| From domain | Keys | To |
|---|---|---|
| `com.nicholaspsmith.MediaTrackingKiller` | `enabled`, `intervalSeconds`, `target.*` | `tracker.*` |
| `com.nicholaspsmith.DownloadRecycler` | `enabled`, `daysToKeep`, `lastSweep` | `downloads.*` (`lastSweep` carried so it does not re-sweep at once) |

Process Monitor has no user settings worth keeping (its display mode is
obsolete; the 85 % warning was a constant). Then set `migration.version = 1`.
A key that fails to read falls back to the duty's default and is logged; launch
is never blocked.

On first launch Mac Daddy also unloads the reaper agent if loaded
(`launchctl bootout gui/<uid>/com.nicholassmith.godot-headless-reaper`) and
logs whether it did.

`install.sh` (in addition to the usual build, link, Start-at-Login prompt,
relaunch): quits Media Tracking Killer, Download Recycler and ProcessMonitor;
turns off their login items (`--login off` on each binary while it still
exists); removes their `~/Applications` symlinks; unloads and removes the
`godot-headless-reaper` LaunchAgent plist and moves `~/.local/bin/godot-headless-reaper`
to the Trash. Their repos and builds stay on disk. Run on both Macs.

## Error handling

- A duty failure is local: it sets that duty's `⚠` line and the others keep
  running. The icon never shows errors; mood comes only from process load.
- Downloads access refused → `⚠ Needs access to Downloads`; clicking it opens
  System Settings ▸ Privacy & Security ▸ Files and Folders.
- Signals go only to the user's own processes, so no extra permission; a
  `kill` returning `ESRCH` is not an error (already gone), `EPERM` is shown.
- Process count unreadable → fraction nil → `.cool`, Processes row shows "—".
  A bad reading never makes him sweat.
- Migration failures fall back to defaults and are logged
  (`subsystem com.nicholaspsmith.MacDaddy`).

## Testing

- `swift test` on `MacDaddyCore`: ported ProcessMonitorCore tests; `Mood`
  (thresholds at exactly 0.60 and 0.85, nil fraction, asleep + redHot,
  flourish expiry at 2.0 s); `SettingsMigration` (key mapping, run-once,
  never overwrite, partial-failure fallback, v2 reaper → Lost Souls);
  `LostSouls` (orphaned+hot+long qualifies; not orphaned, under 10 min,
  mean ≤ 50, allowlisted, launchd job, app, spared → no; reused PID not
  spared; exited PIDs pruned; malformed lines ignored);
  `ZombieCount`; `DownloadAge` (boundary day).
- Glyph review: `render-glyphs.sh` renders every level × asleep × flourish into
  a contact sheet, checked by eye; same images feed the README and site.
- Live check on the M5, then the M1: a forced sweep shows the flourish; a
  test-only threshold override (removed before release) shows sweating and
  red-hot; old apps quit, their login items gone (`sfltool dumpbtm`), reaper
  agent unloaded, migrated settings visible in the menu.

## Release and retirement

- Mac Daddy `v1.0.0` via the standard Menubarn release workflow
  (`adopt.sh` sets CHANGELOG, workflow, hooks, branch protection).
- StatusItemKit minor release with `CharacterIcon.macDaddy` and its
  `render-glyphs.sh` entry; merged before Mac Daddy depends on it.
- Media Tracking Killer, Download Recycler, MacOS_Process_Monitor: a final
  patch release whose README opens with "Merged into Mac Daddy" and a link,
  then `gh repo archive`.
- Site: remove the three cards, add Mac Daddy's (13 → 11 widgets), regenerate
  glyphs and hero bar, deploy.
- Suite tables in every Menubarn README: three rows → one Mac Daddy row
  (`[no release]` docs pushes).
- `MacOS-Dev-Environment-Setup`: `MENU_BAR_APP_REPOS` and its legacy-agent
  map; readme counts.
- Nick's global CLAUDE.md app list: three apps → Mac Daddy.

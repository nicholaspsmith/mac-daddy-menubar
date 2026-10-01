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
  SIGKILLs hung headless Godot test runs.
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
- `ReapRule` — given `ps -Axo pid=,etime=,command=` lines, returns the PIDs
  to kill: command contains `MacOS/Godot --headless`, elapsed ≥ threshold
  (default 900 s). Never the editor (`-e`, no `--headless`).
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
| `Reaper` | SIGKILL hung headless Godot runs per `ReapRule` | 300 s | `reaper.enabled`, `reaper.thresholdSeconds` (default 900) |

`TrackerKiller` emits `.hatTip` on a kill that hit at least one live process;
`DownloadSweeper` emits `.chainGlint` when it trashed at least one file;
`Reaper` emits `.hatTip` when it killed something. `ProcessWatch` emits no
flourish; it feeds the fraction.

### App (`main.swift`)

Builds the status item through StatusItemKit's `StatusItemController`,
collects duty callbacks, recomputes `Mood`, and redraws. `anyCleanupEnabled` =
tracker or downloads or reaper enabled.

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
Godot Reaper
  ✓ Enabled
    Reap Now
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
  never overwrite, partial-failure fallback); `ReapRule` (headless past
  threshold, headless under threshold, editor never, malformed lines);
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

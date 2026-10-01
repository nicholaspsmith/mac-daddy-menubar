#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Build Mac Daddy.app, symlink it into ~/Applications, retire the apps and the
# launchd agent it replaces, offer Start at Login, and (re)launch it.
set -euo pipefail

RELEASE_KIT="$(cd "$(dirname "$0")/.." && pwd)/StatusItemKit/scripts/release/adopt.sh"
if [ -x "$RELEASE_KIT" ]; then "$RELEASE_KIT" --hooks-only || echo "Release hook: adopt.sh failed" >&2
else echo "Release hook: StatusItemKit not found beside this repo — clone it and re-run" >&2; fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Mac Daddy.app"
"$SRC_DIR/scripts/build-app.sh"
mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

# --- retire the three apps Mac Daddy replaces --------------------------------
retire() {   # $1 = app name in ~/Applications, $2 = executable, $3 = bundle id
    local app="$HOME/Applications/$1.app" bin="$HOME/Applications/$1.app/Contents/MacOS/$2"
    [ -e "$app" ] || [ -L "$app" ] || return 0
    osascript -e "tell application id \"$3\" to quit" >/dev/null 2>&1 || true
    sleep 1; pkill -f "$1.app/Contents/MacOS/$2" 2>/dev/null || true
    if [ -x "$bin" ]; then "$bin" --login off >/dev/null 2>&1 || true
    else echo "Warning: $1's binary is gone, so its login item could not be turned off (System Settings > General > Login Items)." >&2; fi
    if [ -L "$app" ]; then rm -f "$app"; echo "Retired $1 (quit, login item off, ~/Applications link removed)."
    else echo "Warning: $app is a real app bundle, not a link; quit it and left it in place (delete it by hand)." >&2; fi
}
retire "Media Tracking Killer" MediaTrackingKiller com.nicholaspsmith.MediaTrackingKiller
retire "Download Recycler" DownloadRecycler com.nicholaspsmith.DownloadRecycler
retire "ProcessMonitor" ProcessMonitor com.nicholaspsmith.ProcessMonitor

# --- retire the godot-headless-reaper launchd agent ---------------------------
REAPER="com.nicholassmith.godot-headless-reaper"
launchctl bootout "gui/$(id -u)/$REAPER" 2>/dev/null || true
if [ -f "$HOME/Library/LaunchAgents/$REAPER.plist" ]; then
    rm -f "$HOME/Library/LaunchAgents/$REAPER.plist"; echo "Removed the $REAPER agent."
fi
if [ -f "$HOME/.local/bin/godot-headless-reaper" ]; then
    reaper_bin="$HOME/.local/bin/godot-headless-reaper"
    if osascript -e "tell application \"Finder\" to delete POSIX file \"$reaper_bin\"" >/dev/null 2>&1 \
        || { mkdir -p "$HOME/.Trash" 2>/dev/null && mv "$reaper_bin" "$HOME/.Trash/" 2>/dev/null; }; then
        echo "Moved godot-headless-reaper to the Trash."
    else
        echo "Could not move godot-headless-reaper to the Trash — delete it by hand: $reaper_bin" >&2
    fi
fi

# --- Start at Login (ask; never unasked) --------------------------------------
APP="$HOME/Applications/$APP_NAME"
BIN="$APP/Contents/MacOS/MacDaddy"
PROC="${APP##*/}/Contents/MacOS/MacDaddy"
if [ "$("$BIN" --login status 2>/dev/null)" = "on" ]; then echo "Start at Login: already on"
elif [ -t 0 ]; then
    read -r -p "Start Mac Daddy at login? [Y/n] " answer || answer=n
    case "$answer" in
        [nN]*) echo "Start at Login: left off (turn it on from the menu)" ;;
        *) "$BIN" --login on >/dev/null && echo "Start at Login: on" || echo "Start at Login: could not register (turn it on from the menu)" >&2 ;;
    esac
else
    echo "Start at Login: off (not asked: no terminal). Turn it on from the menu, or run"
    echo "    \"$BIN\" --login on"
fi

# --- relaunch ------------------------------------------------------------------
if pgrep -f "$PROC" >/dev/null; then
    osascript -e 'tell application id "com.nicholaspsmith.MacDaddy" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$PROC" >/dev/null || break; sleep 0.5; done
    pkill -f "$PROC" 2>/dev/null || true; sleep 1
fi
/usr/bin/open "$APP"
echo
echo "Mac Daddy is in the menu bar. First run: allow access to Downloads when macOS asks."

#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# Lock by canonical installation path so separate test installs remain independent.
LOCK_KEY="$(printf '%s' "$CONFIG_DIR" | sha256sum)"
LOCK_KEY="${LOCK_KEY%% *}"
LOCK_DIR="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hunu-wallpaper}/hunu-launch"
mkdir -p -- "$LOCK_DIR"
exec 9>"$LOCK_DIR/$LOCK_KEY.lock"
if ! flock -n 9; then
    printf 'Hunu Wallpaper Splitter is already running for this installation.\n'
    exit 0
fi

# Keep the lock for the entire foreground process lifetime; never unlink it.
export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-xdgdesktopportal}"
quickshell --no-duplicate -p "$CONFIG_DIR"

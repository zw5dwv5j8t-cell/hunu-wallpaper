#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
case "${1:-show}" in
    next|previous)
        exec python3 "$SCRIPT_DIR/switcher-controller.py" "$1"
        ;;
    show) ;;
    *) printf 'Usage: %s [show|next|previous]\n' "$0" >&2; exit 2 ;;
esac

KEY="$(printf '%s' "$SCRIPT_DIR" | sha256sum)"
KEY="${KEY%% *}"
LOCK_DIR="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hunu-wallpaper}/hunu-launch"
mkdir -p -- "$LOCK_DIR"
exec 9>"$LOCK_DIR/switcher-$KEY.lock"
if ! flock -n 9; then
    # Allow a first launch time to register IPC before forwarding rapid hotkeys.
    for attempt in {1..10}; do
        if timeout 2 quickshell -p "$SCRIPT_DIR/Switcher.qml" ipc call picker next >/dev/null 2>&1; then
            exit 0
        fi
        sleep 0.1
    done
    printf 'Wallpaper switcher is starting or unavailable. Try again.\n' >&2
    exit 1
fi
export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-xdgdesktopportal}"
quickshell --no-duplicate -p "$SCRIPT_DIR/Switcher.qml"

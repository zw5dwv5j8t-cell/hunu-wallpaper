#!/usr/bin/env bash
set -euo pipefail
if [[ "${HUNU_SWITCHER_TRACE:-0}" == 1 ]]; then
    export HUNU_SWITCHER_STARTED_MS="$(date +%s%3N)"
    printf 'HUNU_SWITCHER {"stage":"launcher","elapsedMs":0}\n' >&2
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
unset HUNU_SWITCHER_NATIVE_BIN
if [[ "${HUNU_SWITCHER_NATIVE:-1}" == 1 && -x "$SCRIPT_DIR/hunu-switcher-native" ]]; then
    export HUNU_SWITCHER_NATIVE_BIN="$SCRIPT_DIR/hunu-switcher-native"
    ENABLED="$("$HUNU_SWITCHER_NATIVE_BIN" enabled "$SCRIPT_DIR")"
else
    ENABLED="$(python3 "$SCRIPT_DIR/switcher-settings.py" enabled)"
fi
if [[ "${HUNU_SWITCHER_TRACE:-0}" == 1 ]]; then
    if [[ -n "${HUNU_SWITCHER_NATIVE_BIN:-}" ]]; then
        printf 'HUNU_SWITCHER {"stage":"startup-helper","implementation":"rust"}\n' >&2
    else
        printf 'HUNU_SWITCHER {"stage":"startup-helper","implementation":"python"}\n' >&2
    fi
fi
[[ "$ENABLED" == true ]] || exit 0
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
# This overlay has no native dialogs or desktop-themed controls. Avoid loading
# a platform-theme plugin (and its portal/settings startup) on every hotkey.
export QT_QPA_PLATFORMTHEME=""
export QT_QUICK_CONTROLS_STYLE=Basic
export HUNU_SWITCHER_PARALLEL="${HUNU_SWITCHER_PARALLEL:-1}"
if [[ "$HUNU_SWITCHER_PARALLEL" != 1 ]]; then
    unset HUNU_SWITCHER_SOCKET
    quickshell --no-duplicate -p "$SCRIPT_DIR/Switcher.qml"
    exit $?
fi

# Private, short socket path; one controller belongs to this picker only.
mkdir -p -- "${XDG_RUNTIME_DIR:-/tmp}"
SESSION_DIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/hunu-picker.XXXXXX")"
export HUNU_SWITCHER_SOCKET="$SESSION_DIR/session.sock"
CONTROLLER_PID=""
PICKER_PID=""
cleanup() {
    if [[ -n "$PICKER_PID" ]]; then
        kill "$PICKER_PID" 2>/dev/null || true
        wait "$PICKER_PID" 2>/dev/null || true
    fi
    if [[ -n "$CONTROLLER_PID" ]]; then
        # Closing Qt disconnects the bridge. Let EOF finish rollback naturally;
        # signalling at the same instant can interrupt its cleanup transition.
        for attempt in {1..100}; do
            kill -0 "$CONTROLLER_PID" 2>/dev/null || break
            sleep 0.02
        done
        kill "$CONTROLLER_PID" 2>/dev/null || true
        wait "$CONTROLLER_PID" 2>/dev/null || true
    fi
    if [[ -S "$HUNU_SWITCHER_SOCKET" ]]; then
        unlink "$HUNU_SWITCHER_SOCKET"
    fi
    rmdir "$SESSION_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$SCRIPT_DIR/switcher-controller.py" serve "$HUNU_SWITCHER_SOCKET" &
CONTROLLER_PID=$!
quickshell --no-duplicate -p "$SCRIPT_DIR/Switcher.qml" <&0 &
PICKER_PID=$!
wait "$PICKER_PID"

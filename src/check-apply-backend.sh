#!/usr/bin/env bash
set -euo pipefail

BACKEND="${1:-}"
READY=false
REASON=""

command -v timeout >/dev/null 2>&1 || {
    echo "ERROR: Required tool 'timeout' was not found." >&2
    exit 127
}

case "$BACKEND" in
    serpantinum)
        DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
        SHELL_PATH="$DATA_HOME/serpantinum/src/quickshell/Shell.qml"

        if ! command -v quickshell >/dev/null 2>&1; then
            REASON="Quickshell is not installed."
        elif [[ ! -f "$SHELL_PATH" ]]; then
            REASON="Serpantinum integration was not found."
        elif ! reply="$(timeout 3 quickshell -p "$SHELL_PATH" ipc show 2>/dev/null)"; then
            REASON="Serpantinum IPC is unavailable or timed out."
        elif awk '
            /^target / { wallpaper = ($2 == "wallpaper") }
            wallpaper && /^[[:space:]]+function setWallpaper\(/ {
                found = 1
            }
            END { exit !found }
        ' <<< "$reply"; then
            READY=true
            REASON="Serpantinum wallpaper IPC is ready."
        else
            REASON="Serpantinum wallpaper endpoint was not found."
        fi
        ;;
    hyprpaper)
        if ! command -v hyprpaper >/dev/null 2>&1; then
            REASON="hyprpaper is not installed."
        elif ! command -v hyprctl >/dev/null 2>&1; then
            REASON="hyprctl is not installed."
        elif ! reply="$(timeout 3 hyprctl hyprpaper listactive 2>&1)"; then
            REASON="hyprpaper IPC is unavailable or timed out."
        elif [[ "$reply" == error:* || "$reply" == "[hw] err:"* ]]; then
            REASON="hyprpaper IPC is unavailable."
        else
            READY=true
            REASON="hyprpaper IPC is ready."
        fi
        ;;
    awww)
        if ! command -v awww >/dev/null 2>&1; then
            REASON="awww is not installed."
        elif ! reply="$(timeout 3 awww query 2>&1)"; then
            REASON="awww IPC is unavailable or timed out."
        else
            READY=true
            REASON="awww IPC is ready."
        fi
        ;;
    *)
        echo "ERROR: Unsupported backend: $BACKEND" >&2
        exit 2
        ;;
esac

printf 'BACKEND=%s\n' "$BACKEND"
printf 'BACKEND_READY=%s\n' "$READY"
printf 'BACKEND_REASON=%s\n' "$REASON"
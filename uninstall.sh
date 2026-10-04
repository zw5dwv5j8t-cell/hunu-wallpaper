#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${HUNU_APP_NAME:-hunu-wallpaper}"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

CONFIG_DIR="$CONFIG_HOME/$APP_NAME"
CACHE_DIR="$CACHE_HOME/$APP_NAME"
DESKTOP_FILE="$DATA_HOME/applications/$APP_NAME.desktop"
ICON_FILE="$DATA_HOME/icons/$APP_NAME.png"
BACKUP_ROOT="$STATE_HOME/$APP_NAME/backups"

printf '\nHunu Wallpaper Splitter (%s) — uninstaller\n' "$APP_NAME"
printf '============================================\n\n'

rm -rf "$CONFIG_DIR"
rm -rf "$CACHE_DIR"
rm -f "$DESKTOP_FILE" "$ICON_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
fi

printf 'Removed:\n'
printf '  %s\n' "$CONFIG_DIR"
printf '  %s\n' "$CACHE_DIR"
printf '  %s\n' "$DESKTOP_FILE"
printf '  %s\n\n' "$ICON_FILE"
printf 'Generated wallpapers were left untouched.\n'

if [[ -d "$BACKUP_ROOT" ]]; then
    printf 'Installer backups were left untouched:\n'
    printf '  %s\n' "$BACKUP_ROOT"
fi

printf '\n'

#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 2 ]] || die "Expected CONFIG_PATH BACKEND."

CONFIG_PATH="$1"
BACKEND="$2"

[[ -f "$CONFIG_PATH" ]] || die "Save monitor setup first."

case "$BACKEND" in
    serpantinum|hyprpaper|awww) ;;
    *) die "Unsupported wallpaper backend: $BACKEND" ;;
esac

CONFIG_DIR="$(dirname -- "$CONFIG_PATH")"
TEMP_CONFIG="$(mktemp "$CONFIG_DIR/.backend-config.XXXXXX")"
trap 'rm -f -- "$TEMP_CONFIG"' EXIT

awk '!/^[[:space:]]*APPLY_BACKEND=/' "$CONFIG_PATH" > "$TEMP_CONFIG"
printf '\nAPPLY_BACKEND=%q\n' "$BACKEND" >> "$TEMP_CONFIG"

chmod --reference="$CONFIG_PATH" "$TEMP_CONFIG"
mv -fT -- "$TEMP_CONFIG" "$CONFIG_PATH"

printf 'APPLY_BACKEND=%s\n' "$BACKEND"
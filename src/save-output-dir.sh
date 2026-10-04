#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 2 ]] || die "Expected CONFIG_PATH OUTPUT_DIRECTORY."

CONFIG_PATH="$1"
WALLPAPER_DIR="$2"

[[ -f "$CONFIG_PATH" ]] || die "Save monitor setup first."
[[ "$WALLPAPER_DIR" == /* ]] || die "Output directory must be an absolute path."
[[ -d "$WALLPAPER_DIR" ]] || die "Selected directory does not exist."
[[ -w "$WALLPAPER_DIR" ]] || die "Selected directory is not writable."

CONFIG_DIR="$(dirname -- "$CONFIG_PATH")"
TEMP_CONFIG="$(mktemp "$CONFIG_DIR/.output-config.XXXXXX")"
trap 'rm -f -- "$TEMP_CONFIG"' EXIT

# Hunu writes OUTPUT_DIR as a single Bash assignment.
# Preserve monitor calibration and other configuration lines.
awk '!/^[[:space:]]*OUTPUT_DIR=/' "$CONFIG_PATH" > "$TEMP_CONFIG"
printf '\nOUTPUT_DIR=%q\n' "$WALLPAPER_DIR" >> "$TEMP_CONFIG"

chmod --reference="$CONFIG_PATH" "$TEMP_CONFIG"
mv -fT -- "$TEMP_CONFIG" "$CONFIG_PATH"

printf 'OUTPUT_DIR=%s\n' "$WALLPAPER_DIR"

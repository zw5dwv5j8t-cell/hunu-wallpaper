#!/usr/bin/env bash
set -euo pipefail

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

(( $# >= 2 && $# % 2 == 0 )) || die "Expected OUTPUT FILE pairs."

command -v quickshell >/dev/null 2>&1 || die "Quickshell is not installed."

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
SERPANTINUM_SHELL="$DATA_HOME/serpantinum/src/quickshell/Shell.qml"

[[ -f "$SERPANTINUM_SHELL" ]] || \
    die "Serpantinum wallpaper integration was not found. Wallpapers were generated successfully; apply them with your wallpaper manager."

while (( $# >= 2 )); do
    output="$1"
    file="$2"
    shift 2

    [[ -n "$output" ]] || die "Missing monitor output name."
    [[ -f "$file" ]] || die "Generated wallpaper does not exist: $file"

    quickshell -p "$SERPANTINUM_SHELL" \
        ipc call wallpaper setWallpaper "$output" "$file" fade
done

printf 'Wallpapers applied through Serpantinum.\n'

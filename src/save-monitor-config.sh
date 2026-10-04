#!/usr/bin/env bash
set -euo pipefail

# Hunu Wallpaper Splitter — monitor setup config writer.
# Receives already validated GUI values and writes config.conf atomically.
#
# The destination is supplied explicitly with --config. This lets the same
# helper work from the source tree, normal installs, isolated test installs,
# and custom XDG config locations without guessing paths.

CONFIG_PATH=""

M1_OUTPUT=""; M1_WIDTH=""; M1_HEIGHT=""; M1_PW=""; M1_PH=""; M1_X=""; M1_Y=""
M2_OUTPUT=""; M2_WIDTH=""; M2_HEIGHT=""; M2_PW=""; M2_PH=""; M2_X=""; M2_Y=""
M3_OUTPUT=""; M3_WIDTH=""; M3_HEIGHT=""; M3_PW=""; M3_PH=""; M3_X=""; M3_Y=""

while (($#)); do
    case "$1" in
        --config) CONFIG_PATH="$2"; shift 2 ;;
        --m1-output) M1_OUTPUT="$2"; shift 2 ;;
        --m1-width) M1_WIDTH="$2"; shift 2 ;;
        --m1-height) M1_HEIGHT="$2"; shift 2 ;;
        --m1-physical-width) M1_PW="$2"; shift 2 ;;
        --m1-physical-height) M1_PH="$2"; shift 2 ;;
        --m1-x) M1_X="$2"; shift 2 ;;
        --m1-y) M1_Y="$2"; shift 2 ;;
        --m2-output) M2_OUTPUT="$2"; shift 2 ;;
        --m2-width) M2_WIDTH="$2"; shift 2 ;;
        --m2-height) M2_HEIGHT="$2"; shift 2 ;;
        --m2-physical-width) M2_PW="$2"; shift 2 ;;
        --m2-physical-height) M2_PH="$2"; shift 2 ;;
        --m2-x) M2_X="$2"; shift 2 ;;
        --m2-y) M2_Y="$2"; shift 2 ;;
        --m3-output) M3_OUTPUT="$2"; shift 2 ;;
        --m3-width) M3_WIDTH="$2"; shift 2 ;;
        --m3-height) M3_HEIGHT="$2"; shift 2 ;;
        --m3-physical-width) M3_PW="$2"; shift 2 ;;
        --m3-physical-height) M3_PH="$2"; shift 2 ;;
        --m3-x) M3_X="$2"; shift 2 ;;
        --m3-y) M3_Y="$2"; shift 2 ;;
        *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ -n "$CONFIG_PATH" ]] || {
    echo "ERROR: --config PATH is required." >&2
    exit 2
}

[[ -n "$M1_OUTPUT" ]] || {
    echo "ERROR: Monitor 1 is required." >&2
    exit 2
}

WALLPAPER_OUTPUT_DIR="$HOME/Pictures/Wallpapers"

if [[ -f "$CONFIG_PATH" ]]; then
    WALLPAPER_OUTPUT_DIR="$(
        unset OUTPUT_DIR
        source "$CONFIG_PATH"
        printf '%s' "${OUTPUT_DIR:-$HOME/Pictures/Wallpapers}"
    )"
fi

SAVED_APPLY_BACKEND="serpantinum"

if [[ -f "$CONFIG_PATH" ]]; then
    SAVED_APPLY_BACKEND="$(
        unset APPLY_BACKEND
        source "$CONFIG_PATH"
        printf '%s' "${APPLY_BACKEND:-serpantinum}"
    )"
fi

case "$SAVED_APPLY_BACKEND" in
    serpantinum|hyprpaper|awww) ;;
    *) SAVED_APPLY_BACKEND="serpantinum" ;;
esac

OUTPUT_DIR="$(dirname -- "$CONFIG_PATH")"
mkdir -p "$OUTPUT_DIR"

target="$CONFIG_PATH"
tmp="$(mktemp "$OUTPUT_DIR/.config.conf.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

write_monitor() {
    local n="$1" enabled="$2" output="$3" width="$4" height="$5" pw="$6" ph="$7" x="$8" y="$9"
    {
        echo
        echo "# Monitor $n"
        printf 'MONITOR_%s_ENABLED=%s\n' "$n" "$enabled"
        printf 'MONITOR_%s_OUTPUT="%s"\n' "$n" "$output"
        printf 'MONITOR_%s_WIDTH=%s\n' "$n" "${width:-1920}"
        printf 'MONITOR_%s_HEIGHT=%s\n' "$n" "${height:-1080}"
        printf 'MONITOR_%s_PHYSICAL_WIDTH_CM=%s\n' "$n" "${pw:-60}"
        printf 'MONITOR_%s_PHYSICAL_HEIGHT_CM=%s\n' "$n" "${ph:-34}"
        printf 'MONITOR_%s_X_CM=%s\n' "$n" "${x:-0}"
        printf 'MONITOR_%s_Y_CM=%s\n' "$n" "${y:-0}"
    } >> "$tmp"
}

{
    echo '# Hunu Wallpaper Splitter — generated monitor configuration'
    echo '# Physical measurements include monitor bezels.'
    echo
    echo '# General'
    printf 'OUTPUT_DIR=%q\n' "$WALLPAPER_OUTPUT_DIR"
    printf 'APPLY_BACKEND=%q\n' "$SAVED_APPLY_BACKEND"
} > "$tmp"

write_monitor 1 true "$M1_OUTPUT" "$M1_WIDTH" "$M1_HEIGHT" "$M1_PW" "$M1_PH" "$M1_X" "$M1_Y"

if [[ -n "$M2_OUTPUT" ]]; then
    write_monitor 2 true "$M2_OUTPUT" "$M2_WIDTH" "$M2_HEIGHT" "$M2_PW" "$M2_PH" "$M2_X" "$M2_Y"
else
    write_monitor 2 false "" 1920 1080 60 34 0 0
fi

if [[ -n "$M3_OUTPUT" ]]; then
    write_monitor 3 true "$M3_OUTPUT" "$M3_WIDTH" "$M3_HEIGHT" "$M3_PW" "$M3_PH" "$M3_X" "$M3_Y"
else
    write_monitor 3 false "" 1920 1080 60 34 0 0
fi

mv "$tmp" "$target"
trap - EXIT

printf 'Saved monitor setup to %s\n' "$target"

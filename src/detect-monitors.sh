#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Hunu Wallpaper Splitter - Hyprland monitor detector
#
# Reads Hyprland's monitor information and exposes a small,
# stable KEY=value interface for the QML setup screen.
#
# Hyprland reports the untransformed display mode. For quarter-
# turn transforms (1, 3, 5, 7), wallpaper width and height are
# swapped so the GUI sees the monitor as the user sees it.
#
# EDID physical dimensions are included only as a suggested
# starting point. Linked mode should use the user's real
# bezel-to-bezel measurements.
# ============================================================

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command -v hyprctl >/dev/null 2>&1 \
    || die "hyprctl was not found."

command -v jq >/dev/null 2>&1 \
    || die "jq was not found. Install jq to detect monitors."

MONITORS_JSON="$(hyprctl monitors -j)" \
    || die "Could not query Hyprland monitors."

COUNT="$(
    jq '[.[] | select(.disabled != true and .mirrorOf == "none")] | length' \
        <<< "$MONITORS_JSON"
)"

[[ "$COUNT" =~ ^[0-9]+$ ]] \
    || die "Could not determine monitor count."

(( COUNT > 0 )) \
    || die "Hyprland reports no active monitors."

# Hunu Wallpaper intentionally supports at most three monitors.
# We still report the real detected count so the GUI can explain
# the limitation instead of silently hiding additional displays.
printf 'DETECTED_COUNT=%s\n' "$COUNT"

if (( COUNT > 3 )); then
    printf 'SUPPORTED_COUNT=3\n'
    printf 'HAS_EXTRA_MONITORS=true\n'
else
    printf 'SUPPORTED_COUNT=%s\n' "$COUNT"
    printf 'HAS_EXTRA_MONITORS=false\n'
fi

jq -c '
    [
        .[]
        | select(.disabled != true and .mirrorOf == "none")
    ]
    | to_entries[]
    | select(.key < 3)
    | {
        slot: (.key + 1),
        name: .value.name,
        description: .value.description,
        make: .value.make,
        model: .value.model,
        modeWidth: .value.width,
        modeHeight: .value.height,
        physicalWidthMm: .value.physicalWidth,
        physicalHeightMm: .value.physicalHeight,
        refreshRate: .value.refreshRate,
        x: .value.x,
        y: .value.y,
        scale: .value.scale,
        transform: .value.transform,
        focused: .value.focused
    }
' <<< "$MONITORS_JSON" |
while IFS= read -r monitor; do
    slot="$(jq -r '.slot' <<< "$monitor")"
    transform="$(jq -r '.transform' <<< "$monitor")"

    mode_width="$(jq -r '.modeWidth' <<< "$monitor")"
    mode_height="$(jq -r '.modeHeight' <<< "$monitor")"

    physical_width_mm="$(jq -r '.physicalWidthMm' <<< "$monitor")"
    physical_height_mm="$(jq -r '.physicalHeightMm' <<< "$monitor")"

    # Hyprland transforms 1/3/5/7 represent quarter-turn
    # orientations. Swap dimensions for the displayed result.
    case "$transform" in
        1|3|5|7)
            wallpaper_width="$mode_height"
            wallpaper_height="$mode_width"

            suggested_width_mm="$physical_height_mm"
            suggested_height_mm="$physical_width_mm"

            orientation="portrait"
            ;;
        *)
            wallpaper_width="$mode_width"
            wallpaper_height="$mode_height"

            suggested_width_mm="$physical_width_mm"
            suggested_height_mm="$physical_height_mm"

            if (( wallpaper_height > wallpaper_width )); then
                orientation="portrait"
            elif (( wallpaper_width > wallpaper_height )); then
                orientation="landscape"
            else
                orientation="square"
            fi
            ;;
    esac

    suggested_width_cm="$(
        awk -v mm="$suggested_width_mm" \
            'BEGIN { printf "%.1f", mm / 10 }'
    )"

    suggested_height_cm="$(
        awk -v mm="$suggested_height_mm" \
            'BEGIN { printf "%.1f", mm / 10 }'
    )"

    refresh="$(
        jq -r '.refreshRate' <<< "$monitor" |
        awk '{ printf "%.2f", $1 }'
    )"

    printf 'MONITOR_%s_NAME=%s\n' \
        "$slot" "$(jq -r '.name' <<< "$monitor")"

    printf 'MONITOR_%s_DESCRIPTION=%s\n' \
        "$slot" "$(jq -r '.description' <<< "$monitor")"

    printf 'MONITOR_%s_MAKE=%s\n' \
        "$slot" "$(jq -r '.make' <<< "$monitor")"

    printf 'MONITOR_%s_MODEL=%s\n' \
        "$slot" "$(jq -r '.model' <<< "$monitor")"

    printf 'MONITOR_%s_WIDTH=%s\n' \
        "$slot" "$wallpaper_width"

    printf 'MONITOR_%s_HEIGHT=%s\n' \
        "$slot" "$wallpaper_height"

    printf 'MONITOR_%s_ORIENTATION=%s\n' \
        "$slot" "$orientation"

    printf 'MONITOR_%s_TRANSFORM=%s\n' \
        "$slot" "$transform"

    printf 'MONITOR_%s_REFRESH=%s\n' \
        "$slot" "$refresh"

    printf 'MONITOR_%s_SCALE=%s\n' \
        "$slot" "$(jq -r '.scale' <<< "$monitor")"

    printf 'MONITOR_%s_HYPR_X=%s\n' \
        "$slot" "$(jq -r '.x' <<< "$monitor")"

    printf 'MONITOR_%s_HYPR_Y=%s\n' \
        "$slot" "$(jq -r '.y' <<< "$monitor")"

    printf 'MONITOR_%s_SUGGESTED_PHYSICAL_WIDTH_CM=%s\n' \
        "$slot" "$suggested_width_cm"

    printf 'MONITOR_%s_SUGGESTED_PHYSICAL_HEIGHT_CM=%s\n' \
        "$slot" "$suggested_height_cm"

    printf 'MONITOR_%s_FOCUSED=%s\n' \
        "$slot" "$(jq -r '.focused' <<< "$monitor")"
done

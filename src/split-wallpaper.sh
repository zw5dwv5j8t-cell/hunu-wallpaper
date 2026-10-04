#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Hunu Wallpaper Splitter - public backend
#
# Supports 1 to 3 monitors. Monitor numbers are logical slots,
# not physical left/right positions.
#
# Physical geometry is read from config.conf. Wallpaper offsets
# are runtime adjustments and do not change monitor placement.
#
# Usage:
#   split-wallpaper.sh IMAGE [options]
#
# Options:
#   --config PATH
#   --mode linked|quality
#   --probe
#   --monitor-1-x N   --monitor-1-y N
#   --monitor-2-x N   --monitor-2-y N
#   --monitor-3-x N   --monitor-3-y N
#
# Wallpaper offsets are integer pixels/layout units:
#   positive X = move image left
#   negative X = move image right
#   positive Y = move image up
#   negative Y = move image down
# ============================================================

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

is_integer() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

is_number() {
    [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_positive_number() {
    awk -v v="$1" 'BEGIN { exit !(v ~ /^[0-9]+([.][0-9]+)?$/ && v > 0) }'
}

clamp() {
    local value="$1" min="$2" max="$3"
    if (( value < min )); then
        printf '%s\n' "$min"
    elif (( value > max )); then
        printf '%s\n' "$max"
    else
        printf '%s\n' "$value"
    fi
}

cm_to_units() {
    awk -v cm="$1" -v unit="$PHYS_UNIT" 'BEGIN { printf "%.0f", cm * unit }'
}

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

[[ $# -ge 1 ]] || die "Usage: $0 IMAGE [options]"

SOURCE="$1"
shift

MODE="linked"
PROBE=false
CONFIG_PATH=""

declare -a OFFSET_X=(0 0 0 0)
declare -a OFFSET_Y=(0 0 0 0)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            [[ $# -ge 2 ]] || die "--config requires a path."
            CONFIG_PATH="$2"
            shift 2
            ;;
        --mode)
            [[ $# -ge 2 ]] || die "--mode requires linked or quality."
            MODE="$2"
            shift 2
            ;;
        --probe)
            PROBE=true
            shift
            ;;
        --monitor-1-x|--monitor-2-x|--monitor-3-x)
            [[ $# -ge 2 ]] || die "$1 requires an integer."
            slot="${1:10:1}"
            OFFSET_X[$slot]="$2"
            shift 2
            ;;
        --monitor-1-y|--monitor-2-y|--monitor-3-y)
            [[ $# -ge 2 ]] || die "$1 requires an integer."
            slot="${1:10:1}"
            OFFSET_Y[$slot]="$2"
            shift 2
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

[[ "$MODE" == "linked" || "$MODE" == "quality" ]] \
    || die "Mode must be 'linked' or 'quality'."

for i in 1 2 3; do
    is_integer "${OFFSET_X[$i]}" || die "Monitor $i X wallpaper offset must be an integer."
    is_integer "${OFFSET_Y[$i]}" || die "Monitor $i Y wallpaper offset must be an integer."
done

[[ -f "$SOURCE" ]] || die "Source image does not exist: $SOURCE"
command -v magick >/dev/null 2>&1 || die "ImageMagick 'magick' was not found."
command -v awk >/dev/null 2>&1 || die "'awk' was not found."

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$CONFIG_PATH" ]]; then
    if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
        CONFIG_PATH="$SCRIPT_DIR/config.conf"
    elif [[ -f "$SCRIPT_DIR/../config/config.conf" ]]; then
        CONFIG_PATH="$SCRIPT_DIR/../config/config.conf"
    elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/hunu-wallpaper/config.conf" ]]; then
        CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/hunu-wallpaper/config.conf"
    else
        die "No config.conf found. Copy config/config.example.conf to config/config.conf or pass --config PATH."
    fi
fi

[[ -f "$CONFIG_PATH" ]] || die "Config file does not exist: $CONFIG_PATH"

# config.conf is intentionally a Bash-style KEY=value file.
# It is sourced so values such as "$HOME/Pictures/Wallpapers" expand
# naturally. Public documentation must treat config files as trusted
# local configuration, not files downloaded from untrusted sources.
# shellcheck disable=SC1090
source "$CONFIG_PATH"

OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Pictures/Wallpapers}"
PHYS_UNIT=100

declare -a ENABLED OUTPUT PIXEL_W PIXEL_H
declare -a PHYS_W_CM PHYS_H_CM RAW_X_CM RAW_Y_CM
declare -a PHYS_X PHYS_Y PHYS_W PHYS_H
declare -a OUTPUT_FILE OUTPUT_SUFFIX

for i in 1 2 3; do
    enabled_var="MONITOR_${i}_ENABLED"
    output_var="MONITOR_${i}_OUTPUT"
    width_var="MONITOR_${i}_WIDTH"
    height_var="MONITOR_${i}_HEIGHT"
    phys_w_var="MONITOR_${i}_PHYSICAL_WIDTH_CM"
    phys_h_var="MONITOR_${i}_PHYSICAL_HEIGHT_CM"
    x_var="MONITOR_${i}_X_CM"
    y_var="MONITOR_${i}_Y_CM"

    ENABLED[$i]="${!enabled_var:-false}"
    OUTPUT[$i]="${!output_var:-}"
    PIXEL_W[$i]="${!width_var:-}"
    PIXEL_H[$i]="${!height_var:-}"
    PHYS_W_CM[$i]="${!phys_w_var:-}"
    PHYS_H_CM[$i]="${!phys_h_var:-}"
    RAW_X_CM[$i]="${!x_var:-}"
    RAW_Y_CM[$i]="${!y_var:-}"
done

[[ "${ENABLED[1]}" == "true" ]] || die "Monitor 1 must be enabled."

declare -a ACTIVE=()
declare -A SEEN_OUTPUT=()

for i in 1 2 3; do
    case "${ENABLED[$i]}" in
        true)
            ;;
        false)
            continue
            ;;
        *)
            die "Monitor $i ENABLED must be true or false."
            ;;
    esac

    [[ -n "${OUTPUT[$i]}" ]] || die "Monitor $i is enabled but has no output assigned."
    is_positive_integer "${PIXEL_W[$i]}" || die "Monitor $i WIDTH must be a positive integer."
    is_positive_integer "${PIXEL_H[$i]}" || die "Monitor $i HEIGHT must be a positive integer."
    is_positive_number "${PHYS_W_CM[$i]}" || die "Monitor $i physical width must be greater than 0 cm."
    is_positive_number "${PHYS_H_CM[$i]}" || die "Monitor $i physical height must be greater than 0 cm."
    is_number "${RAW_X_CM[$i]}" || die "Monitor $i X position must be a number in centimetres."
    is_number "${RAW_Y_CM[$i]}" || die "Monitor $i Y position must be a number in centimetres."

    [[ -z "${SEEN_OUTPUT[${OUTPUT[$i]}]:-}" ]] \
        || die "Output '${OUTPUT[$i]}' is assigned to more than one monitor."

    SEEN_OUTPUT["${OUTPUT[$i]}"]=1
    ACTIVE+=("$i")
done

MONITOR_COUNT="${#ACTIVE[@]}"
(( MONITOR_COUNT >= 1 && MONITOR_COUNT <= 3 )) || die "Between 1 and 3 monitors must be enabled."

# ------------------------------------------------------------
# Physical layout
# ------------------------------------------------------------
#
# 100 integer layout units = 1 cm. Integer geometry avoids
# accumulating floating-point rounding errors during crop math.
#
# Configured X/Y values may be negative. We first find the complete
# bounding rectangle, then normalize every monitor so the canvas
# begins at (0,0). This means no monitor is inherently "left",
# "right", "main", or the origin.
# ------------------------------------------------------------

min_x=""
min_y=""
max_right=""
max_bottom=""

declare -a RAW_X RAW_Y

for i in "${ACTIVE[@]}"; do
    RAW_X[$i]="$(cm_to_units "${RAW_X_CM[$i]}")"
    RAW_Y[$i]="$(cm_to_units "${RAW_Y_CM[$i]}")"
    PHYS_W[$i]="$(cm_to_units "${PHYS_W_CM[$i]}")"
    PHYS_H[$i]="$(cm_to_units "${PHYS_H_CM[$i]}")"

    right=$(( RAW_X[$i] + PHYS_W[$i] ))
    bottom=$(( RAW_Y[$i] + PHYS_H[$i] ))

    if [[ -z "$min_x" ]] || (( RAW_X[$i] < min_x )); then min_x="${RAW_X[$i]}"; fi
    if [[ -z "$min_y" ]] || (( RAW_Y[$i] < min_y )); then min_y="${RAW_Y[$i]}"; fi
    if [[ -z "$max_right" ]] || (( right > max_right )); then max_right="$right"; fi
    if [[ -z "$max_bottom" ]] || (( bottom > max_bottom )); then max_bottom="$bottom"; fi
done

DESKTOP_W=$(( max_right - min_x ))
DESKTOP_H=$(( max_bottom - min_y ))

(( DESKTOP_W > 0 && DESKTOP_H > 0 )) || die "Calculated physical desktop has an invalid size."

for i in "${ACTIVE[@]}"; do
    PHYS_X[$i]=$(( RAW_X[$i] - min_x ))
    PHYS_Y[$i]=$(( RAW_Y[$i] - min_y ))
done

# ------------------------------------------------------------
# Output set numbering
# ------------------------------------------------------------

mkdir -p "$OUTPUT_DIR"

suffix_for_slot() {
    case "$1" in
        1) printf 'a\n' ;;
        2) printf 'b\n' ;;
        3) printf 'c\n' ;;
        *) return 1 ;;
    esac
}

PAIR=1
while true; do
    PREFIX="$(printf '%03d' "$PAIR")"
    collision=false

    # A set number is occupied if ANY Hunu slot file already exists,
    # even when that slot is disabled in the current monitor setup.
    # This prevents stale files such as 003_c.png from being mixed with
    # a newly generated 003_a.png / 003_b.png two-monitor set.
    for suffix in a b c; do
        candidate="$OUTPUT_DIR/${PREFIX}_${suffix}.png"
        if [[ -e "$candidate" ]]; then
            collision=true
            break
        fi
    done

    [[ "$collision" == false ]] && break
    PAIR=$((PAIR + 1))
done

for i in "${ACTIVE[@]}"; do
    OUTPUT_SUFFIX[$i]="$(suffix_for_slot "$i")"
    OUTPUT_FILE[$i]="$OUTPUT_DIR/${PREFIX}_${OUTPUT_SUFFIX[$i]}.png"
done

# ------------------------------------------------------------
# Source dimensions
# ------------------------------------------------------------

read -r SRC_W SRC_H < <(magick identify -format '%w %h\n' "$SOURCE")
is_positive_integer "$SRC_W" || die "Could not determine source image width."
is_positive_integer "$SRC_H" || die "Could not determine source image height."

# ------------------------------------------------------------
# Probe helpers
# ------------------------------------------------------------

probe_common() {
    printf 'MONITOR_COUNT=%s\n' "$MONITOR_COUNT"
    printf 'SOURCE_W=%s\n' "$SRC_W"
    printf 'SOURCE_H=%s\n' "$SRC_H"

    for i in "${ACTIVE[@]}"; do
        printf 'MONITOR_%s_ENABLED=true\n' "$i"
        printf 'MONITOR_%s_OUTPUT=%s\n' "$i" "${OUTPUT[$i]}"
        printf 'MONITOR_%s_WIDTH=%s\n' "$i" "${PIXEL_W[$i]}"
        printf 'MONITOR_%s_HEIGHT=%s\n' "$i" "${PIXEL_H[$i]}"
    done
}

recommended_scale_for_dimensions() {
    local required_w="$1"
    local required_h="$2"

    awk -v sw="$SRC_W" -v sh="$SRC_H" -v rw="$required_w" -v rh="$required_h" '
        BEGIN {
            scale_w = rw / sw
            scale_h = rh / sh
            scale = (scale_w > scale_h ? scale_w : scale_h)

            if (scale <= 1.0)
                print 1
            else if (scale <= 2.0)
                print 2
            else if (scale <= 3.0)
                print 3
            else if (scale <= 4.0)
                print 4
            else
                print 0
        }'
}

linked_quality_probe() {
    local max_ppu="0"
    local ideal_w ideal_h recommended sufficient

    # Determine the highest pixel density required by any active monitor.
    #
    # PHYS_W / PHYS_H use the same physical units as DESKTOP_W/H, so
    # PIXEL_W / PHYS_W and PIXEL_H / PHYS_H are pixels per physical unit.
    for i in "${ACTIVE[@]}"; do
        max_ppu="$(
            awk \
                -v current="$max_ppu" \
                -v pw="${PIXEL_W[$i]}" \
                -v ph="${PIXEL_H[$i]}" \
                -v physw="${PHYS_W[$i]}" \
                -v physh="${PHYS_H[$i]}" '
                BEGIN {
                    x = pw / physw
                    y = ph / physh
                    candidate = (x > y ? x : y)
                    print (candidate > current ? candidate : current)
                }'
        )"
    done

    ideal_w="$(awk -v d="$DESKTOP_W" -v p="$max_ppu" \
        'BEGIN { printf "%.0f", d * p }')"
    ideal_h="$(awk -v d="$DESKTOP_H" -v p="$max_ppu" \
        'BEGIN { printf "%.0f", d * p }')"

    recommended="$(recommended_scale_for_dimensions "$ideal_w" "$ideal_h")"

    if awk -v sw="$SRC_W" -v sh="$SRC_H" -v iw="$ideal_w" -v ih="$ideal_h" \
        'BEGIN { exit !(sw >= iw && sh >= ih) }'
    then
        sufficient=true
    else
        sufficient=false
    fi

    printf 'IDEAL_W=%s\n' "$ideal_w"
    printf 'IDEAL_H=%s\n' "$ideal_h"
    printf 'SOURCE_SUFFICIENT=%s\n' "$sufficient"
    printf 'RECOMMENDED_SCALE=%s\n' "$recommended"
}

linked_scale() {
    awk -v sw="$SRC_W" -v sh="$SRC_H" -v dw="$DESKTOP_W" -v dh="$DESKTOP_H" '
        BEGIN {
            sx = dw / sw
            sy = dh / sh
            print (sx > sy ? sx : sy)
        }'
}

probe_linked() {
    local scale scaled_w scaled_h base_x base_y
    scale="$(linked_scale)"
    scaled_w="$(awk -v w="$SRC_W" -v s="$scale" 'BEGIN { printf "%.0f", w * s }')"
    scaled_h="$(awk -v h="$SRC_H" -v s="$scale" 'BEGIN { printf "%.0f", h * s }')"
    base_x=$(( (scaled_w - DESKTOP_W) / 2 ))
    base_y=$(( (scaled_h - DESKTOP_H) / 2 ))

    probe_common
    linked_quality_probe
    printf 'DESKTOP_W=%s\n' "$DESKTOP_W"
    printf 'DESKTOP_H=%s\n' "$DESKTOP_H"
    printf 'PREVIEW_W=%s\n' "$scaled_w"
    printf 'PREVIEW_H=%s\n' "$scaled_h"

    for i in "${ACTIVE[@]}"; do
        local min_dx max_dx min_dy max_dy
        min_dx=$(( -base_x - PHYS_X[$i] ))
        max_dx=$(( scaled_w - PHYS_W[$i] - base_x - PHYS_X[$i] ))
        min_dy=$(( -base_y - PHYS_Y[$i] ))
        max_dy=$(( scaled_h - PHYS_H[$i] - base_y - PHYS_Y[$i] ))

        printf 'MONITOR_%s_PHYS_X=%s\n' "$i" "${PHYS_X[$i]}"
        printf 'MONITOR_%s_PHYS_Y=%s\n' "$i" "${PHYS_Y[$i]}"
        printf 'MONITOR_%s_PHYS_W=%s\n' "$i" "${PHYS_W[$i]}"
        printf 'MONITOR_%s_PHYS_H=%s\n' "$i" "${PHYS_H[$i]}"
        printf 'MONITOR_%s_CROP_W=%s\n' "$i" "${PHYS_W[$i]}"
        printf 'MONITOR_%s_CROP_H=%s\n' "$i" "${PHYS_H[$i]}"
        printf 'MONITOR_%s_BASE_X=%s\n' "$i" "$(( base_x + PHYS_X[$i] ))"
        printf 'MONITOR_%s_BASE_Y=%s\n' "$i" "$(( base_y + PHYS_Y[$i] ))"
        printf 'MONITOR_%s_X_MIN=%s\n' "$i" "$min_dx"
        printf 'MONITOR_%s_X_MAX=%s\n' "$i" "$max_dx"
        printf 'MONITOR_%s_Y_MIN=%s\n' "$i" "$min_dy"
        printf 'MONITOR_%s_Y_MAX=%s\n' "$i" "$max_dy"
    done
}

quality_geometry() {
    local target_w="$1" target_h="$2"
    awk -v sw="$SRC_W" -v sh="$SRC_H" -v tw="$target_w" -v th="$target_h" '
        BEGIN {
            source_ratio = sw / sh
            target_ratio = tw / th

            if (source_ratio > target_ratio) {
                crop_h = sh
                crop_w = sh * target_ratio
            } else {
                crop_w = sw
                crop_h = sw / target_ratio
            }

            printf "%.0f %.0f\n", crop_w, crop_h
        }'
}

quality_required_dimensions() {
    local required_w=0
    local required_h=0

    # Maximum Quality creates an independent crop for every monitor.
    #
    # For each monitor, determine how large the source must be to contain
    # a crop with the monitor's aspect ratio at native output resolution.
    # The final requirement must satisfy every active monitor.
    for i in "${ACTIVE[@]}"; do
        local target_w="${PIXEL_W[$i]}"
        local target_h="${PIXEL_H[$i]}"
        local needed_w needed_h

        read -r needed_w needed_h < <(
            awk \
                -v sw="$SRC_W" \
                -v sh="$SRC_H" \
                -v tw="$target_w" \
                -v th="$target_h" '
                BEGIN {
                    source_ratio = sw / sh
                    target_ratio = tw / th

                    if (source_ratio > target_ratio) {
                        needed_w = tw * (source_ratio / target_ratio)
                        needed_h = th
                    } else {
                        needed_w = tw
                        needed_h = th * (target_ratio / source_ratio)
                    }

                    printf "%.0f %.0f\n", needed_w, needed_h
                }'
        )

        (( needed_w > required_w )) && required_w="$needed_w"
        (( needed_h > required_h )) && required_h="$needed_h"
    done

    printf '%s %s\n' "$required_w" "$required_h"
}

quality_quality_probe() {
    local ideal_w ideal_h recommended sufficient

    read -r ideal_w ideal_h < <(quality_required_dimensions)

    recommended="$(recommended_scale_for_dimensions "$ideal_w" "$ideal_h")"

    if (( SRC_W >= ideal_w && SRC_H >= ideal_h )); then
        sufficient=true
    else
        sufficient=false
    fi

    printf 'IDEAL_W=%s\n' "$ideal_w"
    printf 'IDEAL_H=%s\n' "$ideal_h"
    printf 'SOURCE_SUFFICIENT=%s\n' "$sufficient"
    printf 'RECOMMENDED_SCALE=%s\n' "$recommended"
}

probe_quality() {
    probe_common
    quality_quality_probe
    printf 'PREVIEW_W=%s\n' "$SRC_W"
    printf 'PREVIEW_H=%s\n' "$SRC_H"

    for i in "${ACTIVE[@]}"; do
        local crop_w crop_h center_x center_y
        read -r crop_w crop_h < <(quality_geometry "${PIXEL_W[$i]}" "${PIXEL_H[$i]}")
        center_x=$(( (SRC_W - crop_w) / 2 ))
        center_y=$(( (SRC_H - crop_h) / 2 ))

        printf 'MONITOR_%s_CROP_W=%s\n' "$i" "$crop_w"
        printf 'MONITOR_%s_CROP_H=%s\n' "$i" "$crop_h"
        printf 'MONITOR_%s_BASE_X=%s\n' "$i" "$center_x"
        printf 'MONITOR_%s_BASE_Y=%s\n' "$i" "$center_y"
        printf 'MONITOR_%s_X_MIN=%s\n' "$i" "$((-center_x))"
        printf 'MONITOR_%s_X_MAX=%s\n' "$i" "$((SRC_W - crop_w - center_x))"
        printf 'MONITOR_%s_Y_MIN=%s\n' "$i" "$((-center_y))"
        printf 'MONITOR_%s_Y_MAX=%s\n' "$i" "$((SRC_H - crop_h - center_y))"
    done
}

if [[ "$PROBE" == true ]]; then
    case "$MODE" in
        linked) probe_linked ;;
        quality) probe_quality ;;
    esac
    exit 0
fi

# ------------------------------------------------------------
# Linked mode
# ------------------------------------------------------------

linked_mode() {
    local scale scaled_w scaled_h base_x base_y tmp
    scale="$(linked_scale)"
    scaled_w="$(awk -v w="$SRC_W" -v s="$scale" 'BEGIN { printf "%.0f", w * s }')"
    scaled_h="$(awk -v h="$SRC_H" -v s="$scale" 'BEGIN { printf "%.0f", h * s }')"
    base_x=$(( (scaled_w - DESKTOP_W) / 2 ))
    base_y=$(( (scaled_h - DESKTOP_H) / 2 ))

    tmp="$OUTPUT_DIR/.hunu-linked-working-$$.png"
    trap 'rm -f -- "$tmp"' EXIT

    magick "$SOURCE" -resize "${scaled_w}x${scaled_h}!" "$tmp"

    for i in "${ACTIVE[@]}"; do
        local min_dx max_dx min_dy max_dy dx dy crop_x crop_y
        min_dx=$(( -base_x - PHYS_X[$i] ))
        max_dx=$(( scaled_w - PHYS_W[$i] - base_x - PHYS_X[$i] ))
        min_dy=$(( -base_y - PHYS_Y[$i] ))
        max_dy=$(( scaled_h - PHYS_H[$i] - base_y - PHYS_Y[$i] ))

        dx="$(clamp "${OFFSET_X[$i]}" "$min_dx" "$max_dx")"
        dy="$(clamp "${OFFSET_Y[$i]}" "$min_dy" "$max_dy")"

        crop_x=$(( base_x + PHYS_X[$i] + dx ))
        crop_y=$(( base_y + PHYS_Y[$i] + dy ))

        magick "$tmp" \
            -crop "${PHYS_W[$i]}x${PHYS_H[$i]}+${crop_x}+${crop_y}" \
            +repage \
            -resize "${PIXEL_W[$i]}x${PIXEL_H[$i]}!" \
            "${OUTPUT_FILE[$i]}"
    done

    rm -f -- "$tmp"
    trap - EXIT
}

# ------------------------------------------------------------
# Maximum-quality mode
# ------------------------------------------------------------

quality_monitor() {
    local i="$1"
    local crop_w crop_h center_x center_y min_dx max_dx min_dy max_dy
    local dx dy crop_x crop_y

    read -r crop_w crop_h < <(quality_geometry "${PIXEL_W[$i]}" "${PIXEL_H[$i]}")

    center_x=$(( (SRC_W - crop_w) / 2 ))
    center_y=$(( (SRC_H - crop_h) / 2 ))

    min_dx=$(( -center_x ))
    max_dx=$(( SRC_W - crop_w - center_x ))
    min_dy=$(( -center_y ))
    max_dy=$(( SRC_H - crop_h - center_y ))

    dx="$(clamp "${OFFSET_X[$i]}" "$min_dx" "$max_dx")"
    dy="$(clamp "${OFFSET_Y[$i]}" "$min_dy" "$max_dy")"

    crop_x=$(( center_x + dx ))
    crop_y=$(( center_y + dy ))

    # Crop the original source first, then resize once. This preserves
    # as much source detail as possible for an independent monitor.
    magick "$SOURCE" \
        -crop "${crop_w}x${crop_h}+${crop_x}+${crop_y}" \
        +repage \
        -resize "${PIXEL_W[$i]}x${PIXEL_H[$i]}!" \
        "${OUTPUT_FILE[$i]}"
}

quality_mode() {
    for i in "${ACTIVE[@]}"; do
        quality_monitor "$i"
    done
}

case "$MODE" in
    linked) linked_mode ;;
    quality) quality_mode ;;
esac

# ------------------------------------------------------------
# Machine-readable result
# ------------------------------------------------------------

printf 'RESULT=OK\n'
printf 'PAIR=%s\n' "$PREFIX"
printf 'MONITOR_COUNT=%s\n' "$MONITOR_COUNT"

for i in "${ACTIVE[@]}"; do
    printf 'MONITOR_%s_OUTPUT_NAME=%s\n' "$i" "${OUTPUT[$i]}"
    printf 'MONITOR_%s_FILE=%s\n' "$i" "${OUTPUT_FILE[$i]}"
done

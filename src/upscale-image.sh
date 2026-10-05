#!/usr/bin/env bash
set -euo pipefail

INPUT=""
OUTPUT=""
SCALE="4"
MODEL="realesrgan-x4plus"
USE_CACHE=false

usage() {
    cat <<'EOF'
Usage:
  upscale-image.sh --input FILE [--output FILE] [options]

Options:
  --input FILE     Source image
  --output FILE    Upscaled image (default: Hunu cache)
  --scale N        Upscale factor: 2, 3, or 4 (default: 4)
  --model NAME     Real-ESRGAN model (default: realesrgan-x4plus)
  --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            INPUT="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT="${2:-}"
            shift 2
            ;;
        --scale)
            SCALE="${2:-}"
            shift 2
            ;;
        --model)
            MODEL="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    echo "ERROR: --input is required." >&2
    exit 2
fi

if [[ -z "$OUTPUT" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/cache-path.sh"
    CACHE_DIR="$(hunu_cache_directory)"
    USE_CACHE=true
fi

if [[ ! -f "$INPUT" ]]; then
    echo "ERROR: Input image does not exist: $INPUT" >&2
    exit 1
fi

if [[ "$INPUT" -ef "$OUTPUT" ]]; then
    echo "ERROR: Input and output refer to the same file. Source image was left untouched." >&2
    exit 2
fi

if ! command -v realesrgan-ncnn-vulkan >/dev/null 2>&1; then
    echo "ERROR: realesrgan-ncnn-vulkan is not installed." >&2
    exit 127
fi

case "$SCALE" in
    2|3|4) ;;
    *)
        echo "ERROR: --scale must be 2, 3, or 4." >&2
        exit 2
        ;;
esac

if [[ "$USE_CACHE" == true ]]; then
    for cmd in sha256sum flock magick; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "ERROR: Required cache tool was not found: $cmd" >&2
            exit 127
        }
    done

    # Cache clearing takes an exclusive lock on this same file.
    mkdir -p -- "$CACHE_DIR"
    exec 8>"$CACHE_DIR/.hunu-cache.lock"
    flock -s 8

    SOURCE_HASH="$(sha256sum < "$INPUT")"
    SOURCE_HASH="${SOURCE_HASH%% *}"

    HELPER_HASH="$(sha256sum < "${BASH_SOURCE[0]}")"
    HELPER_HASH="${HELPER_HASH%% *}"

    CACHE_KEY="$(
        printf '%s\0' "$SOURCE_HASH" "$SCALE" "$MODEL" "$HELPER_HASH" |
            sha256sum
    )"
    CACHE_KEY="${CACHE_KEY%% *}"
    OUTPUT="$CACHE_DIR/upscaled-$CACHE_KEY.png"
fi

# Check again after resolving the default cache destination.
if [[ "$INPUT" -ef "$OUTPUT" ]]; then
    echo "ERROR: Input and output refer to the same file. Source image was left untouched." >&2
    exit 2
fi

mkdir -p "$(dirname -- "$OUTPUT")"

if [[ "$USE_CACHE" == true ]]; then
    exec 9>"$OUTPUT.lock"
    flock -x 9

    if [[ -s "$OUTPUT" ]] &&
        magick identify -quiet "$OUTPUT" >/dev/null 2>&1
    then
        echo "UPSCALE_STATUS=OK"
        echo "UPSCALE_CACHE=HIT"
        echo "UPSCALE_OUTPUT=$OUTPUT"
        exit 0
    fi

    echo "UPSCALE_CACHE=MISS"
fi

echo "UPSCALE_STATUS=STARTING"
echo "UPSCALE_INPUT=$INPUT"
echo "UPSCALE_OUTPUT=$OUTPUT"
echo "UPSCALE_SCALE=$SCALE"
echo "UPSCALE_MODEL=$MODEL"

WORK_OUTPUT="$(mktemp --suffix=.png "$(dirname -- "$OUTPUT")/.hunu-upscale.XXXXXX")"
TEMP_OUTPUT=""
trap 'rm -f -- "$WORK_OUTPUT"; if [[ -n "$TEMP_OUTPUT" ]]; then rm -f -- "$TEMP_OUTPUT"; fi' EXIT

# realesrgan-x4plus is a native 4x model. Although the NCNN executable accepts
# -s 2 and -s 3, non-native scaling can produce tiled/corrupted output on some
# builds. Always run the model at 4x, then downsample for requested 2x/3x.
if [[ "$SCALE" == "4" ]]; then
    if ! realesrgan-ncnn-vulkan \
        -i "$INPUT" \
        -o "$WORK_OUTPUT" \
        -s 4 \
        -n "$MODEL"
    then
        rm -f -- "$WORK_OUTPUT"
        echo "ERROR: Real-ESRGAN failed." >&2
        exit 1
    fi
else
    if ! command -v magick >/dev/null 2>&1; then
        echo "ERROR: ImageMagick (magick) is required for 2x/3x AI output." >&2
        exit 127
    fi

    TEMP_OUTPUT="$(mktemp --suffix=.png "${TMPDIR:-/tmp}/hunu-upscale-4x.XXXXXX")"

    if ! realesrgan-ncnn-vulkan \
        -i "$INPUT" \
        -o "$TEMP_OUTPUT" \
        -s 4 \
        -n "$MODEL"
    then
        echo "ERROR: Real-ESRGAN failed." >&2
        exit 1
    fi

    if [[ "$SCALE" == "2" ]]; then
        RESIZE_PERCENT="50%"
    else
        RESIZE_PERCENT="75%"
    fi

    if ! magick "$TEMP_OUTPUT" -resize "$RESIZE_PERCENT" "$WORK_OUTPUT"; then
        rm -f -- "$WORK_OUTPUT"
        echo "ERROR: Failed to resize Real-ESRGAN output to ${SCALE}x." >&2
        exit 1
    fi
fi

if [[ ! -s "$WORK_OUTPUT" ]]; then
    echo "ERROR: Real-ESRGAN did not produce an output image." >&2
    exit 1
fi

mv -fT -- "$WORK_OUTPUT" "$OUTPUT"

echo "UPSCALE_STATUS=OK"
echo "UPSCALE_OUTPUT=$OUTPUT"

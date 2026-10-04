#!/usr/bin/env bash
set -euo pipefail

INPUT=""
OUTPUT=""
SCALE="4"
MODEL="realesrgan-x4plus"

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
    CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
    CACHE_DIR="$CACHE_HOME/hunu-wallpaper"
    OUTPUT="$CACHE_DIR/upscaled-current.png"
fi

if [[ ! -f "$INPUT" ]]; then
    echo "ERROR: Input image does not exist: $INPUT" >&2
    exit 1
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

mkdir -p "$(dirname -- "$OUTPUT")"

echo "UPSCALE_STATUS=STARTING"
echo "UPSCALE_INPUT=$INPUT"
echo "UPSCALE_OUTPUT=$OUTPUT"
echo "UPSCALE_SCALE=$SCALE"
echo "UPSCALE_MODEL=$MODEL"

rm -f -- "$OUTPUT"

if ! realesrgan-ncnn-vulkan \
    -i "$INPUT" \
    -o "$OUTPUT" \
    -s "$SCALE" \
    -n "$MODEL"
then
    rm -f -- "$OUTPUT"
    echo "ERROR: Real-ESRGAN failed." >&2
    exit 1
fi

if [[ ! -s "$OUTPUT" ]]; then
    echo "ERROR: Real-ESRGAN did not produce an output image." >&2
    exit 1
fi

echo "UPSCALE_STATUS=OK"
echo "UPSCALE_OUTPUT=$OUTPUT"

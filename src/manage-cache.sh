#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

ACTION="${1:-}"
case "$ACTION" in
    stats|clear) ;;
    *) die "Usage: manage-cache.sh stats|clear" ;;
esac
[[ $# -eq 1 ]] || die "Expected one action."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cache-path.sh"
CACHE_DIR="$(hunu_cache_directory)"

# Report an absent cache without creating it.
if [[ ! -d "$CACHE_DIR" ]]; then
    printf 'CACHE_BYTES=0\nCACHE_FILES=0\n'
    exit 0
fi

if [[ "$ACTION" == "clear" ]]; then
    exec 8>"$CACHE_DIR/.hunu-cache.lock"
    flock -xn 8 ||
        die "AI cache is in use. Try again after processing finishes."
fi

shopt -s nullglob
FILES=()
BYTES=0

for file in "$CACHE_DIR"/upscaled-*.png; do
    name="${file##*/}"

    # Only Hunu's published AI images, never directories or symlinks.
    [[ "$name" == "upscaled-current.png" ||
       "$name" =~ ^upscaled-[a-f0-9]{64}\.png$ ]] || continue
    [[ -f "$file" && ! -L "$file" ]] || continue

    if size="$(stat -c '%s' -- "$file" 2>/dev/null)"; then
        FILES+=("$file")
        BYTES=$((BYTES + size))
    fi
done

if [[ "$ACTION" == "clear" ]]; then
    if (( ${#FILES[@]} > 0 )); then
        rm -f -- "${FILES[@]}"
    fi
    printf 'CACHE_REMOVED=%s\n' "${#FILES[@]}"
    BYTES=0
    FILES=()
fi

# Keep lock files: deleting them could break synchronization.
printf 'CACHE_BYTES=%s\n' "$BYTES"
printf 'CACHE_FILES=%s\n' "${#FILES[@]}"
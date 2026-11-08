#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $# -ge 2 && "$1" == "--backend" ]] ||
    die "Usage: $0 --backend serpantinum|hyprpaper|awww|noctalia OUTPUT FILE ..."

BACKEND="$2"
shift 2

case "$BACKEND" in
    serpantinum|hyprpaper|awww|noctalia) ;;
    *) die "Unsupported wallpaper backend: $BACKEND" ;;
esac

(( $# >= 2 && $# % 2 == 0 )) ||
    die "Expected monitor-output and wallpaper-file pairs."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PAIRS=("$@")
source "$SCRIPT_DIR/cache-path.sh"
APPLY_CACHE="$(hunu_cache_directory)"
mkdir -p -- "$APPLY_CACHE"
# A preview session can pass its already-held lock through to this child.
if [[ "${HUNU_APPLY_LOCK_FD:-}" =~ ^[0-9]+$ ]] &&
   [[ "/proc/self/fd/$HUNU_APPLY_LOCK_FD" -ef "$APPLY_CACHE/wallpaper-apply.lock" ]]; then
    exec 8>&"$HUNU_APPLY_LOCK_FD"
else
    exec 8>"$APPLY_CACHE/wallpaper-apply.lock"
fi
flock -n 8 || die "Another wallpaper Apply is in progress. Try again."

record_success() {
    local status=$?
    if (( status == 0 )) && [[ "${HUNU_PREVIEW_ONLY:-0}" != 1 ]]; then
        python3 "$SCRIPT_DIR/switcher-controller.py" record "${PAIRS[@]}" ||
            printf 'Warning: Could not remember the applied set.\n' >&2
    fi
}
trap record_success EXIT

# Validate every pair before changing any wallpaper.
while (( $# >= 2 )); do
    output="$1"
    file="$2"
    shift 2

    [[ -n "$output" ]] || die "Missing monitor output name."
    [[ -f "$file" ]] || die "Wallpaper does not exist: $file"

    if [[ "$BACKEND" == "hyprpaper" ]]; then
        [[ "$output" != *,* && "$file" != *,* ]] ||
            die "hyprpaper IPC cannot accept commas in output names or wallpaper paths."
    fi
done

if [[ "$BACKEND" == "serpantinum" ]]; then
    "$SCRIPT_DIR/apply-serpantinum.sh" "${PAIRS[@]}"
    exit 0
fi

if [[ "$BACKEND" == "noctalia" ]]; then
    if command -v noctalia >/dev/null 2>&1; then
        NOCTALIA_COMMAND=(noctalia msg wallpaper-set)
        NOCTALIA_NATIVE=true
    else
        command -v quickshell >/dev/null 2>&1 || die "Noctalia or Quickshell is not installed."
        NOCTALIA_COMMAND=(quickshell -c noctalia-shell ipc call wallpaper set)
        NOCTALIA_NATIVE=false
    fi
    command -v timeout >/dev/null 2>&1 || die "timeout was not found."

    set -- "${PAIRS[@]}"
    while (( $# >= 2 )); do
        output="$1"
        # Resolve relative paths in Hunu's working directory.
        file="$2"
        [[ "$file" == /* ]] || file="$PWD/$file"
        shift 2

        if [[ "$NOCTALIA_NATIVE" == true ]]; then
            arguments=("$output" "$file")
        else
            arguments=("$file" "$output")
        fi
        if ! reply="$(timeout 10 "${NOCTALIA_COMMAND[@]}" "${arguments[@]}" 2>&1)"; then
            die "Noctalia Apply failed for $output: $reply"
        fi
    done

    printf 'Wallpapers applied through Noctalia.\n'
    exit 0
fi

if [[ "$BACKEND" == "awww" ]]; then
    command -v awww >/dev/null 2>&1 ||
        die "awww was not found."

    set -- "${PAIRS[@]}"

    while (( $# >= 2 )); do
        output="$1"
        file="$2"
        shift 2

        [[ "$output" != *,* ]] ||
            die "awww output names cannot contain commas."

        if ! reply="$(awww img \
            --outputs "$output" \
            --resize stretch \
            --transition-type none \
            -- "$file" 2>&1)"
        then
            die "awww Apply failed for $output: $reply"
        fi
    done

    printf 'Wallpapers applied through awww.\n'
    exit 0
fi

command -v hyprctl >/dev/null 2>&1 ||
    die "hyprctl was not found."

set -- "${PAIRS[@]}"

while (( $# >= 2 )); do
    output="$1"
    file="$2"
    shift 2

    if ! reply="$(hyprctl hyprpaper wallpaper "$output,$file" 2>&1)"; then
        die "hyprpaper Apply failed for $output: $reply"
    fi

    [[ -z "$reply" || "$reply" == "ok" ]] ||
        die "Unexpected hyprpaper response for $output: $reply"
done

printf 'Wallpapers applied through hyprpaper.\n'
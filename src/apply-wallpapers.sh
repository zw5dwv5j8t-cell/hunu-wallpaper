#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $# -ge 2 && "$1" == "--backend" ]] ||
    die "Usage: $0 --backend serpantinum|hyprpaper|awww OUTPUT FILE ..."

BACKEND="$2"
shift 2

case "$BACKEND" in
    serpantinum|hyprpaper|awww) ;;
    *) die "Unsupported wallpaper backend: $BACKEND" ;;
esac

(( $# >= 2 && $# % 2 == 0 )) ||
    die "Expected monitor-output and wallpaper-file pairs."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PAIRS=("$@")

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
    exec "$SCRIPT_DIR/apply-serpantinum.sh" "${PAIRS[@]}"
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
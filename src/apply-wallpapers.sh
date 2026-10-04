#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $# -ge 2 && "$1" == "--backend" ]] ||
    die "Usage: $0 --backend serpantinum|hyprpaper OUTPUT FILE ..."

BACKEND="$2"
shift 2

case "$BACKEND" in
    serpantinum|hyprpaper) ;;
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

    [[ "$reply" == "ok" ]] ||
        die "Unexpected hyprpaper response for $output: $reply"
done

printf 'Wallpapers applied through hyprpaper.\n'
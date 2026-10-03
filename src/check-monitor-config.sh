#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Development tree:
#   hunu-wallpaper/
#   ├── src/check-monitor-config.sh
#   └── config/config.conf
#
# Installed tree:
#   ~/.config/hunu-wallpaper/
#   ├── check-monitor-config.sh
#   └── config.conf
#
# Detect the layout from the script's directory structure, not from whether
# config.conf exists. A fresh installation intentionally has no config.conf yet.

if [[ "$(basename -- "$SCRIPT_DIR")" == "src" && -d "$SCRIPT_DIR/../config" ]]; then
    CONFIG_PATH="$(cd -- "$SCRIPT_DIR/../config" && pwd)/config.conf"
else
    CONFIG_PATH="$SCRIPT_DIR/config.conf"
fi

if [[ -f "$CONFIG_PATH" ]]; then
    printf 'CONFIG_EXISTS=true\n'
else
    printf 'CONFIG_EXISTS=false\n'
fi

printf 'CONFIG_PATH=%s\n' "$CONFIG_PATH"

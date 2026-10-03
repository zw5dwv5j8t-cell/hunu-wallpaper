#!/usr/bin/env bash

# Hunu Wallpaper Splitter — optional theme provider detection
#
# Hunu always has its own built-in fallback palette. This helper only
# discovers optional external theme providers, so their absence is normal.

set -u

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SERPANTINUM_COLORS="$STATE_HOME/serpantinum/qs_colors.json"

if [[ -f "$SERPANTINUM_COLORS" ]]; then
    printf 'THEME_PROVIDER=serpantinum\n'
    printf 'THEME_FILE=%s\n' "$SERPANTINUM_COLORS"
else
    printf 'THEME_PROVIDER=fallback\n'
    printf 'THEME_FILE=\n'
fi

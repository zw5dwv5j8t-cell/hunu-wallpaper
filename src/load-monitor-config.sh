#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${1:-}"

# No saved setup is normal during first run.
if [[ -z "$CONFIG_PATH" || ! -f "$CONFIG_PATH" ]]; then
    printf 'CONFIG_LOADED=false\n'
    exit 0
fi

# config.conf is Hunu's own trusted local Bash-style configuration.
# shellcheck disable=SC1090
source "$CONFIG_PATH"

bool_value() {
    [[ "${1:-false}" == "true" ]] && printf 'true' || printf 'false'
}

printf 'CONFIG_LOADED=true\n'

for i in 1 2 3; do
    enabled_var="MONITOR_${i}_ENABLED"
    output_var="MONITOR_${i}_OUTPUT"
    width_var="MONITOR_${i}_PHYSICAL_WIDTH_CM"
    height_var="MONITOR_${i}_PHYSICAL_HEIGHT_CM"
    x_var="MONITOR_${i}_X_CM"
    y_var="MONITOR_${i}_Y_CM"

    printf 'MONITOR_%d_ENABLED=%s\n' "$i" "$(bool_value "${!enabled_var:-false}")"
    printf 'MONITOR_%d_OUTPUT=%s\n' "$i" "${!output_var:-}"
    printf 'MONITOR_%d_PHYSICAL_WIDTH_CM=%s\n' "$i" "${!width_var:-0}"
    printf 'MONITOR_%d_PHYSICAL_HEIGHT_CM=%s\n' "$i" "${!height_var:-0}"
    printf 'MONITOR_%d_X_CM=%s\n' "$i" "${!x_var:-0}"
    printf 'MONITOR_%d_Y_CM=%s\n' "$i" "${!y_var:-0}"
done

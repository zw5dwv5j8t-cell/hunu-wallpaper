#!/usr/bin/env bash

# Shared cache namespace for Hunu helpers.
hunu_cache_directory() {
    local script_dir app_name

    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || return 1
    app_name="${HUNU_APP_NAME:-$(basename -- "$script_dir")}"

    if [[ "$app_name" == "src" ]]; then
        app_name="hunu-wallpaper"
    fi

    if [[ ! "$app_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: Invalid HUNU_APP_NAME." >&2
        return 2
    fi

    printf '%s/%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}" "$app_name"
}
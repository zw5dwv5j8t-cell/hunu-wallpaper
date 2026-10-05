#!/usr/bin/env bash
set -euo pipefail

# Report command availability for the About panel.
# Optional wallpaper backends still use their separate IPC readiness checks.
for command_name in \
    hyprctl quickshell magick jq bash awk \
    flock sha256sum timeout python3 \
    realesrgan-ncnn-vulkan hyprpaper awww
do
    if command -v "$command_name" >/dev/null 2>&1; then
        printf '%s=true\n' "$command_name"
    else
        printf '%s=false\n' "$command_name"
    fi
done
#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Hunu Wallpaper Splitter installer
#
# Normal install:
#   ./install.sh
#
# Isolated development/test install:
#   HUNU_APP_NAME=hunu-wallpaper-public-test ./install.sh
#
# APP_NAME controls every installed filename/path so a test installation
# cannot overwrite a normal Hunu installation.
# ---------------------------------------------------------------------------

APP_NAME="${HUNU_APP_NAME:-hunu-wallpaper}"

if [[ ! "$APP_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: Invalid HUNU_APP_NAME. Use letters, numbers, dots, underscores, or hyphens; start with a letter or number." >&2
    exit 2
fi

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Respect XDG locations while retaining standard Linux defaults.
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

CONFIG_DIR="$CONFIG_HOME/$APP_NAME"
DESKTOP_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons"
BACKUP_ROOT="$STATE_HOME/$APP_NAME/backups"

DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"
ICON_FILE="$ICON_DIR/$APP_NAME.png"

if [[ "$APP_NAME" == "hunu-wallpaper" ]]; then
    DISPLAY_NAME="Hunu Wallpaper Splitter"
else
    DISPLAY_NAME="Hunu Wallpaper Splitter ($APP_NAME)"
fi

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

printf '\n'
printf '%s — installer\n' "$DISPLAY_NAME"
printf '============================================\n\n'

# ---------------------------------------------------------------------------
# Required dependencies
#
# Hunu v1 targets Hyprland + Quickshell.
#
# The installer intentionally does not invoke pacman, apt, dnf, or another
# package manager. Users install dependencies using their distribution's
# normal package-management method.
# ---------------------------------------------------------------------------

missing=()

for cmd in hyprctl quickshell magick jq bash awk flock sha256sum timeout; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing+=("$cmd")
    fi
done

if (( ${#missing[@]} > 0 )); then
    printf 'Missing required dependencies:\n\n' >&2

    for cmd in "${missing[@]}"; do
        printf '  - %s\n' "$cmd" >&2
    done

    printf '\n' >&2
    printf 'Install the missing dependencies with your distribution'\''s\n' >&2
    printf 'package manager, then run ./install.sh again.\n\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate repository
# ---------------------------------------------------------------------------

required_files=(
    "src/shell.qml"
    "src/SetupView.qml"
    "src/WorkspaceView.qml"
    "src/Theme.qml"
    "src/qmldir"
    "src/split-wallpaper.sh"
    "src/detect-monitors.sh"
    "src/save-monitor-config.sh"
    "src/save-output-dir.sh"
    "src/save-apply-backend.sh"
    "src/check-monitor-config.sh"
    "src/load-monitor-config.sh"
    "src/detect-theme.sh"
    "src/check-upscaler.sh"
    "src/check-apply-backend.sh"
    "src/upscale-image.sh"
    "src/apply-serpantinum.sh"
    "src/apply-wallpapers.sh"
    "assets/hunu-wallpaper.png"
    "src/cache-path.sh"
    "src/manage-cache.sh"
)

for file in "${required_files[@]}"; do
    [[ -f "$REPO_DIR/$file" ]] || \
        die "Repository file is missing: $file"
done

# ---------------------------------------------------------------------------
# Optional Serpantinum integration
# ---------------------------------------------------------------------------

SERPANTINUM_SHELL="$DATA_HOME/serpantinum/src/quickshell/Shell.qml"
SERPANTINUM_COLORS="$STATE_HOME/serpantinum/qs_colors.json"

has_serpantinum=false

if [[ -f "$SERPANTINUM_SHELL" ]]; then
    has_serpantinum=true
fi

# ---------------------------------------------------------------------------
# Prepare installation directories
# ---------------------------------------------------------------------------

mkdir -p \
    "$CONFIG_DIR" \
    "$DESKTOP_DIR" \
    "$ICON_DIR" \
    "$BACKUP_ROOT"

# ---------------------------------------------------------------------------
# Back up an existing installation
#
# config.conf is included intentionally. A reinstall/update therefore leaves
# the previous monitor calibration recoverable from the backup.
# ---------------------------------------------------------------------------

if find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$BACKUP_ROOT/${APP_NAME}-before-install-$stamp.tar.gz"

    tar -czf "$backup" \
        -C "$CONFIG_HOME" \
        "$APP_NAME"

    printf 'Backed up existing installation:\n'
    printf '  %s\n\n' "$backup"
fi

# ---------------------------------------------------------------------------
# Install application files
# ---------------------------------------------------------------------------

app_files=(
    "shell.qml"
    "SetupView.qml"
    "WorkspaceView.qml"
    "Theme.qml"
    "qmldir"
    "split-wallpaper.sh"
    "detect-monitors.sh"
    "save-monitor-config.sh"
    "save-output-dir.sh"
    "save-apply-backend.sh"
    "check-monitor-config.sh"
    "load-monitor-config.sh"
    "check-upscaler.sh"
    "check-apply-backend.sh"
    "upscale-image.sh"
    "detect-theme.sh"
    "apply-serpantinum.sh"
    "apply-wallpapers.sh"
    "cache-path.sh"
    "manage-cache.sh"

)

for file in "${app_files[@]}"; do
    cp "$REPO_DIR/src/$file" "$CONFIG_DIR/$file"
done

chmod +x \
    "$CONFIG_DIR/split-wallpaper.sh" \
    "$CONFIG_DIR/detect-monitors.sh" \
    "$CONFIG_DIR/save-monitor-config.sh" \
    "$CONFIG_DIR/save-output-dir.sh" \
    "$CONFIG_DIR/save-apply-backend.sh" \
    "$CONFIG_DIR/check-monitor-config.sh" \
    "$CONFIG_DIR/load-monitor-config.sh" \
    "$CONFIG_DIR/detect-theme.sh" \
    "$CONFIG_DIR/apply-serpantinum.sh" \
    "$CONFIG_DIR/apply-wallpapers.sh" \
    "$CONFIG_DIR/check-upscaler.sh" \
    "$CONFIG_DIR/check-apply-backend.sh" \
    "$CONFIG_DIR/manage-cache.sh" \
    "$CONFIG_DIR/upscale-image.sh"

# Deliberately do NOT install config/config.conf.
#
# Fresh installation:
#   No config.conf -> first-run Monitor Setup.
#
# Reinstallation:
#   Existing config.conf remains untouched, preserving the user's monitor
#   calibration.

# ---------------------------------------------------------------------------
# Install icon
# ---------------------------------------------------------------------------

cp \
    "$REPO_DIR/assets/hunu-wallpaper.png" \
    "$ICON_FILE"

# ---------------------------------------------------------------------------
# Install desktop launcher
# ---------------------------------------------------------------------------
desktop_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

desktop_exec_argument() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"
    value="${value//%/%%}"
    desktop_value "\"$value\""
}

EXEC_CONFIG_DIR="$(desktop_exec_argument "$CONFIG_DIR")"
DESKTOP_ICON="$(desktop_value "$ICON_FILE")"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=Create coordinated wallpapers for 1–3 physical monitors
Exec=quickshell -p $EXEC_CONFIG_DIR
Icon=$DESKTOP_ICON
Terminal=false
Categories=Graphics;Utility;
StartupNotify=false
EOF

chmod +x "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Installation summary
# ---------------------------------------------------------------------------

printf 'Installed successfully.\n\n'

printf 'Application:\n'
printf '  %s\n\n' "$CONFIG_DIR"

printf 'Launcher:\n'
printf '  %s\n\n' "$DESKTOP_FILE"

printf 'Icon:\n'
printf '  %s\n\n' "$ICON_FILE"

printf 'Launch manually with:\n'
printf '  quickshell -p %s\n\n' "$CONFIG_DIR"

printf 'Optional wallpaper backends:\n'

if [[ "$has_serpantinum" == true ]]; then
    printf '  Serpantinum detected.\n'
else
    printf '  Serpantinum was not detected.\n'
fi

if command -v hyprpaper >/dev/null 2>&1; then
    printf '  hyprpaper detected.\n'
else
    printf '  hyprpaper was not detected.\n'
fi

if command -v awww >/dev/null 2>&1; then
    printf '  awww detected.\n'
else
    printf '  awww was not detected.\n'
fi

printf '  Choose the Apply backend inside Hunu.\n'
printf '  Apply requires the selected backend IPC to be responding.\n'
printf '  Hunu does not start or stop wallpaper daemons.\n'
printf '  Wallpaper generation works without an Apply backend.\n'

printf '\nOptional theme integration:\n'

if [[ "$has_serpantinum" == true && -f "$SERPANTINUM_COLORS" ]]; then
    printf '  Serpantinum/Matugen colors are available.\n'
else
    printf '  Serpantinum color state is not currently available.\n'
    printf '  Hunu will use its built-in fallback palette.\n'
fi

if command -v realesrgan-ncnn-vulkan >/dev/null 2>&1; then
    printf '\n'
    printf 'Optional AI upscaling:\n'
    printf '  Real-ESRGAN detected.\n'
    printf '  AI upscaling is available.\n'
else
    printf '\n'
    printf 'Optional AI upscaling:\n'
    printf '  Real-ESRGAN was not detected.\n'
    printf '  Hunu works normally without it.\n'
    printf '  Install realesrgan-ncnn-vulkan to enable AI upscaling.\n'
fi

printf '\n'

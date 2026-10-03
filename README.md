# Hunu Wallpaper Splitter

**Hunu Wallpaper Splitter** is a Hyprland + Quickshell application for creating
coordinated wallpapers across **one to three monitors**.

Instead of assuming that every display has the same size, orientation, or pixel
density, Hunu Wallpaper Splitter can use each monitor's **real physical
dimensions and placement** to build a composition that visually continues
across the displays.

## Preview

![Hunu Wallpaper Splitter wallpaper generation](assets/screenshots/wallpaper-generation.png)

Create and preview coordinated wallpapers using the physical arrangement of your monitors.

## Features

- Supports **1–3 monitors**
- Automatically detects connected Hyprland outputs
- Assign any detected output to Monitor 1, 2, or 3
- Configure physical monitor width, height, X position, and Y position in cm
- Supports landscape, portrait, mixed-resolution, and offset monitor layouts
- **Linked / Seam** mode for one physical composition across displays
- **Maximum Quality** mode for independent source crops
- Physical-layout preview
- Wallpaper positioning controls
- Sequential output sets using `_a`, `_b`, and `_c`
- Saved monitor setup with first-run configuration
- Optional Serpantinum wallpaper Apply integration
- Optional Serpantinum/Matugen colors with a built-in fallback theme
- XDG-aware installer
- Existing monitor configuration is preserved when reinstalling

## Requirements

Required:

- Hyprland
- Quickshell
- ImageMagick (`magick`)
- Bash
- `awk`
- `jq`

Optional:

- Serpantinum — enables automatic wallpaper Apply integration and use of the
  current Serpantinum/Matugen color palette.

The installer checks dependencies but does not install system packages.

## Install

Clone or download the repository, enter it, and run:

```bash
./install.sh
```

By default the installer uses the standard XDG locations:

- application files: `${XDG_CONFIG_HOME:-$HOME/.config}/hunu-wallpaper`
- desktop launcher: `${XDG_DATA_HOME:-$HOME/.local/share}/applications/`
- icon: `${XDG_DATA_HOME:-$HOME/.local/share}/icons/`
- installer backups: `${XDG_STATE_HOME:-$HOME/.local/state}/hunu-wallpaper/backups/`

An existing installed configuration is backed up before installation. A saved
`config.conf` is preserved across reinstalls.

### Test or alternate installation name

For development or parallel installations, set `HUNU_APP_NAME`:

```bash
HUNU_APP_NAME=hunu-wallpaper-test ./install.sh
```

The application, launcher, icon, and backup paths use that name, keeping the
test installation separate from the normal one.

## First run

On first launch, Hunu Wallpaper Splitter opens **Monitor Setup**.

For each monitor you want to use:

1. Assign a detected Hyprland output.
2. Confirm its pixel resolution.
3. Enter the monitor's physical width and height in centimeters.
4. Enter its physical X/Y position relative to the other displays.

Physical measurements should include the monitor bezels if you want the linked
composition to account for the real gap occupied by those bezels.

Monitor 1 is required. Monitors 2 and 3 are optional.

After saving, the setup is reused automatically on later launches. Monitor
Setup remains available if the physical arrangement changes.

![Hunu Wallpaper Splitter monitor setup](assets/screenshots/monitor-setup.png)

## Wallpaper modes

### Linked / Seam

Linked mode treats the monitors as windows into one physical composition. It
uses their real-world dimensions and X/Y placement rather than simply joining
their pixel resolutions.

This is useful when a landscape should appear to continue naturally from one
display to another even when the monitors have different sizes, orientations,
resolutions, or vertical offsets.

### Maximum Quality

Maximum Quality creates an independent crop from the original source image for
each monitor. This avoids constructing the outputs from one intermediate
combined canvas and prioritizes usable source detail on every display.

## Generate and Apply

**Generate** creates the wallpaper files without changing the desktop.

Generated wallpapers are written to:

```text
~/Pictures/Wallpapers
```

unless `OUTPUT_DIR` is changed in the saved configuration.

When Serpantinum is detected, **Apply** sends each generated wallpaper to its
corresponding output through Serpantinum's Quickshell wallpaper IPC.

Without Serpantinum, wallpaper generation still works; applying the resulting
files is left to the user's wallpaper system.

## Run manually

With the default installation:

```bash
quickshell -p ~/.config/hunu-wallpaper
```

If `XDG_CONFIG_HOME` or `HUNU_APP_NAME` was customized, use the corresponding
installed application directory instead.

## Uninstall

From the repository:

```bash
./uninstall.sh
```

For an alternate installation name:

```bash
HUNU_APP_NAME=hunu-wallpaper-test ./uninstall.sh
```

The uninstaller removes the installed application, launcher, and icon.
Generated wallpapers and installer backups are deliberately left untouched.

## Repository layout

```text
assets/
  hunu-wallpaper.png
config/
  config.example.conf
packaging/
  hunu-wallpaper.desktop
src/
  apply-serpantinum.sh
  check-monitor-config.sh
  detect-monitors.sh
  detect-theme.sh
  load-monitor-config.sh
  qmldir
  save-monitor-config.sh
  SetupView.qml
  shell.qml
  split-wallpaper.sh
  Theme.qml
  WorkspaceView.qml
install.sh
uninstall.sh
README.md
LICENSE
.gitignore
```

`config/config.conf` is a local development configuration and is intentionally
ignored by Git. Public users create their own monitor configuration through the
first-run setup.

## Notes

- Hunu Wallpaper Splitter currently targets **Hyprland + Quickshell**.
- Automatic Apply is currently **Serpantinum-specific**.
- Monitor physical placement is user-configured because display protocols do
  not provide the real-world bezel-inclusive arrangement needed for accurate
  seam composition.
- Up to three monitors are supported in the current version.

## License

Hunu Wallpaper Splitter is released under the **MIT License**. See `LICENSE`.

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
- Wallpaper positioning controls with editable integer fields for exact offsets
- Source-resolution quality analysis with an upscale recommendation
- Optional Real-ESRGAN AI upscaling at 2×, 3×, or 4×
- Sequential output sets using `_a`, `_b`, and `_c`
- Saved monitor setup with first-run configuration
- Optional Serpantinum wallpaper Apply integration
- Optional Serpantinum/Matugen colors with a built-in fallback theme
- XDG-aware installer
- Existing monitor configuration is preserved when reinstalling
- Persistent output-folder chooser
- Generation settings captured at job start, with controls locked while processing
- Reusable AI cache with per-entry locking
- Concurrent generation protected by an output-directory lock

## Requirements

Required:

- Hyprland
- Quickshell
- ImageMagick (`magick`)
- Bash
- `awk`
- `jq`
- `flock`
- `sha256sum`

Optional:

- Serpantinum — enables automatic wallpaper Apply integration and use of the
  current Serpantinum/Matugen color palette.
- Real-ESRGAN (`realesrgan-ncnn-vulkan`) — enables optional AI upscaling.
  Hunu works normally without it.

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
test installation separate from the normal one. Application names must start
with a letter or number and contain only letters, numbers, dots, underscores,
or hyphens.

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

## Image quality and AI upscaling

Hunu compares the source image resolution with the resolution needed for the
current monitor layout and wallpaper mode. The Image Quality panel reports
whether the source has enough resolution and, when useful, recommends an
upscale factor.

Upscaling is always optional. Hunu never enables it automatically, even when
the source resolution is below the recommended size.

When `realesrgan-ncnn-vulkan` is installed, the Image Quality panel offers
**Off**, **2×**, **3×**, and **4×** AI upscaling. The original source image is
never modified; the upscaled working image is stored in Hunu's XDG cache.

The `realesrgan-x4plus` model is run at its native 4× scale. For reliable 2×
and 3× output, Hunu creates the native 4× result first and then downsamples it
with ImageMagick to the requested size.

Without Real-ESRGAN, Hunu still analyzes source quality and generates
wallpapers normally from the original image.

Completed AI results are cached by source contents, requested scale, model
name, and helper version. Matching requests reuse the cached image; simultaneous
requests for the same cache entry wait for its creation.

The default cache location is
`${XDG_CACHE_HOME:-$HOME/.cache}/hunu-wallpaper/`. Alternate installations use
their own application-name namespace. Cached files remain until removed or
until Hunu is uninstalled.

The helper rejects an output that refers to its source file, including through
symlinks or hard links. Results are written to temporary files and replace the
destination only after successful completion. Failed upscaling preserves any
existing destination. AI failures display diagnostic details in the workspace.

## Generate and Apply

**Generate** creates the wallpaper files without changing the desktop.

Generated wallpapers are written to:

```text
~/Pictures/Wallpapers
```

by default. Use **Choose Folder** beside **Save to** to select another existing,
writable directory. The selection is remembered across launches and preserved
when saving monitor calibration. Previously generated wallpapers are left
in their original locations.

Use the sliders for broad positioning adjustments, or type an exact integer
into the X/Y fields. Press Enter or leave the field to apply the value.
Values are limited to the valid crop range. **Center / Reset** returns all
offsets to zero.

Controls are locked while generating or applying wallpapers. Generation jobs
targeting the same output directory run sequentially to prevent output-set
collisions.

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

The uninstaller removes the installed application, launcher, icon, and Hunu
cache. Generated wallpapers and installer backups are deliberately left
untouched.

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
  check-upscaler.sh
  detect-monitors.sh
  detect-theme.sh
  load-monitor-config.sh
  qmldir
  save-monitor-config.sh
  save-output-dir.sh
  SetupView.qml
  shell.qml
  split-wallpaper.sh
  upscale-image.sh
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
- `config.conf` is trusted local Bash configuration and is sourced by the
  configuration helpers.
- Monitor physical placement is user-configured because display protocols do
  not provide the real-world bezel-inclusive arrangement needed for accurate
  seam composition.
- Up to three monitors are supported in the current version.
- Monitor 1/2/3 are configuration slots; physical X/Y placement determines the
  spatial arrangement, so monitor numbering does not need to run left to right.

## License

Hunu Wallpaper Splitter is released under the **MIT License**. See `LICENSE`.

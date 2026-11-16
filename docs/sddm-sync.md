# Noctalia SDDM wallpaper synchronization

If Noctalia's `wallpaper_changed` hook runs an SDDM wallpaper script, live picker
browsing can start many expensive blur jobs. A thread limit alone does not stop
jobs accumulating. The optional `sddm-sync-guard.py` helper coalesces hooks and
waits for Hunu's existing wallpaper transaction lock to clear. It runs your sync
script against the final wallpaper state after Enter or Escape. New wallpaper
requests, or reopening the picker, cancel obsolete sync process groups.

The original script must query current wallpapers when called, refresh all
monitors when `NOCTALIA_WALLPAPER_CONNECTOR` is unset, write destinations
atomically, and keep its subprocesses in its process group. The guard invokes
it with no arguments and limits `MAGICK_THREAD_LIMIT` and `OMP_NUM_THREADS` to
one. Explicit script/tool overrides may change these limits. Keep your existing
`magick -limit thread 1` option as well.

## Setup for the reported installation

After `git pull --ff-only origin main` and `bash install.sh`, preserve
`~/.local/bin/sddm-wallpaper-sync` as your original generator. Back up
`~/.config/noctalia/sddm-wallpaper.toml` and change **both** existing hook paths
from `/home/hunu/.local/bin/sddm-wallpaper-sync` to:

```toml
[hooks]
started = "/home/hunu/.config/hunu-wallpaper/sddm-sync-guard.py"
wallpaper_changed = "/home/hunu/.config/hunu-wallpaper/sddm-sync-guard.py"
```

Then run `noctalia msg config-reload`. Installation does not edit these hooks.
There is no need to replace the original generator or change the blur/resolution.
Stop using the picker briefly to let any jobs launched by the old hook finish.

Re-enable Live desktop preview. During browsing there should be no new SDDM
ImageMagick jobs. After closing the picker, one script refreshes the final state;
it refreshes the restored wallpaper after Escape. Reopen during a sync to check
that obsolete work stops. This behavior is covered by subprocess/lock tests;
actual Noctalia/SDDM behavior still requires a live retest.

Diagnostic log: `${XDG_CACHE_HOME:-$HOME/.cache}/hunu-wallpaper/sddm-sync/sync.log`.
A failed sync is logged and the worker exits; the next hook can retry. The worker
is short-lived but remains waiting while a picker is open. There is no idle
service. A sync that completed just before a new request may have written an
intermediate wallpaper; the worker performs the newer request afterward.

To undo, restore both original hook paths and reload Noctalia before uninstalling
Hunu. Only the wrapper and its worker are managed by Hunu; no system files or
SDDM settings are changed automatically.

## Other installations

The default generator is `~/.local/bin/sddm-wallpaper-sync`. A custom hook wrapper
can invoke `python3 /path/to/sddm-sync-guard.py --script /path/to/generator`.
The helper's installed directory name (or `HUNU_APP_NAME`) and `XDG_CACHE_HOME`
must match Hunu's picker environment so both use the same apply lock. Do not
point the generator back at the guard. Generator output goes to the diagnostic
log rather than Noctalia's hook output.

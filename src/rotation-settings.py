#!/usr/bin/env python3
"""Opt-in user timer for short-lived, layout-compatible wallpaper rotation."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
DEFAULTS = dict(enabled=False, intervalMinutes=15, avoidRepeat=True)
MARKER = '# Managed by Hunu Wallpaper; configure through Picker Settings.\n'


def settings_path():
    folder = HERE.parent / 'config' if HERE.name == 'src' and (HERE.parent / 'config').is_dir() else HERE
    return folder / 'rotation-settings.json'


def validate(values):
    if not isinstance(values, dict):
        raise ValueError('Rotation settings must be an object.')
    result = {key: values.get(key, default) for key, default in DEFAULTS.items()}
    if any(type(result[key]) is not bool for key in ('enabled', 'avoidRepeat')):
        raise ValueError('Rotation enable and avoid-repeat settings must be true or false.')
    if type(result['intervalMinutes']) is not int or not 1 <= result['intervalMinutes'] <= 1440:
        raise ValueError('Rotation interval must be between 1 and 1440 minutes.')
    return result


def load():
    try:
        return validate(json.loads(settings_path().read_text()))
    except FileNotFoundError:
        return dict(DEFAULTS)


def unit_name():
    return 'hunu-wallpaper-rotate-' + hashlib.sha256(str(HERE).encode()).hexdigest()[:12]


def unit_folder():
    return Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'systemd/user'


def systemctl(*arguments, check=True):
    return subprocess.run(['systemctl', '--user', *arguments], capture_output=True, text=True, timeout=10, check=check)


def available():
    try:
        return systemctl('show', '--property=SystemState', check=False).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def sync_environment():
    names = [key for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE') if key in os.environ]
    if names:
        systemctl('import-environment', *names)


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.rotation-')
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def quote(value, command=False):
    if '\n' in value or '\r' in value:
        raise ValueError('Timer paths cannot contain line breaks.')
    if command:
        value = value.replace('$', '$$')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%') + '"'


def save(values):
    values = validate(values)
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_name('.rotation-settings.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = load()
        name = unit_name()
        folder = unit_folder()
        service = folder / (name + '.service')
        timer = folder / (name + '.timer')
        needs_manager = previous['enabled'] or values['enabled'] or timer.exists()
        if needs_manager and not available():
            raise ValueError('Automatic cycling needs a running systemd user session. No rotation settings were changed.')
        originals = {file: file.read_bytes() if file.exists() else None for file in (path, service, timer)}
        for file in (service, timer):
            if originals[file] is not None and not originals[file].startswith(MARKER.encode()):
                raise ValueError('An unrelated user timer uses this name; it was left untouched.')
        try:
            if values['enabled']:
                sync_environment()
                service_text = (MARKER + '[Unit]\nDescription=Hunu random compatible wallpaper\n'
                                '[Service]\nType=oneshot\nExecStart=' + quote(sys.executable, command=True) + ' '
                                + quote(str(HERE / 'switcher-controller.py'), command=True) + ' rotate\n'
                                + 'Environment=' + quote('XDG_CACHE_HOME=' + str(Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))).expanduser().resolve())) + '\n'
                                + 'Environment=' + quote('HUNU_APP_NAME=' + (os.environ.get('HUNU_APP_NAME') or ('hunu-wallpaper' if HERE.name == 'src' else HERE.name))) + '\nTimeoutStartSec=45\n')
                timer_text = (MARKER + '[Unit]\nDescription=Hunu wallpaper rotation interval\n[Timer]\n'
                              + f"OnActiveSec={values['intervalMinutes']}min\nOnUnitInactiveSec={values['intervalMinutes']}min\n"
                              + 'AccuracySec=1s\nPersistent=false\n[Install]\nWantedBy=timers.target\n')
                atomic_write(service, service_text.encode())
                atomic_write(timer, timer_text.encode())
            elif needs_manager:
                systemctl('disable', '--now', name + '.timer')
                systemctl('stop', name + '.service')
                for file in (timer, service):
                    file.unlink(missing_ok=True)
            # The controller reads the new preference when the timer first fires.
            atomic_write(path, (json.dumps(values, indent=2) + '\n').encode())
            if needs_manager:
                systemctl('daemon-reload')
                if values['enabled']:
                    systemctl('enable', '--now', name + '.timer')
                    systemctl('restart', name + '.timer')
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            if needs_manager:
                # Remove enablement while the new unit still exists, including
                # symlinks created by an enable command that failed to start it.
                systemctl('disable', '--now', name + '.timer', check=False)
                systemctl('stop', name + '.service', check=False)
            for file, original in originals.items():
                if original is None:
                    file.unlink(missing_ok=True)
                else:
                    atomic_write(file, original)
            if needs_manager:
                systemctl('daemon-reload', check=False)
                if previous['enabled']:
                    systemctl('enable', '--now', name + '.timer', check=False)
                    systemctl('restart', name + '.timer', check=False)
            raise ValueError('Could not update automatic cycling; previous settings were restored. ' + str(error)) from error
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['get', 'save', 'disable', 'sync-session'])
    parser.add_argument('values', nargs='?')
    args = parser.parse_args()
    if args.action == 'sync-session':
        if load()['enabled'] and available():
            sync_environment()
        return
    if args.action in ('save', 'disable'):
        if args.action == 'save' and args.values is None:
            parser.error('save requires settings JSON')
        print(json.dumps(save(json.loads(args.values) if args.action == 'save' else dict(load(), enabled=False))))
    else:
        values = load()
        ready = available()
        if values['enabled'] and ready:
            try:
                sync_environment()
            except (OSError, subprocess.SubprocessError):
                ready = False
        print(json.dumps(dict(values, available=ready, timerUnit=unit_name() + '.timer')))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)

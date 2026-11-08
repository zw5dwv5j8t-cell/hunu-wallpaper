#!/usr/bin/env python3
"""Headless saved-set controller used by the short-lived wallpaper picker."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('saved_sets', HERE / 'list-wallpaper-sets.py')
saved_sets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(saved_sets)


def state_path():
    # Match cache-path.sh, including separate installed application names.
    app = os.environ.get('HUNU_APP_NAME') or HERE.name
    if app == 'src':
        app = 'hunu-wallpaper'
    return Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / app / 'last-applied.json'


def remember(pairs):
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.last-applied-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(dict(zip(pairs[::2], [str(Path(p).resolve()) for p in pairs[1::2]])), stream)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configuration():
    check = subprocess.run(['bash', str(HERE / 'check-monitor-config.sh')],
                           capture_output=True, text=True, check=True, timeout=5)
    path = dict(line.split('=', 1) for line in check.stdout.splitlines() if '=' in line)['CONFIG_PATH']
    result = subprocess.run(['bash', str(HERE / 'load-monitor-config.sh'), path],
                            capture_output=True, text=True, check=True, timeout=5)
    values = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if values.get('CONFIG_LOADED') != 'true':
        raise ValueError('Complete Monitor Setup in Hunu before using the switcher.')
    return path, values


def active_monitors():
    result = subprocess.run(['hyprctl', 'monitors', '-j'], capture_output=True,
                            text=True, check=True, timeout=5)
    monitors = {}
    for monitor in json.loads(result.stdout):
        if monitor.get('disabled') or monitor.get('mirrorOf', 'none') != 'none':
            continue
        width, height = int(monitor['width']), int(monitor['height'])
        if int(monitor.get('transform', 0)) % 2:
            width, height = height, width
        if width <= 0 or height <= 0 or monitor['name'] in monitors:
            raise ValueError('Invalid active monitor information.')
        monitors[monitor['name']] = (width, height)
    if not 1 <= len(monitors) <= 3:
        raise ValueError('The switcher requires one to three active monitors.')
    return monitors


def png_size(path):
    with open(path, 'rb') as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('Invalid PNG header.')
    return struct.unpack('>II', header[16:24])


def compatible(item, monitors):
    if item['legacy'] or item['error']:
        return False
    rows = item['monitors']
    if len(rows) != len(monitors) or {row['output'] for row in rows} != set(monitors):
        return False
    try:
        return all(png_size(row['file']) == monitors[row['output']] for row in rows)
    except (OSError, ValueError):
        return False


def listing():
    config, values = configuration()
    monitors = active_monitors()
    layout = saved_sets.load_layout(config)
    if set(layout) != set(monitors):
        raise ValueError('Active outputs differ from Monitor Setup. Update the setup in Hunu first.')
    all_sets = saved_sets.scan(values['OUTPUT_DIR'])
    sets = sorted((item for item in all_sets if compatible(item, monitors)),
                  key=lambda item: (item['modified'], item['name']), reverse=True)
    try:
        last = json.loads(state_path().read_text())
    except (OSError, ValueError):
        last = {}
    current = next((item['name'] for item in sets if
                    {row['output']: str(Path(row['file']).resolve()) for row in item['monitors']} == last), '')
    return {'sets': sets, 'layout': layout, 'current': current,
            'hidden': len(all_sets) - len(sets), 'backend': values['APPLY_BACKEND']}


def apply(item, backend):
    pairs = [value for row in item['monitors'] for value in (row['output'], row['file'])]
    subprocess.run(['bash', str(HERE / 'apply-wallpapers.sh'), '--backend', backend, *pairs], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['list', 'apply', 'next', 'previous', 'record'])
    parser.add_argument('arguments', nargs='*')
    args = parser.parse_args()
    if args.action == 'record':
        if not args.arguments or len(args.arguments) % 2:
            raise ValueError('Expected output/file pairs.')
        remember(args.arguments)
        return
    if args.action == 'list':
        print(json.dumps(listing()))
        return
    # Serialize selection as well as apply, so rapid next/previous advances correctly.
    lock = state_path().with_name('switcher-selection.lock')
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open('a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another wallpaper selection is being applied. Try again.')
        result = listing()  # Recheck current outputs and files at confirmation time.
        sets = result['sets']
        if not sets:
            raise ValueError('No saved sets match the active outputs and resolutions.')
        if args.action == 'apply':
            if len(args.arguments) != 1:
                raise ValueError('Expected one saved set name.')
            item = next((s for s in sets if s['name'] == args.arguments[0]), None)
            if item is None:
                raise ValueError('This set no longer matches the active layout. Reopen the switcher.')
        else:
            index = next((i for i, s in enumerate(sets) if s['name'] == result['current']), None)
            if index is None:
                index = 0 if args.action == 'next' else len(sets) - 1
            else:
                index = (index + (1 if args.action == 'next' else -1)) % len(sets)
            item = sets[index]
        apply(item, result['backend'])


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)

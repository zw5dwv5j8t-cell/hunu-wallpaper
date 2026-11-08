#!/usr/bin/env python3
"""Read and atomically save per-installation wallpaper switcher preferences."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile

HERE = Path(__file__).resolve().parent
DEFAULTS = dict(enabled=True, position='center', livePreview=True, delayMs=400, showActionButtons=True)


def settings_path():
    folder = HERE.parent / 'config' if HERE.name == 'src' and (HERE.parent / 'config').is_dir() else HERE
    return folder / 'switcher-settings.json'


def validate(values):
    if not isinstance(values, dict):
        raise ValueError('Switcher settings must be an object.')
    result = {key: values.get(key, default) for key, default in DEFAULTS.items()}
    if any(type(result[key]) is not bool for key in ('enabled', 'livePreview', 'showActionButtons')):
        raise ValueError('Enable, live preview, and show buttons must be true or false.')
    if result['position'] not in ('top', 'center', 'bottom'):
        raise ValueError('Position must be top, center, or bottom.')
    if type(result['delayMs']) is not int or not 100 <= result['delayMs'] <= 1500:
        raise ValueError('Preview delay must be between 100 and 1500 milliseconds.')
    return result


def load():
    try:
        return validate(json.loads(settings_path().read_text()))
    except FileNotFoundError:
        return dict(DEFAULTS)


def save(values):
    result = validate(values)
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.switcher-settings-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(result, stream, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['get', 'save', 'enabled'])
    parser.add_argument('value', nargs='?')
    args = parser.parse_args()
    if args.action == 'save':
        if args.value is None:
            parser.error('save requires a JSON settings object')
        print(json.dumps(save(json.loads(args.value))))
    elif args.action == 'enabled':
        print('true' if load()['enabled'] else 'false')
    else:
        print(json.dumps(load()))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)

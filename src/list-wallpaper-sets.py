#!/usr/bin/env python3
"""Discover completed Hunu sets and connected outputs without changing files."""
import json
from pathlib import Path
import re
import subprocess
import sys


def scan(directory):
    folder = Path(directory).expanduser().resolve()
    if not folder.exists():
        return []
    groups = {}
    for image in folder.glob('*.png'):
        match = re.fullmatch(r'(.+)_([abc])\.png', image.name)
        if match and image.is_file():
            groups.setdefault(match[1], {})[match[2]] = image
    sets = []
    for prefix, images in groups.items():
        manifest = folder / (prefix + '.hunu.json')
        legacy = not manifest.exists()
        error = ''
        rows = []
        title = prefix
        created = ''
        mode = ''
        ai_scale = None
        if not legacy:
            try:
                data = json.loads(manifest.read_text())
                if data['version'] != 1 or data['set'] != prefix:
                    raise ValueError('Unsupported metadata.')
                records = data['monitors']
                if not isinstance(records, list) or not 1 <= len(records) <= 3:
                    raise ValueError('Invalid monitor list.')
                seen = set()
                outputs = set()
                for record in records:
                    slot = record['slot']
                    output = record['output']
                    if type(slot) is not int or slot not in (1, 2, 3) or slot in seen:
                        raise ValueError('Invalid monitor slot.')
                    if not isinstance(output, str) or not output or output in outputs:
                        raise ValueError('Invalid output assignment.')
                    seen.add(slot)
                    outputs.add(output)
                    name = prefix + '_' + 'abc'[slot - 1] + '.png'
                    if record['file'] != name or not (folder / name).is_file():
                        raise ValueError('A saved wallpaper is missing.')
                    rows.append({'slot': slot, 'output': output,
                                 'file': str(folder / name), 'url': (folder / name).as_uri(),
                                 'offsetX': record.get('offset_x'), 'offsetY': record.get('offset_y')})
                title = data.get('source', prefix)
                created = data.get('created', '')
                mode = data.get('mode', '')
                ai_scale = data.get('ai_scale')
            except (OSError, ValueError, KeyError, TypeError, IndexError):
                error = 'Incomplete or invalid saved set. Apply is unavailable.'
                rows = []
        else:
            for suffix, image in sorted(images.items()):
                rows.append({'slot': 'abc'.index(suffix) + 1, 'output': '',
                             'file': str(image), 'url': image.as_uri()})
        sets.append({'name': prefix, 'title': str(title), 'created': str(created),
                     'legacy': legacy, 'error': error, 'monitors': rows,
                     'mode': mode, 'aiScale': ai_scale,
                     'modified': max(p.stat().st_mtime for p in images.values())})
    return sorted(sets, key=lambda item: item['modified'], reverse=True)


def load_layout(config):
    helper = Path(__file__).resolve().with_name('load-monitor-config.sh')
    result = subprocess.run(['bash', str(helper), config], capture_output=True,
                            text=True, timeout=5, check=True)
    values = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    layout = {}
    for slot in (1, 2, 3):
        prefix = f'MONITOR_{slot}_'
        if values.get(prefix + 'ENABLED') == 'true':
            layout[values[prefix + 'OUTPUT']] = {
                'x': float(values[prefix + 'X_CM']),
                'y': float(values[prefix + 'Y_CM']),
                'w': float(values[prefix + 'PHYSICAL_WIDTH_CM']),
                'h': float(values[prefix + 'PHYSICAL_HEIGHT_CM']),
            }
    return layout


def main():
    outputs = []
    output_error = ''
    try:
        result = subprocess.run(['hyprctl', 'monitors', '-j'], capture_output=True,
                                text=True, timeout=5, check=True)
        outputs = [m['name'] for m in json.loads(result.stdout)
                   if not m.get('disabled', False) and m.get('mirrorOf', 'none') == 'none']
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        output_error = 'Could not detect connected outputs. Close and retry.'
    layout = load_layout(sys.argv[2]) if len(sys.argv) > 2 else {}
    print(json.dumps({'sets': scan(sys.argv[1]), 'outputs': outputs, 'layout': layout,
                      'outputError': output_error}))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, IndexError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)

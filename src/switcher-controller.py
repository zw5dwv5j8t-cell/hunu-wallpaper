#!/usr/bin/env python3
"""Headless saved-set controller used by the short-lived wallpaper picker."""
from concurrent.futures import ThreadPoolExecutor
import argparse
import fcntl
import importlib.util
import json
import os
import shutil
import signal
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('saved_sets', HERE / 'list-wallpaper-sets.py')
saved_sets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(saved_sets)
prefs_spec = importlib.util.spec_from_file_location('switcher_prefs', HERE / 'switcher-settings.py')
switcher_prefs = importlib.util.module_from_spec(prefs_spec)
prefs_spec.loader.exec_module(switcher_prefs)


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
    focused = ''
    for monitor in json.loads(result.stdout):
        if monitor.get('disabled') or monitor.get('mirrorOf', 'none') != 'none':
            continue
        width, height = int(monitor['width']), int(monitor['height'])
        if int(monitor.get('transform', 0)) % 2:
            width, height = height, width
        if width <= 0 or height <= 0 or monitor['name'] in monitors:
            raise ValueError('Invalid active monitor information.')
        monitors[monitor['name']] = (width, height)
        if monitor.get('focused'):
            focused = monitor['name']
    if not 1 <= len(monitors) <= 3:
        raise ValueError('The switcher requires one to three active monitors.')
    return monitors, focused


def png_size(path):
    with open(path, 'rb') as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('Invalid PNG header.')
    return struct.unpack('>II', header[16:24])


def compatible(item, monitors, dimensions=None):
    if item['legacy'] or item['error']:
        return False
    rows = item['monitors']
    if len(rows) != len(monitors) or {row['output'] for row in rows} != set(monitors):
        return False
    try:
        return all((tuple(dimensions.get(row['file'], ())) if dimensions is not None else png_size(row['file']))
                   == monitors[row['output']] for row in rows)
    except (OSError, ValueError):
        return False


def library(directory):
    """Cache discovery and headers; selected files are revalidated before Apply."""
    directory = Path(directory).expanduser().resolve()
    cache = state_path().with_name('switcher-library.json')

    def fingerprint():
        entries = []
        if not directory.exists():
            return []
        with os.scandir(directory) as scan:
            for entry in scan:
                if entry.name.endswith(('.png', '.hunu.json', '.preview.jpg')):
                    stat = entry.stat()
                    entries.append((entry.name, stat.st_size, stat.st_mtime_ns,
                                    stat.st_ctime_ns, stat.st_ino))
        return [list(row) for row in sorted(entries)]

    signature = fingerprint()
    try:
        cached = json.loads(cache.read_text())
        if (cached.get('version') == 1 and cached.get('directory') == str(directory)
                and cached.get('signature') == signature
                and isinstance(cached.get('sets'), list) and isinstance(cached.get('dimensions'), dict)):
            return cached['sets'], cached['dimensions']
    except (OSError, ValueError, AttributeError):
        pass
    items = saved_sets.scan(directory)
    dimensions = {}
    for item in items:
        for row in item['monitors']:
            try:
                dimensions[row['file']] = png_size(row['file'])
            except (OSError, ValueError):
                pass
    temporary = None
    try:
        if fingerprint() == signature:
            cache.parent.mkdir(parents=True, exist_ok=True)
            fd, temporary = tempfile.mkstemp(dir=cache.parent, prefix='.switcher-library-')
            with os.fdopen(fd, 'w') as stream:
                json.dump(dict(version=1, directory=str(directory), signature=signature,
                               sets=items, dimensions=dimensions), stream)
            os.replace(temporary, cache)
    except OSError:
        pass
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
    return items, dimensions


def listing():
    config, values = configuration()
    monitors, focused = active_monitors()
    layout = saved_sets.load_layout(config, values)
    if set(layout) != set(monitors):
        raise ValueError('Active outputs differ from Monitor Setup. Update the setup in Hunu first.')
    all_sets, dimensions = library(values['OUTPUT_DIR'])
    sets = sorted((item for item in all_sets if compatible(item, monitors, dimensions)),
                  key=lambda item: (item['modified'], item['name']), reverse=True)
    for item in sets:
        # Old sets have only monitor crops; choose the widest as a single-image
        # fallback rather than suggesting that the original can be reconstructed.
        widest = max(item['monitors'], key=lambda row: dimensions[row['file']][0] / dimensions[row['file']][1])
        item['fallbackPreviewUrl'] = widest['url']
        item['previewIsSource'] = bool(item['previewUrl'])
        item['previewUrl'] = item['previewUrl'] or widest['url']
    try:
        last = json.loads(state_path().read_text())
    except (OSError, ValueError):
        last = {}
    current = next((item['name'] for item in sets if
                    {row['output']: str(Path(row['file']).resolve()) for row in item['monitors']} == last), '')
    return {'sets': sets, 'layout': layout, 'current': current,
            'hidden': len(all_sets) - len(sets), 'backend': values['APPLY_BACKEND'],
            'switcherSettings': switcher_prefs.load(),
            'focusedOutput': focused, 'outputDirectory': str(Path(values['OUTPUT_DIR']).expanduser().resolve())}


def apply(item, backend):
    pairs = [value for row in item['monitors'] for value in (row['output'], row['file'])]
    subprocess.run(['bash', str(HERE / 'apply-wallpapers.sh'), '--backend', backend, *pairs], check=True)


class SessionStopped(BaseException):
    pass


class PreviewSession:
    """One picker transaction: capture, temporarily apply, then commit or restore."""
    def __init__(self, lock):
        self.lock = lock
        self.backend = ''
        self.original = {}
        self.dirty = False
        self.committed = False
        self.names = set()
        self.directory = None

    def capture(self, result):
        self.backend = result['backend']
        self.names = {item['name'] for item in result['sets']}
        self.directory = Path(result['outputDirectory'])
        if not result['switcherSettings']['livePreview']:
            return False, ''
        if self.backend != 'noctalia' or not shutil.which('noctalia'):
            return False, 'Live preview needs a backend with readable current wallpapers; Enter still applies.'
        def query(output):
            reply = subprocess.run(['timeout', '5', 'noctalia', 'msg', 'wallpaper-get', output],
                                   capture_output=True, text=True, check=True, timeout=6)
            path = Path(reply.stdout.strip()).expanduser()
            if not path.is_absolute() or not path.is_file():
                raise ValueError(f'Current wallpaper for {output} is not a readable file.')
            return output, str(path.resolve())

        try:
            with ThreadPoolExecutor(max_workers=3) as pool:
                self.original = dict(pool.map(query, result['layout']))
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            self.original = {}
            return False, f'Live preview unavailable: {error} Enter still applies.'
        return True, ''

    def apply_pairs(self, pairs):
        env = dict(os.environ, HUNU_PREVIEW_ONLY='1', HUNU_APPLY_LOCK_FD=str(self.lock.fileno()))
        result = subprocess.run(['bash', str(HERE / 'apply-wallpapers.sh'), '--backend', self.backend, *pairs],
                                env=env, pass_fds=(self.lock.fileno(),), capture_output=True, text=True)
        if result.returncode:
            raise ValueError(result.stderr.strip() or 'Wallpaper Apply failed.')

    def select(self, name, commit=False):
        # Revalidate only the selected set, not every image in the library.
        # Names must come from the initial listing, never an arbitrary path.
        _, values = configuration()
        if values['APPLY_BACKEND'] != self.backend:
            raise ValueError('Apply backend changed. Cancel and reopen the picker.')
        if Path(values['OUTPUT_DIR']).expanduser().resolve() != self.directory:
            raise ValueError('Wallpaper folder changed. Cancel and reopen the picker.')
        monitors, _ = active_monitors()
        configured = {values[f'MONITOR_{i}_OUTPUT'] for i in (1, 2, 3)
                      if values.get(f'MONITOR_{i}_ENABLED') == 'true'}
        if configured != set(monitors):
            raise ValueError('Active outputs differ from Monitor Setup.')
        item = next((s for s in saved_sets.scan(self.directory, name) if compatible(s, monitors)), None) if name in self.names else None
        if item is None:
            raise ValueError('This set no longer matches the active layout.')
        pairs = [value for row in item['monitors'] for value in (row['output'], row['file'])]
        # Mark dirty before the first output, since a backend can fail halfway.
        self.dirty = bool(self.original)
        try:
            self.apply_pairs(pairs)
            if commit:
                remember(pairs)
                self.committed = True
                self.dirty = False
        except (OSError, ValueError, subprocess.SubprocessError):
            self.restore()
            raise

    def restore(self):
        if not self.dirty:
            return
        monitors, _ = active_monitors()
        pairs = [value for output, path in self.original.items() if output in monitors
                 for value in (output, path)]
        if pairs:
            self.apply_pairs(pairs)
        self.dirty = False


def run_session():
    def send(event, **values):
        print(json.dumps(dict(event=event, **values)), flush=True)

    def stop(_signal, _frame):
        raise SessionStopped()

    path = state_path().with_name('wallpaper-apply.lock')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another wallpaper Apply or picker session is in progress.')
        session = PreviewSession(lock)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        try:
            result = listing()
            send('catalog', **result)
            live, reason = session.capture(result)
            if live:
                result['current'] = next((s['name'] for s in result['sets'] if
                    {row['output']: str(Path(row['file']).resolve()) for row in s['monitors']} == session.original), '')
            send('ready', **result, liveEnabled=live, liveReason=reason)
            for line in sys.stdin:
                action = ''
                try:
                    request = json.loads(line)
                    action = request['action']
                    if action == 'cancel':
                        session.restore()
                        send('cancelled')
                        return
                    if action not in ('preview', 'commit'):
                        raise ValueError('Unknown picker action.')
                    if action == 'preview' and not live:
                        raise ValueError(reason)
                    name = request['name']
                    session.select(name, commit=action == 'commit')
                    send('committed' if action == 'commit' else 'previewed', name=name)
                    if action == 'commit':
                        return
                except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
                    send('error', action=action, message=str(error))
        except SessionStopped:
            pass
        finally:
            # EOF or normal termination of the picker is cancellation too.
            # Ignore a second TERM while restoring; SIGKILL cannot be recovered.
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            if not session.committed:
                session.restore()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['list', 'apply', 'next', 'previous', 'record', 'session'])
    parser.add_argument('arguments', nargs='*')
    args = parser.parse_args()
    if args.action in ('session', 'apply', 'next', 'previous') and not switcher_prefs.load()['enabled']:
        raise ValueError('Wallpaper switcher is disabled in Hunu Settings.')
    if args.action == 'session':
        run_session()
        return
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

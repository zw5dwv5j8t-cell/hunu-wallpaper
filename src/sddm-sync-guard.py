#!/usr/bin/env python3
"""Optional Noctalia hook: coalesce SDDM sync until Hunu browsing has finished."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent


def cache_directory():
    app = os.environ.get('HUNU_APP_NAME') or HERE.name
    if app == 'src':
        app = 'hunu-wallpaper'
    return Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / app


@contextmanager
def gate(folder):
    with (folder / 'queue.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def pending(folder):
    return json.loads((folder / 'pending.json').read_text())


def picker_open(cache):
    # Probe only: holding this lock throughout rendering would block hotkeys.
    with (cache / 'wallpaper-apply.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
    return False


def stop_job(job):
    if job is None:
        return
    # The sync script and ImageMagick children share this private process group.
    try:
        os.killpg(job.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        job.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(job.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    job.wait()


def work(cache, folder, worker_fd):
    job = None
    completed = None
    def terminated(_signum, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, terminated)
    signal.signal(signal.SIGINT, terminated)
    try:
        while True:
            with gate(folder):
                request = pending(folder)
                if request['token'] == completed:
                    # Release under the producer's gate to avoid lost wakeups.
                    fcntl.flock(worker_fd, fcntl.LOCK_UN)
                    return
            if picker_open(cache) or time.monotonic() - request['time'] < 0.4:
                time.sleep(0.1)
                continue
            env = dict(os.environ, MAGICK_THREAD_LIMIT='1', OMP_NUM_THREADS='1')
            # Refresh every monitor from current state, not an obsolete event.
            env.pop('NOCTALIA_WALLPAPER_CONNECTOR', None)
            job = subprocess.Popen([request['script']], env=env, start_new_session=True)
            interrupted = False
            while job.poll() is None:
                time.sleep(0.1)
                with gate(folder):
                    changed = pending(folder)['token'] != request['token']
                if changed or picker_open(cache):
                    interrupted = True
                    break
            if interrupted:
                stop_job(job)
                job = None
                continue
            status = job.wait()
            stop_job(job)  # Also reap descendants if a script exited early.
            job = None
            if status:
                print(f'SDDM sync exited with status {status}; see the sync script output above.', flush=True)
            completed = request['token']
    finally:
        stop_job(job)
        os.close(worker_fd)


def enqueue(cache, folder, script):
    with gate(folder):
        target = folder / 'pending.json'
        temporary = folder / 'pending.tmp'
        temporary.write_text(json.dumps(dict(token=uuid.uuid4().hex, time=time.monotonic(), script=str(script))))
        temporary.replace(target)
        with (folder / 'worker.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return
            with (folder / 'sync.log').open('w') as log:
                subprocess.Popen([sys.executable, str(Path(__file__).resolve()),
                                  '--worker-fd', str(lock.fileno())],
                                 pass_fds=(lock.fileno(),), start_new_session=True,
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=log)
            # Closing our descriptor leaves the inherited worker lock held.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--script', type=Path, default=Path.home() / '.local/bin/sddm-wallpaper-sync')
    parser.add_argument('--worker-fd', type=int, help=argparse.SUPPRESS)
    args = parser.parse_args()
    cache = cache_directory()
    folder = cache / 'sddm-sync'
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.worker_fd is not None:
        work(cache, folder, args.worker_fd)
    else:
        script = args.script.expanduser().resolve()
        if script == Path(__file__).resolve() or not script.is_file() or not os.access(script, os.X_OK):
            parser.error('The sync script must be an executable file, distinct from this guard.')
        enqueue(cache, folder, script)


if __name__ == '__main__':
    main()

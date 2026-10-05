#!/usr/bin/env python3
"""Run one captured Hunu job, forwarding progress and handling cancellation."""
import argparse
import fcntl
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time

CANCELLED = threading.Event()
PRINT_LOCK = threading.Lock()
SCRIPT_DIR = Path(__file__).resolve().parent


def emit(line):
    with PRINT_LOCK:
        print(line, flush=True)


def request_cancel(_signal, _frame):
    CANCELLED.set()


def stop_group(pid, sig):
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        pass


def run_stage(command, phase, description):
    if CANCELLED.is_set():
        return 130, {}
    emit("JOB_PHASE=" + phase)
    emit("JOB_STAGE=" + description)
    emit("JOB_PROGRESS=-1")
    process = subprocess.Popen(
        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
        start_new_session=True,
    )
    values = {}

    def read_stdout():
        for line in process.stdout:
            line = line.rstrip("\r\n")
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
            emit(line)

    def read_stderr():
        for line in process.stderr:
            sys.stderr.write(line)
            sys.stderr.flush()
            if phase == "upscale":
                match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)%\s*", line)
                if match:
                    value = min(99.0, max(0.0, float(match.group(1))))
                    emit("JOB_PROGRESS=" + str(value))

    readers = [threading.Thread(target=read_stdout),
               threading.Thread(target=read_stderr)]
    for reader in readers:
        reader.start()
    deadline = None
    while process.poll() is None or any(r.is_alive() for r in readers):
        if CANCELLED.is_set():
            if deadline is None:
                emit("JOB_STAGE=Cancelling — cleaning up…")
                stop_group(process.pid, signal.SIGTERM)
                deadline = time.monotonic() + 3
            elif time.monotonic() >= deadline:
                stop_group(process.pid, signal.SIGKILL)
        time.sleep(0.05)
    for reader in readers:
        reader.join()
    process.stdout.close()
    process.stderr.close()
    return process.returncode, values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scale", choices=["1", "2", "3", "4"], required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if len(command) < 2 or Path(command[0]).resolve() != SCRIPT_DIR / "split-wallpaper.sh":
        parser.error("Expected split-wallpaper.sh and its source image after --")
    if "--probe" in command:
        parser.error("Probes must run directly, not through the generation controller")
    # Capture the original filename before upscaling changes the input path.
    command.extend(["--source-name", Path(command[1]).name])

    signal.signal(signal.SIGTERM, request_cancel)
    signal.signal(signal.SIGINT, request_cancel)
    resolver = subprocess.run(
        ["bash", "-c", 'source "$1"; hunu_cache_directory', "bash",
         str(SCRIPT_DIR / "cache-path.sh")],
        capture_output=True, text=True, check=True,
    )
    cache_dir = Path(resolver.stdout.rstrip("\n"))
    cache_dir.mkdir(parents=True, exist_ok=True)
    with (cache_dir / ".hunu-cache.lock").open("a") as cache_lock:
        emit("JOB_STAGE=Waiting for AI cache access…")
        while True:
            if CANCELLED.is_set():
                return 130
            try:
                fcntl.flock(cache_lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                CANCELLED.wait(0.1)

        if args.scale != "1":
            code, values = run_stage(
                ["bash", str(SCRIPT_DIR / "upscale-image.sh"),
                 "--input", command[1], "--scale", args.scale],
                "upscale", "AI upscaling source " + args.scale + "×…",
            )
            if CANCELLED.is_set():
                return 130
            if code != 0:
                return code if code > 0 else 1
            if values.get("UPSCALE_STATUS") != "OK" or not values.get("UPSCALE_OUTPUT"):
                raise RuntimeError("Upscaling returned no successful output image.")
            command[1] = values["UPSCALE_OUTPUT"]

        code, _ = run_stage(["bash"] + command, "split", "Generating wallpapers…")
        if CANCELLED.is_set():
            return 130
        if code == 0:
            emit("JOB_PROGRESS=100")
        return code if code >= 0 else 1


if __name__ == "__main__":
    try:
        result = main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print("ERROR: " + str(error), file=sys.stderr, flush=True)
        result = 1
    if result == 130:
        emit("JOB_CANCELLED=true")
    sys.exit(result)

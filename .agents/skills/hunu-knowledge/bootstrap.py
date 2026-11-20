#!/usr/bin/env python3
"""Prepare the pinned Hunu Knowledge runtime and print its checkout path."""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REPOSITORY = "zw5dwv5j8t-cell/hunu-knowledge"
ORIGIN = f"https://github.com/{REPOSITORY}.git"


def git(root, *args):
    return subprocess.run(
        ["git", "-C", str(root), *args], capture_output=True, text=True,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"}, timeout=120,
    )


def identity(root):
    top = git(root, "rev-parse", "--show-toplevel")
    if top.returncode or Path(top.stdout.strip()).resolve() != root:
        return False
    # Read the configured URL, before Git's platform proxy URL rewrites.
    origin = git(root, "config", "--local", "--get", "remote.origin.url")
    return origin.returncode == 0 and origin.stdout.strip().removesuffix(".git") in {
        ORIGIN.removesuffix(".git"), f"git@github.com:{REPOSITORY}",
        f"ssh://git@github.com/{REPOSITORY}",
    }


def clean_runtime(root, pin):
    metadata = root / ".git"
    if root.is_symlink() or metadata.is_symlink() or not metadata.is_dir() or not identity(root):
        return False
    head = git(root, "rev-parse", "--verify", "HEAD")
    status = git(root, "status", "--porcelain", "--untracked-files=all", "--ignored")
    return (head.returncode == status.returncode == 0 and head.stdout.strip() == pin
            and not status.stdout and (root / "integration/v1/client.py").is_file())


def initialize(project):
    config = json.loads((project / ".codex/hunu-knowledge.json").read_text())
    if (not isinstance(config, dict) or type(config.get("version")) is not int
            or config["version"] != 1 or config.get("repository") != REPOSITORY):
        raise ValueError("invalid project configuration or unexpected knowledge repository")
    pin = config.get("runtime_commit")
    if not isinstance(pin, str) or not re.fullmatch(r"[0-9a-f]{40}", pin):
        raise ValueError("runtime_commit must be a full lowercase Git commit SHA")

    override = os.environ.get("HUNU_KNOWLEDGE_RUNTIME")
    if override:
        candidate = Path(override).expanduser().resolve()
        if candidate == project or not candidate.is_dir() or not identity(candidate):
            raise ValueError("HUNU_KNOWLEDGE_RUNTIME must identify a Hunu Knowledge checkout")
        candidates = [candidate]
    else:
        candidates = [parent / name for parent in dict.fromkeys((project.parent, Path("/workspace")))
                      for name in ("hunu-knowledge", "hunu-knowledge-runtime")]

    cache = Path(tempfile.gettempdir()).resolve() / f"hunu-knowledge-{os.getuid()}"
    cache.mkdir(mode=0o700, exist_ok=True)
    if cache.is_symlink() or cache.stat().st_uid != os.getuid() or cache.stat().st_mode & 0o077:
        raise ValueError(f"runtime cache must be a private directory owned by this user: {cache}")
    target = cache / pin
    with (cache / f"{pin}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if target.exists() or target.is_symlink():
            if not clean_runtime(target, pin):
                raise ValueError(f"conflicting cached runtime at {target}; inspect it before moving it aside")
            return target

        with tempfile.TemporaryDirectory(dir=cache, prefix="staging-") as stage:
            checkout = Path(stage) / "runtime"
            checkout.mkdir()
            if git(checkout, "init", "-q").returncode or git(checkout, "remote", "add", "origin", ORIGIN).returncode:
                raise ValueError("could not initialize the isolated Git checkout")
            for candidate in candidates:
                candidate = candidate.resolve()
                if candidate != project and candidate.is_dir() and identity(candidate):
                    if git(checkout, "fetch", "--no-tags", str(candidate), pin).returncode == 0:
                        break
            else:
                if git(checkout, "fetch", "--no-tags", "origin", pin).returncode:
                    raise ValueError(f"cannot fetch pinned commit {pin}; check private Git read access and pin availability")
            if git(checkout, "checkout", "--detach", pin).returncode or not clean_runtime(checkout, pin):
                raise ValueError(f"pinned commit {pin} does not contain a usable clean runtime")
            checkout.rename(target)
    return target


if __name__ == "__main__":
    try:
        print(initialize(Path(__file__).resolve().parents[3]))
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        sys.exit(f"Hunu Knowledge bootstrap blocked: {exc}")

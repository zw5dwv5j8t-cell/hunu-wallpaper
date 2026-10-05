#!/usr/bin/env python3
"""Check the latest Hunu release without downloading or installing it."""

import json
import re
import sys
import urllib.error
import urllib.request

REPOSITORY = "zw5dwv5j8t-cell/hunu-wallpaper"
API_URL = f"https://api.github.com/repos/{REPOSITORY}/releases/latest"


def parse_version(value):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", value)
    if not match:
        raise ValueError("Unrecognized version number.")
    return tuple(int(part) for part in match.groups())


def main():
    if len(sys.argv) != 2:
        raise ValueError("Provide the installed version.")

    installed = parse_version(sys.argv[1])
    request = urllib.request.Request(
        API_URL,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "Hunu-Wallpaper-Splitter",
        },
    )

    with urllib.request.urlopen(request, timeout=10) as response:
        release = json.load(response)

    if not isinstance(release, dict):
        raise ValueError("Unexpected release response.")

    tag = release.get("tag_name")
    if not isinstance(tag, str):
        raise ValueError("The release has no version tag.")

    latest = parse_version(tag)
    status = "available" if latest > installed else "current"

    print(f"UPDATE_STATUS={status}")
    print(f"UPDATE_VERSION={tag.removeprefix('v')}")
    print(
        f"UPDATE_URL=https://github.com/{REPOSITORY}/releases/tag/{tag}"
    )
    return 0


if __name__ == "__main__":
    try:
        exit_code = main()
    except urllib.error.HTTPError as error:
        print("UPDATE_STATUS=error")
        if error.code in (403, 429):
            print("UPDATE_MESSAGE=GitHub refused the check. Try again later.")
        else:
            print(f"UPDATE_MESSAGE=GitHub returned HTTP {error.code}.")
        exit_code = 1
    except (OSError, ValueError) as error:
        print("UPDATE_STATUS=error")
        print("UPDATE_MESSAGE=Could not check for updates. Try again later.")
        print(str(error), file=sys.stderr)
        exit_code = 1

    sys.exit(exit_code)
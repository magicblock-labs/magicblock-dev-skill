#!/usr/bin/env python3
"""Validate the skill version and require bumps against a Git base revision."""

import argparse
from pathlib import Path
import re
import subprocess

VERSION_PATH = "skill/VERSION"
VERSION_PATTERN = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"


def parse_version(value):
    value = value.strip()
    if not re.fullmatch(VERSION_PATTERN, value):
        raise ValueError("skill/VERSION must contain a stable MAJOR.MINOR.PATCH version")
    return tuple(map(int, value.split(".")))


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True, stderr=subprocess.PIPE)


def check(root, base=None):
    current = (root / VERSION_PATH).read_text().strip()
    current_version = parse_version(current)
    if base is None:
        return

    # A missing base or failed Git command must fail the check, not look like a first release.
    git(root, "rev-parse", "--verify", f"{base}^{{commit}}")
    base_paths = git(root, "ls-tree", "-r", "--name-only", base).splitlines()
    if VERSION_PATH not in base_paths:
        if current_version != (0, 1, 0):
            raise ValueError("The initial tracked version must be 0.1.0")
        return

    previous = parse_version(git(root, "show", f"{base}:{VERSION_PATH}"))
    if current_version < previous:
        raise ValueError("The skill version cannot decrease")
    changed = git(root, "diff", "--name-only", "-z", "--no-renames", base, "--").split("\0")
    skill_changed = any(path.startswith("skill/") or path in ("build.sh", "install.sh")
                        for path in changed)
    if skill_changed and current_version <= previous:
        raise ValueError("Skill or packaging changed: increase skill/VERSION")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Git base revision to compare, e.g. origin/main")
    args = parser.parse_args()
    try:
        check(Path(__file__).resolve().parents[1], args.base)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Version check failed: {error}\n")
    print("Version check passed")


if __name__ == "__main__":
    main()

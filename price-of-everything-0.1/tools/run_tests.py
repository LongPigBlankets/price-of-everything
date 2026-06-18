#!/usr/bin/env python3
"""Cross-platform headless test runner for Price of Everything.

Detects the OS, locates the Godot 4 binary, and runs res://tests/test_runner.tscn.
The runner exits 0 if all tests pass, 1 if any fail (get_tree().quit in test_runner.gd).

Usage:
    python3 tools/run_tests.py
    GODOT_BIN=/path/to/godot python3 tools/run_tests.py   # explicit override

To locate Godot it tries, in order: $GODOT_BIN, anything named godot/godot4 on PATH,
then OS-specific install locations (macOS .app bundles / Windows download folders).
"""
import glob
import os
import platform
import shutil
import subprocess
import sys

# Project dir = the folder holding project.godot (this script lives in tools/).
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def candidate_paths():
    """Yield possible Godot binary paths, most-specific first."""
    env = os.environ.get("GODOT_BIN")
    if env:
        yield env
    for name in ("godot", "godot4", "Godot"):
        found = shutil.which(name)
        if found:
            yield found

    system = platform.system()
    home = os.path.expanduser("~")
    if system == "Darwin":
        yield os.path.join(home, "Desktop", "Godot.app", "Contents", "MacOS", "Godot")
        yield "/Applications/Godot.app/Contents/MacOS/Godot"
        yield os.path.join(home, "Applications", "Godot.app", "Contents", "MacOS", "Godot")
        for app in glob.glob("/Applications/Godot*.app"):
            yield os.path.join(app, "Contents", "MacOS", "Godot")
    elif system == "Windows":
        for pattern in (
            os.path.join(home, "Downloads", "Godot_v4.*win64*", "*console*.exe"),
            os.path.join(home, "Downloads", "Godot_v4.*win64*.exe"),
            r"C:\Program Files\Godot\*.exe",
        ):
            yield from glob.glob(pattern)


def find_godot():
    for path in candidate_paths():
        if not path or not os.path.isfile(path):
            continue
        # On Windows os.access(X_OK) is unreliable; a .exe file is enough.
        if platform.system() == "Windows" or os.access(path, os.X_OK):
            return path
    return None


def main():
    godot = find_godot()
    if not godot:
        sys.exit(
            "Godot binary not found.\n"
            "Set it explicitly, e.g.:\n"
            "    GODOT_BIN=/path/to/Godot python3 tools/run_tests.py"
        )

    print(f"OS:      {platform.system()} ({platform.machine()})")
    print(f"Godot:   {godot}")
    print(f"Project: {PROJECT_DIR}")
    print("-" * 60)

    cmd = [
        godot, "--headless", "--path", PROJECT_DIR,
        "res://tests/test_runner.tscn", "--quit-after", "600",
    ]
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()

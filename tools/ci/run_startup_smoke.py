#!/usr/bin/env python3
"""Boot an exported demo in isolation; require readiness, exit 0 and clean logs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


ERROR = re.compile(
    r"^\s*(?:(?:SCRIPT |USER )?ERROR:|(?:Parse|Parser) Error:|"
    r"FATAL(?: ERROR)?:|.*Program crashed|.*handle_crash:)", re.MULTILINE
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")
MARKERS = {"fresh": "[STARTUP] eula_ready", "accepted": "[STARTUP] main_menu_ready"}


def check_output(output: str, returncode: int, expected: str) -> None:
    output = ANSI.sub("", output)
    errors = [line for line in output.splitlines() if ERROR.search(line)]
    if errors:
        raise RuntimeError("Engine errors: " + "\n".join(errors[:20]))
    if returncode != 0:
        raise RuntimeError(f"Game exited with code {returncode}")
    if expected not in output.splitlines():
        raise RuntimeError(f"Missing startup milestone: {expected}")
    other = MARKERS["accepted"] if expected == MARKERS["fresh"] else MARKERS["fresh"]
    if other in output.splitlines():
        raise RuntimeError(f"Unexpected startup milestone: {other}")


def run_game(command: list[str], cwd: Path, logs: Path, phase: str, timeout: float) -> dict:
    console = logs / f"{phase}-console.log"
    engine = logs / f"{phase}-engine.log"
    env = os.environ.copy()
    # AppPaths uses the binary's private directory; XDG covers the OS fallback.
    for key, suffix in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                        ("XDG_CACHE_HOME", "cache")):
        env[key] = str(cwd / suffix)
    started = time.monotonic()
    with console.open("w", encoding="utf-8") as stream:
        try:
            result = subprocess.run(
                [*command, "--headless", "--max-fps", "60", "--quit-after", "1200",
                 "--log-file", str(engine), "--", "--no-telemetry"],
                cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT,
                timeout=timeout, check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"{phase} launch exceeded {timeout}s (see {console})") from error
    output = console.read_text(encoding="utf-8", errors="replace")
    if not engine.is_file() or not engine.stat().st_size:
        raise RuntimeError(f"Missing engine log: {engine}")
    output += "\n" + engine.read_text(encoding="utf-8", errors="replace")
    check_output(output, result.returncode, MARKERS[phase])
    return {"phase": phase, "seconds": round(time.monotonic() - started, 2),
            "exit_code": result.returncode, "milestone": MARKERS[phase]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True,
                        help="Exported executable with embedded PCK (not the editor)")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2]
                        / "price-of-everything-0.1")
    parser.add_argument("--logs", type=Path, required=True, help="A new output directory")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    binary, project, logs = args.executable.resolve(), args.project.resolve(), args.logs.resolve()
    logs.mkdir(parents=True, exist_ok=False)  # Never pass using a stale log.
    summary = {"launches": [], "passed": False}
    try:
        digest = hashlib.sha256()
        with binary.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        summary["executable_sha256"] = digest.hexdigest()
        with tempfile.TemporaryDirectory(prefix="cnc-startup-") as temporary:
            isolated = Path(temporary)
            target = isolated / binary.name
            shutil.copy2(binary, target)
            target.chmod(target.stat().st_mode | 0o100)
            summary["launches"].append(run_game([str(target)], isolated, logs, "fresh", args.timeout))
            record = isolated / "savegames" / "demo_eula.cfg"
            if record.exists():
                raise RuntimeError("Fresh startup unexpectedly accepted the EULA")
            # Fixture for a returning player, in disposable data only. No auto-accept
            # switch is shipped in the game, and no real player's record is changed.
            agreement = (project / "data/legal/demo_eula.txt").read_text(encoding="utf-8").strip()
            version = re.search(r'^const VERSION := "([^"]+)"',
                                (project / "scripts/demo_eula.gd").read_text(), re.MULTILINE)
            if not agreement or version is None:
                raise RuntimeError("Could not read the current EULA fixture")
            record.parent.mkdir(parents=True, exist_ok=True)
            record.write_text(
                f'[agreement]\nversion="{version[1]}"\n'
                f'sha256="{hashlib.sha256(agreement.encode()).hexdigest()}"\n', encoding="utf-8")
            summary["launches"].append(run_game([str(target)], isolated, logs, "accepted", args.timeout))
            summary["passed"] = True
    except (RuntimeError, OSError) as error:
        summary["failure"] = str(error)
        print(f"FAIL: {error}", flush=True)
    finally:
        (logs / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if summary["passed"]:
        print("PASS: exported demo reached the EULA and main menu without engine errors", flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

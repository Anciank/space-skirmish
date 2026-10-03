#!/usr/bin/env python3
"""Import a clean checkout and run gameplay suites, rejecting engine errors too."""

from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

SUITES = ("input_test", "flight_systems", "camera_stability", "player_gunnery", "audio_mix", "combat_feedback", "round_flow", "localization", "smoke_test", "ai_gunnery", "ai_combat", "soak_match")
PROBLEMS = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING:|\s+FAIL\s)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or shutil.which("godot4"))
    parser.add_argument("--suite", choices=SUITES, action="append", help="Run only the named suite(s)")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Godot 4 is required; set --godot to its executable")
    project = pathlib.Path(__file__).resolve().parent.parent
    log_dir = pathlib.Path(tempfile.mkdtemp(prefix="star-skirmish-checks-"))
    jobs = [("import", ["--editor", "--import", "--quit"])]
    jobs += [(name, ["--fixed-fps", "60", f"res://tests/{name}.tscn"]) for name in args.suite or SUITES]
    failed = False
    for name, options in jobs:
        command = [args.godot, "--path", str(project), "--headless", *options]
        try:
            if name != "import":
                preflight = [args.godot, "--path", str(project), "--headless", "res://tools/script_check.tscn", "--", f"res://tests/{name}.gd"]
                result = subprocess.run(preflight, capture_output=True, text=True, timeout=20, check=False)
                if result.returncode == 0 and not PROBLEMS.search(result.stdout + result.stderr):
                    result = subprocess.run(command, capture_output=True, text=True, timeout=120, check=False)
            else:
                result = subprocess.run(command, capture_output=True, text=True, timeout=60, check=False)
            output = result.stdout + result.stderr
            ok = result.returncode == 0 and not PROBLEMS.search(output)
        except subprocess.TimeoutExpired as error:
            output = f"Timed out after {error.timeout} seconds\n"
            output += (error.stdout or b"").decode(errors="replace")
            output += (error.stderr or b"").decode(errors="replace")
            ok = False
        path = log_dir / f"{name}.log"
        path.write_text(output)
        checks = re.findall(r"--- .*?(?:checks, \d+ failures|\d+ failures) ---", output)
        detail = checks[-1] if checks else ""
        print(f"{'PASS' if ok else 'FAIL'}  {name} {detail}", flush=True)
        if not ok:
            failed = True
            print(f"      {path}", flush=True)
            if name == "import":
                break
    print(f"Logs: {log_dir}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

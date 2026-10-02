#!/usr/bin/env python3
"""Verify, export and package the Linux release using matching official templates."""
from __future__ import annotations

import argparse
import datetime
import gzip
import hashlib
import json
import os
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile

PROJECT = pathlib.Path(__file__).resolve().parent.parent
PROBLEMS = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING:|\s+FAIL\s)")
GAME_DIRECTORIES = ("scenes", "scripts", "shaders")
GAME_FILES = ("project.godot", "icon.svg", "default_bus_layout.tres", "export_presets.cfg")
FORBIDDEN = ("tests/", "tools/", "captures/", "dist/", "builds/")


def run(command: list[str], log: pathlib.Path, *, timeout: int = 180, env: dict | None = None, cwd: pathlib.Path = PROJECT) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, timeout=timeout, check=False)
    output = result.stdout + result.stderr
    log.write_text(output)
    if result.returncode or PROBLEMS.search(output):
        raise RuntimeError(f"Command failed; see {log}")
    return output


def source_digest() -> str:
    paths = [PROJECT / name for name in GAME_FILES]
    for directory in GAME_DIRECTORIES:
        paths.extend(path for path in (PROJECT / directory).rglob("*") if path.is_file())
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(PROJECT).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def read_pack(path: pathlib.Path) -> dict[str, bytes]:
    """Read and verify unencrypted Godot PCK v3/v4 file records and checksums."""
    data = path.read_bytes()
    magic, version, _, _, _, flags = struct.unpack_from("<6I", data)
    if magic != 0x43504447 or version not in (3, 4) or flags != 2:
        raise RuntimeError("Expected an unencrypted, relative-base Godot PCK v3/v4")
    file_base, directory = struct.unpack_from("<2Q", data, 24)
    count = struct.unpack_from("<I", data, directory)[0]
    cursor = directory + 4
    files = {}
    for _ in range(count):
        length = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        name = data[cursor:cursor + length].rstrip(b"\0").decode()
        cursor += length
        offset, size = struct.unpack_from("<2Q", data, cursor)
        expected = data[cursor + 16:cursor + 32]
        file_flags = struct.unpack_from("<I", data, cursor + 32)[0]
        cursor += 36
        payload = data[file_base + offset:file_base + offset + size]
        if file_flags or len(payload) != size or hashlib.md5(payload).digest() != expected:
            raise RuntimeError(f"Invalid packed resource or checksum: {name}")
        if name in files or name.startswith("/") or ".." in pathlib.PurePosixPath(name).parts:
            raise RuntimeError(f"Invalid resource name: {name}")
        files[name] = payload
    return files


def canonical_game(files: dict[str, bytes]) -> dict[str, str]:
    result = {}
    for name, payload in files.items():
        if name.startswith(("scenes/", "scripts/", "shaders/")) or name.startswith("default_bus_layout.tres") or name == "icon.svg":
            key = name.removesuffix(".remap")
            if name.endswith(".remap"):
                match = re.search(rb'path="res://([^"]+)"', payload)
                if not match or match[1].decode() not in files:
                    raise RuntimeError(f"Missing remapped game resource: {name}")
                payload = files[match[1].decode()]
            result[key] = hashlib.sha256(payload).hexdigest()
    return result


def write_pack(path: pathlib.Path, files: dict[str, bytes]) -> None:
    """Repack verified shipping payloads verbatim with the separate QA entry point."""
    base = 112
    records = []
    with path.open("wb") as output:
        output.write(struct.pack("<6I2Q16I", 0x43504447, 4, 4, 7, 2, 2, base, 0, *([0] * 16)))
        output.write(bytes(base - output.tell()))
        for name, payload in sorted(files.items()):
            records.append((name, output.tell() - base, len(payload), hashlib.md5(payload).digest()))
            output.write(payload)
            output.write(bytes((-output.tell()) % 16))
        directory = output.tell()
        output.write(struct.pack("<I", len(records)))
        for name, offset, size, checksum in records:
            encoded = name.encode()
            encoded += bytes((-len(encoded)) % 4)
            output.write(struct.pack("<I", len(encoded)) + encoded + struct.pack("<2Q", offset, size) + checksum + struct.pack("<I", 0))
        output.seek(32)
        output.write(struct.pack("<Q", directory))


def add_qa_entry_point(path: pathlib.Path, shipping: dict[str, bytes]) -> None:
    # Fresh exports rewrite binary scene reference paths for their cache directory.
    # Keep every shipping game payload and its remap intact instead of testing a
    # second conversion of those scenes. Add only the QA scene/script and startup.
    qa = read_pack(path)
    merged = shipping.copy()
    merged["project.binary"] = qa["project.binary"]
    merged[".godot/uid_cache.bin"] = qa[".godot/uid_cache.bin"]
    for name, payload in qa.items():
        if name.startswith("tools/release_smoke."):
            merged[name] = payload
            if name.endswith(".remap"):
                target = re.search(rb'path="res://([^"]+)"', payload)[1].decode()
                merged[target] = qa[target]
    write_pack(path, merged)


def qa_project(destination: pathlib.Path) -> None:
    # Only the QA main scene and project entry point differ from the shipping game.
    for directory in GAME_DIRECTORIES:
        shutil.copytree(PROJECT / directory, destination / directory)
    for name in GAME_FILES:
        shutil.copy2(PROJECT / name, destination / name)
    (destination / "tools").mkdir()
    for path in (PROJECT / "tools").glob("release_smoke.*"):
        shutil.copy2(path, destination / "tools" / path.name)
    config = (destination / "project.godot").read_text().replace('run/main_scene="res://scenes/main.tscn"', 'run/main_scene="res://tools/release_smoke.tscn"')
    (destination / "project.godot").write_text(config)
    preset = (destination / "export_presets.cfg").read_text().replace("tools/*,", "")
    (destination / "export_presets.cfg").write_text(preset)


def launcher(compatibility: bool = False) -> str:
    options = ' --rendering-method gl_compatibility --rendering-driver opengl3' if compatibility else ''
    return '#!/bin/sh\nset -eu\nbase_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\nexec "$base_dir/star-skirmish.x86_64"' + options + ' "$@"\n'


def archive_release(folder: pathlib.Path, path: pathlib.Path) -> None:
    with path.open("wb") as output, gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w|") as tar:
        for source in [folder, *sorted(folder.rglob("*"))]:
            info = tar.gettarinfo(str(source), arcname=str(pathlib.Path(folder.name) / source.relative_to(folder)))
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            if source.is_file():
                with source.open("rb") as payload:
                    tar.addfile(info, payload)
            else:
                tar.addfile(info)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or shutil.which("godot4"))
    parser.add_argument("--output", type=pathlib.Path, default=PROJECT / "dist")
    parser.add_argument("--native", action="store_true", help="Also drive the shipping executable through a native X11 window")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Godot 4.7.2 is required; use --godot to select it")
    args.godot = str(pathlib.Path(args.godot).resolve())
    version = re.search(r'config/version="([\w.\-]+)"', (PROJECT / "project.godot").read_text())[1]
    slug = f"star-skirmish-{version}-linux-x86_64"
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / ".gdignore").touch()
    logs = pathlib.Path(tempfile.mkdtemp(prefix="star-skirmish-release-"))
    print(f"Build logs: {logs}", flush=True)
    fingerprint = source_digest()
    try:
        engine = run([args.godot, "--version"], logs / "engine.log").strip()
        if not engine.startswith("4.7.2.stable."):
            raise RuntimeError(f"Release is pinned to Godot 4.7.2 stable; found {engine}")
        output = run([sys.executable, str(PROJECT / "tools/verify.py"), "--godot", args.godot], logs / "verification.log", timeout=900)
        print(output.strip(), flush=True)
        with tempfile.TemporaryDirectory(prefix=".release-build-", dir=args.output) as work:
            stage = pathlib.Path(work)
            (stage / ".gdignore").touch()
            package = stage / slug
            package.mkdir()
            binary = package / "star-skirmish.x86_64"
            run([args.godot, "--headless", "--path", str(PROJECT), "--export-release", "Linux", str(binary)], logs / "export.log")
            binary.chmod(0o755)
            files = read_pack(binary.with_suffix(".pck"))
            forbidden = [name for name in files if name.startswith(FORBIDDEN)]
            if forbidden:
                raise RuntimeError(f"Non-game resources found in shipping pack: {forbidden}")
            print(f"PASS  shipping pack: {len(files)} resources, {binary.with_suffix('.pck').stat().st_size:,} bytes; no QA or captures", flush=True)
            qa_source = stage / "qa-project"
            qa_source.mkdir()
            qa_project(qa_source)
            qa_binary = stage / "qa-runtime" / "star-skirmish.x86_64"
            qa_binary.parent.mkdir()
            run([args.godot, "--headless", "--path", str(qa_source), "--editor", "--import", "--quit"], logs / "qa-import.log")
            run([args.godot, "--headless", "--path", str(qa_source), "--export-release", "Linux", str(qa_binary)], logs / "qa-export.log")
            if hashlib.sha256(binary.read_bytes()).digest() != hashlib.sha256(qa_binary.read_bytes()).digest():
                raise RuntimeError("QA and shipping runtimes differ")
            add_qa_entry_point(qa_binary.with_suffix(".pck"), files)
            if canonical_game(files) != canonical_game(read_pack(qa_binary.with_suffix(".pck"))):
                raise RuntimeError("QA and shipping game resource payloads differ")
            print("PASS  QA and shipping runtime plus game resource hashes match", flush=True)
            env = os.environ.copy()
            env["XDG_DATA_HOME"] = str(stage / "qa-user-data")
            for name, renderer in [("forward", []), ("compatibility", ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"])]:
                output = run([str(qa_binary), "--headless", "--fixed-fps", "60", *renderer], logs / f"runtime-{name}.log", env=env, cwd=stage)
                if not re.search(r"--- release smoke: \d+ checks, 0 failures ---", output):
                    raise RuntimeError("Exported runtime did not complete its smoke checks")
                print(f"PASS  exported {name} lifecycle: " + re.search(r"--- release smoke: .*? ---", output)[0], flush=True)
            if args.native:
                run([sys.executable, str(PROJECT / "tools/native_release_check.py"), str(binary), "--output", str(logs / "native")], logs / "native-check.log", timeout=120)
                run([sys.executable, str(PROJECT / "tools/native_release_check.py"), str(binary), "--output", str(logs / "native-compatibility"), "--compatibility"], logs / "native-compatibility-check.log", timeout=120)
                print("PASS  shipping executable native keyboard flow and captures in both renderers", flush=True)
            notices = package / "licenses"
            run([args.godot, "--headless", "--path", str(PROJECT), "res://tools/export_licenses.tscn", "--", str(notices)], logs / "licenses.log")
            for name, compatibility in [("play.sh", False), ("play-compatibility.sh", True)]:
                path = package / name
                path.write_text(launcher(compatibility))
                path.chmod(0o755)
            (package / "README.txt").write_text((PROJECT / "RELEASE_README.txt").read_text().replace("@VERSION@", version))
            (package / "CREDITS.txt").write_text("Star Skirmish\n\nShips, scenery, effects, music and sounds are generated by this project's original code.\nGodot Engine and its bundled components are credited in the licenses directory and in-game Credits.\n")
            manifest = {
                "game": "Star Skirmish", "version": version, "platform": "Linux x86_64",
                "godot": engine, "source_sha256": fingerprint,
                "built_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "verification": {"gameplay_suites": 8, "exported_lifecycle_renderers": ["forward", "compatibility"], "native_shipping_renderers": ["forward", "compatibility"] if args.native else []},
                "packed_resources": len(files),
                "files": {path.relative_to(package).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(package.rglob("*")) if path.is_file()},
            }
            (package / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
            if source_digest() != fingerprint:
                raise RuntimeError("Game sources changed during the build; rebuild to package the verified version")
            archive = stage / f"{slug}.tar.gz"
            archive_release(package, archive)
            destination = args.output / slug
            archive_destination = args.output / archive.name
            # Replace an older candidate only after all gates and packaging succeed.
            if destination.exists():
                shutil.rmtree(destination)
            shutil.move(str(package), destination)
            os.replace(archive, archive_destination)
            checksum = hashlib.sha256(archive_destination.read_bytes()).hexdigest()
            (args.output / f"{slug}.tar.gz.sha256").write_text(f"{checksum}  {archive_destination.name}\n")
            print(f"Release: {destination}\nArchive: {archive_destination}\nSHA256: {checksum}", flush=True)
            return 0
    except (RuntimeError, OSError, subprocess.TimeoutExpired, ValueError) as error:
        print(f"BUILD FAILED: {error}\nLogs: {logs}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

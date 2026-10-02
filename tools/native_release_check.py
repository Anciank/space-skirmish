#!/usr/bin/env python3
"""Drive the shipping Linux executable through X11 and capture its native window."""
from __future__ import annotations

import argparse
import ctypes as C
import ctypes.util
import json
import os
import pathlib
import re
import struct
import subprocess
import tempfile
import time
import zlib


class Image(C.Structure):
    _fields_ = [("width", C.c_int), ("height", C.c_int), ("xoffset", C.c_int), ("format", C.c_int),
                ("data", C.c_void_p), ("byte_order", C.c_int), ("bitmap_unit", C.c_int),
                ("bitmap_bit_order", C.c_int), ("bitmap_pad", C.c_int), ("depth", C.c_int),
                ("bytes_per_line", C.c_int), ("bits_per_pixel", C.c_int),
                ("red_mask", C.c_ulong), ("green_mask", C.c_ulong), ("blue_mask", C.c_ulong)]


class ClientMessage(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int),
                ("display", C.c_void_p), ("window", C.c_ulong), ("message_type", C.c_ulong),
                ("format", C.c_int), ("data", C.c_long * 5)]


class KeyEvent(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int),
                ("display", C.c_void_p), ("window", C.c_ulong), ("root", C.c_ulong),
                ("subwindow", C.c_ulong), ("time", C.c_ulong), ("x", C.c_int), ("y", C.c_int),
                ("x_root", C.c_int), ("y_root", C.c_int), ("state", C.c_uint),
                ("keycode", C.c_uint), ("same_screen", C.c_int)]


class Event(C.Union):
    _fields_ = [("client", ClientMessage), ("key", KeyEvent), ("padding", C.c_long * 24)]


class Desktop:
    def __init__(self) -> None:
        self.x = C.CDLL(ctypes.util.find_library("X11"))
        self.x.XOpenDisplay.argtypes, self.x.XOpenDisplay.restype = [C.c_char_p], C.c_void_p
        self.x.XDefaultRootWindow.argtypes, self.x.XDefaultRootWindow.restype = [C.c_void_p], C.c_ulong
        self.x.XInternAtom.argtypes, self.x.XInternAtom.restype = [C.c_void_p, C.c_char_p, C.c_int], C.c_ulong
        self.x.XQueryTree.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]
        self.x.XGetWindowProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_long, C.c_long, C.c_int, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.c_void_p)]
        self.x.XFree.argtypes = [C.c_void_p]
        self.x.XRaiseWindow.argtypes = [C.c_void_p, C.c_ulong]
        self.x.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
        self.x.XFlush.argtypes = [C.c_void_p]
        self.x.XCloseDisplay.argtypes = [C.c_void_p]
        self.x.XStringToKeysym.argtypes, self.x.XStringToKeysym.restype = [C.c_char_p], C.c_ulong
        self.x.XKeysymToKeycode.argtypes, self.x.XKeysymToKeycode.restype = [C.c_void_p, C.c_ulong], C.c_ubyte
        self.x.XGetGeometry.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
        self.x.XGetImage.argtypes, self.x.XGetImage.restype = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_ulong, C.c_int], C.POINTER(Image)
        self.x.XDestroyImage.argtypes = [C.POINTER(Image)]
        self.x.XSendEvent.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(Event)]
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("Native check requires an X11 DISPLAY")
        # Window disappearance during a tree query is harmless; Python controls exit.
        self.error_handler = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p)(lambda *_: 0)
        self.x.XSetErrorHandler.argtypes = [C.c_void_p]
        self.x.XSetErrorHandler(self.error_handler)
        self.root = self.x.XDefaultRootWindow(self.display)
        self.pid_atom = self.x.XInternAtom(self.display, b"_NET_WM_PID", 0)
        self.held: set[str] = set()
        self.window = 0

    def _pid(self, window: int) -> int:
        kind, fmt, count, after, data = C.c_ulong(), C.c_int(), C.c_ulong(), C.c_ulong(), C.c_void_p()
        self.x.XGetWindowProperty(self.display, window, self.pid_atom, 0, 1, 0, 0, C.byref(kind), C.byref(fmt), C.byref(count), C.byref(after), C.byref(data))
        result = C.cast(data, C.POINTER(C.c_ulong))[0] if data.value and count.value and fmt.value == 32 else 0
        if data.value:
            self.x.XFree(data)
        return result

    def _find(self, window: int, pid: int, depth: int = 0) -> int:
        if self._pid(window) == pid:
            return window
        if depth >= 4:
            return 0
        root, parent, children, count = C.c_ulong(), C.c_ulong(), C.POINTER(C.c_ulong)(), C.c_uint()
        if not self.x.XQueryTree(self.display, window, C.byref(root), C.byref(parent), C.byref(children), C.byref(count)):
            return 0
        result = 0
        for child in [children[i] for i in range(count.value)]:
            result = self._find(child, pid, depth + 1)
            if result:
                break
        if children:
            self.x.XFree(children)
        return result

    def focus(self, process: subprocess.Popen) -> None:
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError("Shipping game exited before creating a window")
            self.window = self._find(self.root, process.pid)
            if self.window:
                self.x.XRaiseWindow(self.display, self.window)
                self.x.XSetInputFocus(self.display, self.window, 2, 0)
                self.x.XFlush(self.display)
                # The native window exists while shaders and the first menu are
                # still initializing. Let deferred control focus settle too.
                time.sleep(3.0)
                return
            time.sleep(0.1)
        raise RuntimeError("Could not find the shipping game's X11 window")

    def set_key(self, name: str, down: bool) -> None:
        code = self.x.XKeysymToKeycode(self.display, self.x.XStringToKeysym(name.encode()))
        if not code:
            raise RuntimeError(f"No X11 keycode for {name}")
        event = Event()
        event.key.type = 2 if down else 3
        event.key.display = self.display
        event.key.window = self.window
        event.key.root = self.root
        event.key.keycode = code
        event.key.same_screen = 1
        event.key.state = 1 if "Shift_L" in self.held or "Shift_R" in self.held else 0
        # Send native X11 key events to this game's window. XTest input may be
        # redirected by a remote desktop's separate keyboard seat.
        self.x.XSendEvent(self.display, self.window, 0, 1 if down else 2, C.byref(event))
        self.x.XFlush(self.display)
        self.held.add(name) if down else self.held.discard(name)

    def key(self, name: str, delay: float = 0.25) -> None:
        self.set_key(name, True)
        time.sleep(0.06)
        self.set_key(name, False)
        time.sleep(delay)

    def capture(self, path: pathlib.Path) -> tuple[int, int]:
        root, x, y, width, height, border, depth = C.c_ulong(), C.c_int(), C.c_int(), C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
        self.x.XGetGeometry(self.display, self.window, C.byref(root), C.byref(x), C.byref(y), C.byref(width), C.byref(height), C.byref(border), C.byref(depth))
        pointer = self.x.XGetImage(self.display, self.window, 0, 0, width, height, C.c_ulong(-1), 2)
        if not pointer:
            raise RuntimeError("Could not capture the native game window")
        image = pointer.contents
        try:
            if image.bits_per_pixel != 32 or image.byte_order != 0 or (image.red_mask, image.green_mask, image.blue_mask) != (0xFF0000, 0xFF00, 0xFF):
                raise RuntimeError("Native capture currently requires a standard 32-bit X11 visual")
            raw = C.string_at(image.data, image.bytes_per_line * image.height)
            rows = bytearray()
            for line in range(image.height):
                row = raw[line * image.bytes_per_line:line * image.bytes_per_line + image.width * 4]
                rgb = bytearray(image.width * 3)
                rgb[0::3], rgb[1::3], rgb[2::3] = row[2::4], row[1::4], row[0::4]
                rows.append(0)
                rows.extend(rgb)
            def chunk(tag: bytes, content: bytes) -> bytes:
                return struct.pack(">I", len(content)) + tag + content + struct.pack(">I", zlib.crc32(tag + content))
            png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", image.width, image.height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")
            path.write_bytes(png)
            return image.width, image.height
        finally:
            self.x.XDestroyImage(pointer)

    def close_window(self) -> None:
        event = Event()
        event.client.type = 33
        event.client.display = self.display
        event.client.window = self.window
        event.client.message_type = self.x.XInternAtom(self.display, b"WM_PROTOCOLS", 0)
        event.client.format = 32
        event.client.data[0] = self.x.XInternAtom(self.display, b"WM_DELETE_WINDOW", 0)
        self.x.XSendEvent(self.display, self.window, 0, 0, C.byref(event))
        self.x.XFlush(self.display)

    def close(self) -> None:
        for name in tuple(self.held):
            self.set_key(name, False)
        self.x.XCloseDisplay(self.display)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--compatibility", action="store_true")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    game_log = args.output / "game.log"
    desktop = Desktop()
    process = None
    captures = {}
    work = tempfile.TemporaryDirectory(prefix="star-skirmish-native-")
    try:
        with game_log.open("w") as log:
            env = os.environ.copy()
            env["XDG_DATA_HOME"] = str(pathlib.Path(work.name) / "user-data")
            env["XMODIFIERS"] = "@im=none"
            options = ["--display-driver", "x11", "--resolution", "1280x720", "--max-fps", "60"]
            if args.compatibility:
                options += ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"]
            # Deliberately launch from outside the project and package directory.
            process = subprocess.Popen([str(args.binary.resolve()), *options], cwd=work.name, env=env, stdout=log, stderr=subprocess.STDOUT)
            desktop.focus(process)
            def capture(name: str) -> None:
                captures[name] = desktop.capture(args.output / f"{name}.png")
            capture("title")
            desktop.key("Return", 1.0)
            capture("flight")
            desktop.set_key("w", True)
            desktop.set_key("space", True)
            time.sleep(3.0)
            desktop.set_key("Shift_L", True)
            time.sleep(1.0)
            capture("boost")
            for name in ("Shift_L", "w", "space"):
                desktop.set_key(name, False)
            desktop.key("Tab")
            time.sleep(0.4)
            capture("combat")
            desktop.key("Escape", 0.4)
            capture("pause")
            desktop.key("Tab")
            desktop.key("Return")
            capture("settings")
            desktop.key("Escape")
            desktop.key("Escape")
            desktop.set_key("backslash", True)
            time.sleep(0.3)
            capture("scoreboard")
            desktop.set_key("backslash", False)
            desktop.key("F5", 0.7)
            desktop.key("Escape")
            for _ in range(4):
                desktop.key("Tab", 0.08)
            desktop.key("Return", 0.5)
            capture("return-title")
            for _ in range(4):
                desktop.key("Tab", 0.08)
            desktop.key("Return")
            capture("credits")
            desktop.key("Escape")
            for _ in range(3):
                desktop.key("Tab", 0.08)
            desktop.key("Return", 0.5)
            if process.wait(timeout=10):
                raise RuntimeError("Shipping executable exited with an error")
        output = game_log.read_text()
        if re.search(r"(?m)^(SCRIPT ERROR:|ERROR:|WARNING:)", output):
            raise RuntimeError(f"Shipping runtime reported an error or warning; see {game_log}")
        report = {"renderer": "compatibility" if args.compatibility else "forward", "exit_code": process.returncode, "captures": captures, "actions": "deploy, thrust, fire, boost, lock, pause, settings, resume, scoreboard, restart, return to command, credits, quit", "isolated_preferences": True}
        (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Native shipping run completed with clean exit and {len(captures)} captures: {args.output}")
        return 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"NATIVE CHECK FAILED: {error}")
        return 1
    finally:
        if process is not None and process.poll() is None:
            desktop.close_window()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
        desktop.close()
        work.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())

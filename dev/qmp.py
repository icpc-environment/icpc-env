#!/usr/bin/env python3
"""Minimal QMP client for driving the dev VM (screenshots, keyboard, mouse).

Stdlib only. The socket path comes from $QMP_SOCK.

  qmp.py screenshot <out.png>
  qmp.py key <combo>...          e.g. ctrl-alt-t ret f1
  qmp.py type <text>
  qmp.py click <x> <y> [left|right|middle] [--double]
  qmp.py move <x> <y>
  qmp.py scroll <up|down> [count]
  qmp.py hmp <human monitor command>
  qmp.py raw <json command>
"""
import json
import os
import socket
import struct
import sys
import tempfile
import time

# Absolute pointer coordinates (usb-tablet) are scaled to 0..0x7fff
ABS_MAX = 0x7FFF

KEY_ALIASES = {
    "enter": "ret", "return": "ret", "space": "spc", "escape": "esc",
    "super": "meta_l", "win": "meta_l", "meta": "meta_l",
    "pageup": "pgup", "pagedown": "pgdn", "del": "delete", "bksp": "backspace",
    "control": "ctrl",
}

# US layout: char -> (qcode, shift)
UNSHIFTED = {
    " ": "spc", "\n": "ret", "\t": "tab", "-": "minus", "=": "equal",
    "[": "bracket_left", "]": "bracket_right", "\\": "backslash",
    ";": "semicolon", "'": "apostrophe", "`": "grave_accent",
    ",": "comma", ".": "dot", "/": "slash",
}
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
    "*": "8", "(": "9", ")": "0", "_": "minus", "+": "equal",
    "{": "bracket_left", "}": "bracket_right", "|": "backslash",
    ":": "semicolon", '"': "apostrophe", "~": "grave_accent",
    "<": "comma", ">": "dot", "?": "slash",
}


class QMP:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buf = b""
        self._recv()  # greeting
        self.cmd("qmp_capabilities")

    def _recv(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("QMP socket closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def cmd(self, execute, **arguments):
        msg = {"execute": execute}
        if arguments:
            msg["arguments"] = arguments
        return self.send(msg)

    def send(self, msg):
        self.sock.sendall(json.dumps(msg).encode() + b"\n")
        while True:
            resp = self._recv()
            if "event" in resp:
                continue
            if "error" in resp:
                raise RuntimeError(f"{msg.get('execute')}: {resp['error'].get('desc')}")
            return resp.get("return")


def png_size(path):
    with open(path, "rb") as f:
        header = f.read(24)
    return struct.unpack(">II", header[16:24])


def screen_size(q):
    fd, path = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    try:
        q.cmd("screendump", filename=path, format="png")
        return png_size(path)
    finally:
        os.unlink(path)


def keyspec(name):
    name = KEY_ALIASES.get(name.lower(), name.lower())
    return {"type": "qcode", "data": name}


def char_keys(c):
    if c in UNSHIFTED:
        return [UNSHIFTED[c]]
    if c in SHIFTED:
        return ["shift", SHIFTED[c]]
    if c.isascii() and c.isalpha():
        return ["shift", c.lower()] if c.isupper() else [c]
    if c.isascii() and c.isdigit():
        return [c]
    raise ValueError(f"don't know how to type {c!r}")


def move(q, x, y):
    w, h = screen_size(q)
    if not (0 <= x < w and 0 <= y < h):
        raise ValueError(f"({x},{y}) is outside the {w}x{h} screen")
    q.cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": round(x * ABS_MAX / (w - 1))}},
        {"type": "abs", "data": {"axis": "y", "value": round(y * ABS_MAX / (h - 1))}},
    ])


def button(q, btn, down):
    q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": down, "button": btn}}])


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    sock = os.environ.get("QMP_SOCK")
    if not sock or not os.path.exists(sock):
        print(f"QMP socket {sock!r} not found - is the VM running?", file=sys.stderr)
        return 1
    q = QMP(sock)
    op, args = argv[1], argv[2:]

    if op == "screenshot":
        out = os.path.abspath(args[0])
        q.cmd("screendump", filename=out, format="png")
        w, h = png_size(out)
        print(f"{out} ({w}x{h})")
    elif op == "key":
        for combo in args:
            q.cmd("send-key", keys=[keyspec(k) for k in combo.split("-")])
            time.sleep(0.15)
        # send-key returns before QEMU has delivered the queued events
        time.sleep(0.3)
    elif op == "type":
        for c in " ".join(args):
            q.cmd("send-key", keys=[keyspec(k) for k in char_keys(c)], **{"hold-time": 20})
            time.sleep(0.04)
        time.sleep(1)
    elif op in ("click", "move"):
        x, y = int(args[0]), int(args[1])
        move(q, x, y)
        if op == "click":
            btn = next((a for a in args[2:] if not a.startswith("-")), "left")
            for _ in range(2 if "--double" in args else 1):
                time.sleep(0.05)
                button(q, btn, True)
                time.sleep(0.05)
                button(q, btn, False)
    elif op == "scroll":
        btn = "wheel-up" if args[0] == "up" else "wheel-down"
        for _ in range(int(args[1]) if len(args) > 1 else 3):
            button(q, btn, True)
            button(q, btn, False)
            time.sleep(0.03)
    elif op == "hmp":
        out = q.cmd("human-monitor-command", **{"command-line": " ".join(args)})
        if out:
            print(out, end="")
    elif op == "raw":
        print(json.dumps(q.send(json.loads(" ".join(args))), indent=2))
    else:
        print(f"unknown op {op!r}\n{__doc__}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (RuntimeError, ValueError, ConnectionError) as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

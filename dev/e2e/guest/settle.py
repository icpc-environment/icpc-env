#!/usr/bin/python3 -I
# Wait until the screen stops changing. Polls the root window every 200ms and
# compares it as a 16x16 grid of tiles, ignoring the top panel and bottom 50px
# (status bars with progress animations) and changes of 2 tiles or fewer
# (blinking carets, the panel clock).
# Prints the time of the last change and exits once nothing has changed for
# QUIET seconds, or after TIMEOUT seconds (exit status 1).
import sys, time, zlib
from Xlib import X, display

quiet = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 120.0

d = display.Display()
root = d.screen().root
geo = root.get_geometry()
W, H = geo.width, geo.height
TOP, BOTTOM = 28, H - 50
COLS, ROWS = 16, 16
tw = W // COLS
rows_per = (BOTTOM - TOP) // ROWS

def grab():
    raw = root.get_image(0, TOP, W, BOTTOM - TOP, X.ZPixmap, 0xffffffff).data
    stride = len(raw) // (BOTTOM - TOP)
    sig = []
    for r in range(ROWS):
        crcs = [0] * COLS
        for y in range(r * rows_per, (r + 1) * rows_per, 2):
            base = y * stride
            for c in range(COLS):
                crcs[c] = zlib.crc32(raw[base + c * tw * 4: base + (c + 1) * tw * 4], crcs[c])
        sig.extend(crcs)
    return sig

start = time.time()
prev = grab()
last_change = start
while True:
    time.sleep(0.2)
    now = time.time()
    cur = grab()
    if sum(a != b for a, b in zip(prev, cur)) > 2:
        last_change = now
    prev = cur
    if now - last_change >= quiet:
        print(f"{last_change:.3f}")
        sys.exit(0)
    if now - start >= timeout:
        print(f"{last_change:.3f}")
        sys.exit(1)

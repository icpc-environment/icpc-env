#!/usr/bin/python3 -I
# How many distinct strong hues a window shows: colors.py WINDOW_ID
# Syntax-highlighted code has several (keywords, strings, numbers, comments);
# a plain-text view has none or one. Prints the number of 30-degree hue
# buckets with at least 25 sampled pixels (text is thin, so this is an
# absolute count rather than a share of the window).
import colorsys, sys
from Xlib import X, display

d = display.Display()
root = d.screen().root
win = d.create_resource_object("window", int(sys.argv[1], 0))
g = win.get_geometry()
pos = win.translate_coords(root, 0, 0)
x, y = -pos.x, -pos.y
w, h = g.width, g.height
img = root.get_image(x, y, w, h, X.ZPixmap, 0xffffffff).data
buckets = [0] * 12
step = 2  # sample every 2nd pixel in each direction
n = 0
for row in range(0, h, step):
    base = row * w * 4
    for col in range(0, w, step):
        b, gr, r = img[base + col * 4], img[base + col * 4 + 1], img[base + col * 4 + 2]
        n += 1
        hh, ss, vv = colorsys.rgb_to_hsv(r / 255, gr / 255, b / 255)
        if ss > 0.25 and vv > 0.3:
            buckets[int(hh * 12) % 12] += 1
print(sum(1 for c in buckets if c >= 25))

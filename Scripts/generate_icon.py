#!/usr/bin/env python3
"""Renders the AETHER app icon (1024x1024, opaque) with Pillow."""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Assets/AppIcon-1024.png")


def vertical_gradient(top, bottom):
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(SIZE):
            px[x, y] = row
    return img


def iso(cx, cy, r, x, y, z):
    """Project cube-grid coordinates (unit cube, centred) to screen space."""
    dx = r * math.cos(math.radians(30))
    dy = r * math.sin(math.radians(30))
    return (cx + (x - y) * dx, cy + (x + y) * dy - z * r)


def draw_cube(draw, cx, cy, r, top, left, right):
    p = lambda x, y, z: iso(cx, cy, r, x, y, z)
    draw.polygon([p(0, 0, 1), p(1, 0, 1), p(1, 1, 1), p(0, 1, 1)], fill=top)
    draw.polygon([p(0, 1, 1), p(1, 1, 1), p(1, 1, 0), p(0, 1, 0)], fill=left)
    draw.polygon([p(1, 0, 1), p(1, 1, 1), p(1, 1, 0), p(1, 0, 0)], fill=right)


bg = vertical_gradient((24, 27, 30), (8, 9, 10))

glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse((212, 212, 812, 812), fill=(40, 150, 70))
glow = glow.filter(ImageFilter.GaussianBlur(150))
bg = Image.blend(bg, Image.composite(glow, bg, glow.convert("L")), 0.55)

layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
cx, cy, r = SIZE / 2, SIZE / 2, 300
draw_cube(d, cx, cy, r, (112, 224, 130, 255), (46, 130, 72, 255), (30, 96, 54, 255))

# Inset pixel on the top face
a = lambda x, y: iso(cx, cy, r, x, y, 1)
d.polygon([a(0.3, 0.3), a(0.7, 0.3), a(0.7, 0.7), a(0.3, 0.7)], fill=(60, 170, 90, 255))
d.polygon([a(0.4, 0.4), a(0.6, 0.4), a(0.6, 0.6), a(0.4, 0.6)], fill=(150, 240, 165, 255))

bg = bg.convert("RGBA")
bg.alpha_composite(layer)
OUT.parent.mkdir(parents=True, exist_ok=True)
bg.convert("RGB").save(OUT, "PNG")
print(f"wrote {OUT} ({SIZE}x{SIZE})")

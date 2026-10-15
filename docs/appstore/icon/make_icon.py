#!/usr/bin/env python3
"""Generates the Vocabi app icon from a single geometry definition.

Outputs:
  docs/appstore/icon/vocabi-icon.svg   (hand-authored vector source, for designers)
  App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png  (1024x1024 RGB, no alpha)

Rasterised with Pillow at 4x and downsampled (no rsvg/inkscape needed).
Usage: python3 docs/appstore/icon/make_icon.py
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SVG_OUT = os.path.join(ROOT, "docs/appstore/icon/vocabi-icon.svg")
PNG_OUT = os.path.join(ROOT, "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

N = 1024
# Brand palette: deep plum, single hue
BG_TOP = (0x6B, 0x22, 0x80)     # #6B2280
BG_BOTTOM = (0x24, 0x08, 0x33)  # #240833
TILE = (0xFF, 0xF4, 0xEA)       # warm paper
GLYPH = (0x4A, 0x14, 0x60)      # #4A1460
LINE = (0xFF, 0x7A, 0x6B)       # coral "description" line
GHOST_ALPHA = 0.20              # back tile = second widget slot

BACK = (272, 192, 832, 752)
FRONT = (192, 272, 752, 832)
RADIUS = 124
V = [(352, 372), (438, 372), (472, 532), (506, 372), (592, 372), (514, 640), (430, 640)]
BAR = (372, 702, 572, 744)  # rounded bar under the glyph


def hexc(c):
    return "#%02X%02X%02X" % c


def write_svg():
    pts = " ".join(f"{x},{y}" for x, y in V)
    r = (BAR[3] - BAR[1]) / 2
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{N}" height="{N}" viewBox="0 0 {N} {N}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="{hexc(BG_TOP)}"/>
      <stop offset="1" stop-color="{hexc(BG_BOTTOM)}"/>
    </linearGradient>
  </defs>
  <rect width="{N}" height="{N}" fill="url(#bg)"/>
  <rect x="{BACK[0]}" y="{BACK[1]}" width="{BACK[2]-BACK[0]}" height="{BACK[3]-BACK[1]}" rx="{RADIUS}" fill="#FFFFFF" fill-opacity="{GHOST_ALPHA}"/>
  <rect x="{FRONT[0]}" y="{FRONT[1]}" width="{FRONT[2]-FRONT[0]}" height="{FRONT[3]-FRONT[1]}" rx="{RADIUS}" fill="{hexc(TILE)}"/>
  <polygon points="{pts}" fill="{hexc(GLYPH)}"/>
  <rect x="{BAR[0]}" y="{BAR[1]}" width="{BAR[2]-BAR[0]}" height="{BAR[3]-BAR[1]}" rx="{r:g}" fill="{hexc(LINE)}"/>
</svg>
"""
    with open(SVG_OUT, "w") as f:
        f.write(svg)


def render_png(scale=4):
    S = N * scale
    sc = lambda box: tuple(v * scale for v in box)
    # gradient matching the SVG vector (0,0)->(0.35,1)
    grad = Image.new("RGB", (S, S))
    gx, gy = 0.35, 1.0
    norm = gx * gx + gy * gy
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = max(0.0, min(1.0, ((x / 255) * gx + (y / 255) * gy) / norm))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM))
    grad = small.resize((S, S), Image.BICUBIC)

    img = grad.convert("RGBA")
    ghost = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ghost).rounded_rectangle(sc(BACK), radius=RADIUS * scale,
                                            fill=(255, 255, 255, round(255 * GHOST_ALPHA)))
    img = Image.alpha_composite(img, ghost)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(sc(FRONT), radius=RADIUS * scale, fill=TILE)
    d.polygon([(x * scale, y * scale) for x, y in V], fill=GLYPH)
    d.rounded_rectangle(sc(BAR), radius=(BAR[3] - BAR[1]) * scale // 2, fill=LINE)
    out = img.convert("RGB").resize((N, N), Image.LANCZOS)
    os.makedirs(os.path.dirname(PNG_OUT), exist_ok=True)
    out.save(PNG_OUT, "PNG", optimize=True)


if __name__ == "__main__":
    write_svg()
    render_png()
    print("wrote", SVG_OUT)
    print("wrote", PNG_OUT)

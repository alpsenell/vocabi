#!/usr/bin/env python3
"""Frame raw simulator screenshots into 1290x2796 App Store images.

  raw/<locale>/*.png  --(captions.json)-->  out/<locale>/NN-<stem>.png

Each output has a brand-plum caption band at the top with the localized caption,
and the screenshot below it with rounded corners inside a thin device bezel.

Requires: python3 + Pillow  (pip3 install Pillow)
Usage:
  python3 scripts/screenshots/compose.py                 # all locales found in raw/
  python3 scripts/screenshots/compose.py --locale tr     # one locale
  python3 scripts/screenshots/compose.py --raw DIR --out DIR --captions FILE
"""
import argparse
import json
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:  # pragma: no cover
    sys.exit("compose.py needs Pillow: pip3 install Pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1290, 2796                      # iPhone 6.9" App Store size (portrait)
BAND_H = 620                           # caption band height
PLUM_TOP = (0x7B, 0x2D, 0x8E)          # brand accent #7B2D8E
PLUM_BOTTOM = (0x24, 0x08, 0x33)       # deep plum #240833
PAPER = (0xFF, 0xF4, 0xEA)
CORAL = (0xFF, 0x7A, 0x6B)
BEZEL = (0x14, 0x05, 0x1C)
LOCALES = ["en-US", "tr", "fr-FR", "es-ES"]

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                f = ImageFont.truetype(path, size)
                try:  # SF is a variable font; pick a heavy weight if supported
                    f.set_variation_by_name("Bold")
                except Exception:
                    pass
                return f
            except OSError:
                continue
    return ImageFont.load_default(size=size)


def vertical_gradient(w, h, top, bottom):
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((w, h), Image.BICUBIC)


def wrap(draw, text, font, max_w):
    words, lines, cur = text.split(), [], ""
    for word in words:
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=font) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def fit_caption(draw, text, max_w, max_h):
    """Largest font size (<=104) for which the wrapped caption fits in max_w x max_h, max 3 lines."""
    for size in range(104, 47, -4):
        font = load_font(size)
        lines = wrap(draw, text, font, max_w)
        line_h = round(size * 1.18)
        if len(lines) <= 3 and line_h * len(lines) <= max_h and \
                all(draw.textlength(l, font=font) <= max_w for l in lines):
            return font, lines, line_h
    font = load_font(48)
    return font, wrap(draw, text, font, max_w), 57


def compose(raw_path, caption, out_path):
    canvas = vertical_gradient(W, H, PLUM_TOP, PLUM_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    # caption band
    margin = 96
    font, lines, line_h = fit_caption(draw, caption, W - 2 * margin, BAND_H - 200)
    block_h = line_h * len(lines)
    y = 150 + (BAND_H - 150 - 70 - block_h) // 2
    for line in lines:
        lw = draw.textlength(line, font=font)
        draw.text(((W - lw) / 2, y), line, font=font, fill=PAPER)
        y += line_h
    # small coral "description" bar under the caption (icon motif)
    draw.rounded_rectangle(((W - 160) // 2, 120, (W + 160) // 2, 136), radius=8, fill=CORAL)

    # device screenshot
    shot = Image.open(raw_path).convert("RGB")
    avail_w, avail_h = W - 2 * 130, H - BAND_H - 60
    scale = min(avail_w / shot.width, avail_h / shot.height)
    sw, sh = round(shot.width * scale), round(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    sx, top = (W - sw) // 2, BAND_H
    radius = round(sw * 0.11)
    bezel = 22

    # soft shadow
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (sx - bezel, top - bezel + 24, sx + sw + bezel, top + sh + bezel + 24),
        radius=radius + bezel, fill=(0, 0, 0, 120))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((sx - bezel, top - bezel, sx + sw + bezel, top + sh + bezel),
                           radius=radius + bezel, fill=BEZEL)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=radius, fill=255)
    canvas.paste(shot, (sx, top), mask)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)


def caption_for(captions, idx, stem):
    """captions is either a list (matched by sorted index) or a dict keyed by file stem."""
    if isinstance(captions, dict):
        return captions.get(stem)
    return captions[idx] if idx < len(captions) else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", default=os.path.join(HERE, "raw"))
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    ap.add_argument("--captions", default=os.path.join(HERE, "captions.json"))
    ap.add_argument("--locale", action="append", help="limit to locale(s); default: all in raw/")
    args = ap.parse_args()

    with open(args.captions, encoding="utf-8") as f:
        all_caps = json.load(f)
    locales = args.locale or [l for l in LOCALES if os.path.isdir(os.path.join(args.raw, l))]
    if not locales:
        sys.exit(f"no raw screenshots found under {args.raw}/<locale>/")

    total = 0
    for loc in locales:
        src = os.path.join(args.raw, loc)
        files = sorted(f for f in os.listdir(src) if f.lower().endswith(".png")) if os.path.isdir(src) else []
        caps = all_caps.get(loc)
        if caps is None:
            sys.exit(f"captions.json has no entry for {loc}")
        for i, name in enumerate(files):
            stem = os.path.splitext(name)[0]
            cap = caption_for(caps, i, stem)
            if not cap:
                print(f"  ! {loc}/{name}: no caption, skipped", file=sys.stderr)
                continue
            out = os.path.join(args.out, loc, f"{stem}.png")
            compose(os.path.join(src, name), cap, out)
            total += 1
            print(f"  {loc}/{name} -> {out}")
    print(f"composed {total} screenshot(s) at {W}x{H}")


if __name__ == "__main__":
    main()

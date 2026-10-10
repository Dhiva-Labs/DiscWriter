#!/usr/bin/env python3
"""Renders the Disc Writer app icon at every size the packages install.

    python3 tool/make_icon.py        # writes assets/icon/discwriter_<size>.png

Drawn procedurally (Pillow) so the icon is reproducible and has no external
source file: a dark rounded tile holding an iridescent disc, with an orange
"burned" data band and a laser glint, matching the in-app gauge.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZES = [16, 32, 48, 64, 128, 256, 512]
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icon')
LASER = (255, 107, 44)
TILE = (17, 19, 24)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def render(size: int) -> Image.Image:
    s = 4  # supersample
    n = size * s
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Rounded tile.
    pad = int(n * 0.04)
    d.rounded_rectangle([pad, pad, n - pad, n - pad], radius=int(n * 0.22), fill=TILE)

    c = n / 2
    r = n * 0.38

    # Iridescent disc face: sweep of soft hues.
    face = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    px = face.load()
    stops = [(160, 233, 255), (194, 155, 255), (255, 184, 107), (160, 233, 255)]
    for y in range(n):
        for x in range(n):
            dx, dy = x - c, y - c
            dist = math.hypot(dx, dy)
            if dist > r:
                continue
            t = (math.atan2(dy, dx) / (2 * math.pi)) % 1.0
            seg = t * (len(stops) - 1)
            i = int(seg)
            col = lerp(stops[i], stops[min(i + 1, len(stops) - 1)], seg - i)
            # Mostly dark disc with a gentle sheen.
            base = (38, 42, 52)
            col = lerp(base, col, 0.35 + 0.15 * math.cos(t * 4 * math.pi))
            px[x, y] = col + (255,)
    img.alpha_composite(face)
    d = ImageDraw.Draw(img)

    # Burned data band (inner ring) in laser orange.
    inner, outer = r * 0.36, r * 0.72
    band = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    bd.ellipse([c - outer, c - outer, c + outer, c + outer], fill=LASER + (235,))
    bd.ellipse([c - inner, c - inner, c + inner, c + inner], fill=(0, 0, 0, 0))
    img.alpha_composite(band)

    # Grooves.
    if size >= 48:
        gr = r * 0.78
        while gr < r * 0.98:
            d.ellipse([c - gr, c - gr, c + gr, c + gr], outline=(255, 255, 255, 28), width=max(1, s // 2))
            gr += r * 0.06

    # Rim.
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 40), width=max(1, s))

    # Hub and spindle hole.
    hub = r * 0.30
    d.ellipse([c - hub, c - hub, c + hub, c + hub], fill=(52, 57, 70, 255))
    hole = r * 0.11
    d.ellipse([c - hole, c - hole, c + hole, c + hole], fill=TILE)

    # Laser glint at the edge of the burned band.
    glint = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glint)
    ang = math.radians(-38)
    gx, gy = c + math.cos(ang) * outer, c + math.sin(ang) * outer
    gs = r * 0.13
    gd.ellipse([gx - gs, gy - gs, gx + gs, gy + gs], fill=(255, 220, 190, 255))
    glint = glint.filter(ImageFilter.GaussianBlur(radius=gs * 0.6))
    img.alpha_composite(glint)
    d = ImageDraw.Draw(img)
    gs2 = r * 0.05
    d.ellipse([gx - gs2, gy - gs2, gx + gs2, gy + gs2], fill=(255, 255, 255, 255))

    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    big = render(512)
    for size in SIZES:
        icon = big if size == 512 else render(size) if size >= 128 else big.resize((size, size), Image.LANCZOS)
        icon.save(os.path.join(OUT, f'discwriter_{size}.png'))
        print(f'wrote assets/icon/discwriter_{size}.png')


if __name__ == '__main__':
    main()

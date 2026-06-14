#!/usr/bin/env python3
"""Generate Fireplace notification icons. Requires Pillow (`pip install pillow`).

Two families, both derived from the Fireplace brand artwork
(`source/fireplace-logo-source.png`, the 1024x1024 campfire tile):

  * SMALL / STATUS-BAR icon — MONOCHROME white-on-transparent flame.
      - Android small icon drawables: res/drawable-{mdpi..xxxhdpi}/ic_stat_fireplace.png
      - Web push `badge`:             web/icons/notification-badge-96.png
    Android renders ONLY the alpha channel of these, so they MUST be white +
    fully transparent. A full-colour image here renders as a white square — the
    original bug this script fixes. The detailed campfire/shield does not read at
    24dp, so the small icon is a clean bold flame silhouette echoing the brand.

  * LARGE web `icon` (notification body) — the FULL-COLOUR brand campfire scene
    (`source/fireplace-logo-scene.png`, pre-cropped), padded to a square.
      - web/icons/notification-icon-512.png  (and -192.png)

Run:  python frontend/tool/generate_notification_icons.py
"""

import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FRONTEND = os.path.dirname(HERE)
RES = os.path.join(FRONTEND, "android", "app", "src", "main", "res")
WEB_ICONS = os.path.join(FRONTEND, "web", "icons")
# Brand campfire scene (flame + shield + logs on the dark hearth bg), pre-cropped
# to taste — no metallic frame, no wordmark, no light edges.
SOURCE_SCENE = os.path.join(HERE, "source", "fireplace-logo-scene.png")

SS = 8  # supersample factor for the procedural flame


# ---------------------------------------------------------------------------
# Procedural flame silhouette — cubic Bézier outline in a normalised [0,1]
# design box (y down, 0 = top/tip). Slightly asymmetric so it reads as a flame
# lick, not a teardrop.
# ---------------------------------------------------------------------------

_TIP = (0.50, 0.05)
_SEGMENTS = [
    ((0.61, 0.15), (0.80, 0.30), (0.80, 0.51)),
    ((0.80, 0.73), (0.67, 0.91), (0.50, 0.95)),
    ((0.33, 0.91), (0.20, 0.73), (0.20, 0.53)),
    ((0.20, 0.37), (0.36, 0.31), (0.41, 0.21)),
    ((0.44, 0.14), (0.45, 0.10), (0.50, 0.05)),
]


def _cubic(p0, c1, c2, p3, steps):
    out = []
    for i in range(steps):
        t = i / steps
        u = 1 - t
        x = (u * u * u * p0[0] + 3 * u * u * t * c1[0]
             + 3 * u * t * t * c2[0] + t * t * t * p3[0])
        y = (u * u * u * p0[1] + 3 * u * u * t * c1[1]
             + 3 * u * t * t * c2[1] + t * t * t * p3[1])
        out.append((x, y))
    return out


def _flame_points():
    pts, start = [], _TIP
    for c1, c2, end in _SEGMENTS:
        pts.extend(_cubic(start, c1, c2, end, 40))
        start = end
    return pts


def _scale(pts, factor, cx, cy):
    return [(cx + (x - cx) * factor, cy + (y - cy) * factor) for (x, y) in pts]


def render_flame_white(size, margin_frac=0.07):
    """White flame on transparent — supersampled then downscaled for AA.

    An inner teardrop is punched out (transparent) so the mark reads
    unmistakably as fire even at 24dp, like the Material fire glyph. Android
    tints the alpha, so the hole shows the status-bar background through it.
    """
    big = size * SS
    m = int(big * margin_frac)
    span = big - 2 * m

    def place(pts):
        return [(m + x * span, m + y * span) for (x, y) in pts]

    outer = _flame_points()
    inner = _scale(outer, 0.46, 0.50, 0.66)  # inner flame, biased toward the base

    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.polygon(place(outer), fill=(255, 255, 255, 255))
    draw.polygon(place(inner), fill=(0, 0, 0, 0))  # erase (direct pixel write)
    return img.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------

def _square_scene():
    """The campfire scene padded to a square (no aspect distortion) using its own
    background colour, so the icon edges match the hearth backdrop."""
    im = Image.open(SOURCE_SCENE).convert("RGBA")
    w, h = im.size
    side = max(w, h)
    bg = im.getpixel((1, 1))  # dark hearth background corner
    canvas = Image.new("RGBA", (side, side), bg)
    canvas.paste(im, ((side - w) // 2, (side - h) // 2), im)
    return canvas


def build_large_icon():
    scene = _square_scene()
    for sz in (512, 192):
        out = scene.resize((sz, sz), Image.LANCZOS)
        path = os.path.join(WEB_ICONS, f"notification-icon-{sz}.png")
        out.save(path)
        print("wrote", os.path.relpath(path, FRONTEND), f"{sz}x{sz}")


def build_small_icons():
    densities = {
        "drawable-mdpi": 24,
        "drawable-hdpi": 36,
        "drawable-xhdpi": 48,
        "drawable-xxhdpi": 72,
        "drawable-xxxhdpi": 96,
    }
    for folder, sz in densities.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, "ic_stat_fireplace.png")
        render_flame_white(sz).save(path)
        print("wrote", os.path.join("res", folder, "ic_stat_fireplace.png"), f"{sz}x{sz}")

    badge = os.path.join(WEB_ICONS, "notification-badge-96.png")
    render_flame_white(96).save(badge)
    print("wrote", os.path.relpath(badge, FRONTEND), "96x96")


def main():
    os.makedirs(WEB_ICONS, exist_ok=True)
    build_small_icons()
    build_large_icon()


if __name__ == "__main__":
    main()

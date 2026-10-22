"""Draws the hitsplat sprites in assets/hitsplats (original pixel art in the
style of OSRS hitsplats: a small blob, 24x24 pixels, enlarged 4x).

Run: python3 tools/make_hitsplats.py   (needs Pillow)
"""
import math, os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "hitsplats")
N = 24
# Lobes of the splat (centre x, centre y, radius) on the 24x24 grid.
LOBES = [(12, 12, 8.2), (6, 6.5, 3.4), (18.5, 6, 3.0), (19, 17.5, 3.4), (5.5, 18, 3.0), (12, 3.8, 2.4), (12.5, 20.5, 2.3)]


def inside(x, y, grow=0.0):
    return any(math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= r + grow for cx, cy, r in LOBES)


def splat(fill, dark, light, trim=None):
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    px = im.load()
    for y in range(N):
        for x in range(N):
            if inside(x, y):
                edge = not all(inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if edge:
                    px[x, y] = dark + (255,)
                elif math.hypot(x - 9, y - 8) < 4.5:
                    px[x, y] = light + (255,)
                else:
                    px[x, y] = fill + (255,)
            elif trim is not None and inside(x, y, 1.6):
                # Max hit: a gold rim with notches, like a crown around the splat.
                ang = math.atan2(y + 0.5 - 12, x + 0.5 - 12)
                if int((ang + math.pi) / (2 * math.pi) * 16) % 2 == 0 or inside(x, y, 0.9):
                    px[x, y] = trim + (255,)
    return im.resize((N * 4, N * 4), Image.NEAREST)


def tint(c, k=0.45):
    return tuple(int(v * k) for v in c)


SPLATS = {
    "damage": ((170, 0, 0), (60, 0, 0), (215, 45, 45)),
    "zero": ((45, 95, 200), (12, 30, 85), (95, 140, 235)),
    "poison": ((15, 140, 40), (5, 55, 15), (70, 190, 80)),
    "venom": ((20, 95, 70), (5, 40, 28), (60, 140, 110)),
    "burn": ((215, 105, 15), (90, 40, 5), (245, 160, 60)),
}

os.makedirs(OUT, exist_ok=True)
for name, (f, d, l) in SPLATS.items():
    splat(f, d, l).save(os.path.join(OUT, name + ".png"))
    splat(tint(f), tint(d), tint(l)).save(os.path.join(OUT, name + "_tinted.png"))
f, d, l = SPLATS["damage"]
splat(f, d, l, trim=(235, 175, 45)).save(os.path.join(OUT, "max.png"))
splat(tint(f), tint(d), tint(l), trim=tint((235, 175, 45))).save(os.path.join(OUT, "max_tinted.png"))
print("hitsplats written to", os.path.abspath(OUT))

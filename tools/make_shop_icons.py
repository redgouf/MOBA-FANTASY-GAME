"""Builds the Grand Exchange tab icons (assets/icons/shop/*.png).

Each is OSRS art from Dava96/osrs-icons (Jagex's icons via the OSRS Wiki,
CC BY-NC-SA 3.0), composed on a 32x32 canvas and enlarged with nearest
filtering to 128x128 like the item icons:

  weapons      the Combat icon (crossed swords)
  defence      Rune kiteshield
  consumables  Lobster with a Prayer potion(4) overlapping it
  boots        Leather boots
  skilling     Rune pickaxe (mirrored) crossed with a Rune axe
  materials    Logs with Iron ore overlapping them

  python tools/make_shop_icons.py PATH_TO_OSRS_ICONS_CHECKOUT

(needs Pillow; the checkout is github.com/Dava96/osrs-icons)
"""
import base64
import io
import os
import re
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons", "shop")


def load_icons(repo, names):
    out = {}
    for f in ("src/generated/category-icons.ts", "src/generated/icons.ts"):
        s = open(os.path.join(repo, f)).read()
        for n in names:
            m = re.search(r"export const %s\b[^=]*=\s*['\"`]url\(['\"]?data:image/png;base64,([A-Za-z0-9+/=]+)" % n, s)
            if m and n not in out:
                out[n] = Image.open(io.BytesIO(base64.b64decode(m.group(1)))).convert("RGBA")
    return out


def canvas(parts, size=32):
    """parts: [(image, x, y)] drawn in order on a size x size canvas."""
    c = Image.new("RGBA", (size, size))
    for im, x, y in parts:
        c.alpha_composite(im, (x, y))
    return c


def centred(im, size=32):
    return canvas([(im, (size - im.width) // 2, (size - im.height) // 2)], size)


def save(name, im):
    # Enlarge by the biggest whole factor that fits 128 px, then centre.
    k = max(1, 128 // max(im.width, im.height))
    big = im.resize((im.width * k, im.height * k), Image.NEAREST)
    out = Image.new("RGBA", (128, 128))
    out.alpha_composite(big, ((128 - big.width) // 2, (128 - big.height) // 2))
    out.save(os.path.join(OUT, name + ".png"))


def main():
    repo = sys.argv[1]
    i = load_icons(repo, ["combatIcon", "runeKiteshield", "lobster", "prayerPotion4", "leatherBoots",
                          "runePickaxe", "runeAxe", "logs", "ironOre"])
    os.makedirs(OUT, exist_ok=True)
    save("weapons", centred(i["combatIcon"], 20))
    save("defence", centred(i["runeKiteshield"]))
    save("consumables", canvas([(i["prayerPotion4"], 1, 4), (i["lobster"], 10, 8)], 40))
    save("boots", centred(i["leatherBoots"]))
    # The pickaxe mirrored, the axe as it is: their handles cross in an X.
    save("skilling", canvas([(i["runePickaxe"].transpose(Image.FLIP_LEFT_RIGHT), 0, 8), (i["runeAxe"], 15, 3)], 40))
    save("materials", canvas([(i["logs"], 0, 4), (i["ironOre"], 14, 12)], 40))


if __name__ == "__main__":
    main()

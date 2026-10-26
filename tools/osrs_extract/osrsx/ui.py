"""OSRS interface pieces: the game's bitmap fonts and its hitsplat sprites.

Fonts: each OSRS font is a sprite group of 256 glyphs (index 8) plus a
metrics file of the same name (index 13: 256 advance widths, then the
ascent). They're written as BMFont text files (ui/fonts/<name>.fnt + .png),
which Godot imports as fonts.

Hitsplats: the hitsplat definitions (config group 32) name a background
sprite each; the ones the game shows are saved as ui/hitsplats/<kind>.png
(damage, zero, max, poison, venom, burn, heal; "_tinted" for hits that
don't involve you, as OSRS draws them).
"""
from .buffer import Buffer
from .textures import decode_sprites, png_bytes

FONTS = ["p11_full", "p12_full", "b12_full", "q8_full"]

# kind -> (hitsplat id for your own hits, id for everyone else's)
HITSPLATS = {
    "damage": (28, 29),       # red; dark red
    "zero": (26, 27),         # blue block; dark blue
    "max": (48, 29),          # red with the gold max-hit border
    "poison": (68, 70),       # green
    "venom": (5, 5),          # dark green-teal
    "burn": (3, 3),           # orange
    "heal": (6, 6),           # purple
}


def _hitsplat_defs(cache):
    out = {}
    for i, data in cache.files(2, 32).items():
        b = Buffer(data)
        d = {}
        while True:
            op = b.u8()
            if op == 0:
                break
            if op in (1, 3, 4, 5, 6):
                d[{1: "font", 3: "left", 4: "left2", 5: "bg", 6: "right"}[op]] = b.big_smart()
            elif op == 2:
                d["color"] = b.u24()
            elif op in (7, 10, 13):
                d[op] = b.s16()
            elif op == 8:
                b.u8()
                d["fmt"] = b.string()
            elif op in (9, 14):
                d[op] = b.u16()
            elif op == 11:
                pass
            elif op == 12:
                b.u8()
            elif op in (17, 18):
                b.u16()
                b.u16()
                if op == 18:
                    b.u16()
                n = b.u8()
                d["multi"] = [b.u16() for _ in range(n + 1)]
            else:
                break
        out[i] = d
    return out


def _sprite_png(cache, sid):
    sp = decode_sprites(cache.file(8, sid))[0]
    return png_bytes(sp.width, sp.height, bytes(sp.full_rgba()))


def export_hitsplats(pack):
    defs = _hitsplat_defs(pack.cache)
    n = 0
    for kind, (mine, other) in HITSPLATS.items():
        for sid, suffix in ((mine, ""), (other, "_tinted")):
            bg = defs.get(sid, {}).get("bg", -1)
            if bg is None or bg < 0:
                continue
            with open(pack._path("ui", "hitsplats", "%s%s.png" % (kind, suffix)), "wb") as f:
                f.write(_sprite_png(pack.cache, bg))
            n += 1
    pack.manifest["ui"] = dict(pack.manifest.get("ui", {}), hitsplats=sorted(HITSPLATS))
    pack.log("hitsplats: %d sprites" % n)


def export_fonts(pack):
    c = pack.cache
    done = []
    for name in FONTS:
        sg = c.archive_by_name(8, name)
        mg = c.archive_by_name(13, name)
        if sg is None or mg is None:
            continue
        glyphs = decode_sprites(c.file(8, sg))
        metrics = c.file(13, mg)
        advances = list(metrics[:256])
        cell_h = max(g.height for g in glyphs)
        ascent = metrics[256] if len(metrics) > 256 else cell_h
        # Pack the glyphs in a 16 x 16 grid of cells, white with the glyph's alpha.
        cw = max(g.sub_w for g in glyphs) + 2
        ch = max(g.sub_h for g in glyphs) + 2
        W, H = cw * 16, ch * 16
        atlas = bytearray(W * H * 4)
        lines = []
        for i, g in enumerate(glyphs[:256]):
            if i < 32:
                continue
            ox, oy = (i % 16) * cw + 1, (i // 16) * ch + 1
            for y in range(g.sub_h):
                for x in range(g.sub_w):
                    a = g.rgba[(y * g.sub_w + x) * 4 + 3]
                    if a:
                        p = ((oy + y) * W + ox + x) * 4
                        atlas[p:p + 4] = b"\xff\xff\xff\xff"
            # The glyphs are in Windows-1252 order (0x97 is the em dash, 0x80 the euro).
            try:
                code = ord(bytes([i]).decode("cp1252"))
            except UnicodeDecodeError:
                code = i
            lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                         % (code, ox, oy, g.sub_w, g.sub_h, g.x_off, g.y_off, advances[i]))
        with open(pack._path("ui", "fonts", "%s.png" % name), "wb") as f:
            f.write(png_bytes(W, H, bytes(atlas)))
        head = [
            'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1' % (name, cell_h),
            "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % (cell_h, ascent, W, H),
            'page id=0 file="%s.png"' % name,
            "chars count=%d" % len(lines),
        ]
        with open(pack._path("ui", "fonts", "%s.fnt" % name), "w") as f:
            f.write("\n".join(head + lines) + "\n")
        done.append(name)
    pack.manifest["ui"] = dict(pack.manifest.get("ui", {}), fonts=done)
    pack.log("fonts: %s" % ", ".join(done))


# Interface sprites the HUD uses (ids in the sprite index): the stone side
# panel background and its top / bottom edges, the equipment slot frame, the
# combat tab's crossed swords, skill icons, attack-style icons.
UI_SPRITES = {
    1031: "side_background", 1036: "side_background_top", 1032: "side_background_bottom",
    170: "slot", 168: "combat", 197: "attack", 198: "strength", 199: "defence", 200: "ranged",
    201: "prayer", 202: "magic", 203: "hitpoints", 204: "agility", 222: "stats", 237: "pierce", 239: "range",
}


def export_ui_sprites(pack):
    n = 0
    for sid, name in UI_SPRITES.items():
        try:
            png = _sprite_png(pack.cache, sid)
        except Exception:
            continue
        with open(pack._path("ui", "sprites", "%s.png" % name), "wb") as f:
            f.write(png)
        n += 1
    pack.manifest["ui"] = dict(pack.manifest.get("ui", {}), sprites=sorted(UI_SPRITES.values()))
    pack.log("ui sprites: %d" % n)

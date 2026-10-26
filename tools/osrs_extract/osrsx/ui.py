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
    # The rest of the Skills tab's 25 x 25 icons (the game's "Skills" panel, and
    # the skill names in item text, use them).
    205: "herblore", 206: "thieving", 207: "crafting", 208: "fletching", 209: "mining", 210: "smithing",
    211: "fishing", 212: "cooking", 213: "firemaking", 214: "woodcutting", 215: "runecraft", 216: "slayer",
    217: "farming", 220: "hunter", 221: "construction", 228: "sailing",
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


# --- Grand Exchange interface ------------------------------------------------
# The shop is dressed like the GE (interface 465). Its pieces, by the sprite
# names RuneLite's gameval lists: the dark trade backing, the riveted steel
# border (steelborder 310-315), its close button and dividers, the thin inner
# box lines (980-997), GE buttons (ge_icons 1110/1111), the item backdrop
# (ge_itembackdrop 1120/1121), the bevelled button frame (913-936), the text
# backdrop (1123-1125), the search and buy icons and the chatbox parchment.
# Frames are composed into 9-slice images here, so the game needs one
# StyleBoxTexture per frame (margins in the manifest's ui.ge_slices).

GE_SPRITES = {
    897: "ge_background", 1040: "ge_background_light", 1017: "chat_background",
    1120: "ge_item_box", 1121: "ge_item_box_glow", 1731: "ge_close", 1732: "ge_close_hover",
    1043: "ge_search", 1113: "ge_search_small", 1108: "ge_buy", 1122: "ge_back", 1112: "ge_coins",
}


class _Img:
    """A small RGBA image (stdlib only): crop, blit, flip, fill."""

    def __init__(self, w, h, px=None):
        self.w, self.h = w, h
        self.px = px if px is not None else bytearray(w * h * 4)

    @staticmethod
    def sprite(cache, sid):
        sp = decode_sprites(cache.file(8, sid))[0]
        return _Img(sp.width, sp.height, sp.full_rgba())

    def get(self, x, y):
        p = (y * self.w + x) * 4
        return bytes(self.px[p:p + 4])

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            p = (y * self.w + x) * 4
            self.px[p:p + 4] = c

    def crop(self, x0, y0, w, h):
        out = _Img(w, h)
        for y in range(h):
            for x in range(w):
                out.put(x, y, self.get(x0 + x, y0 + y))
        return out

    def bbox(self):
        xs, ys = [], []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[(y * self.w + x) * 4 + 3]:
                    xs.append(x)
                    ys.append(y)
        return (min(xs), min(ys), max(xs) + 1, max(ys) + 1) if xs else (0, 0, self.w, self.h)

    def trimmed(self):
        x0, y0, x1, y1 = self.bbox()
        return self.crop(x0, y0, x1 - x0, y1 - y0)

    def flip_v(self):
        out = _Img(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                out.put(x, self.h - 1 - y, self.get(x, y))
        return out

    def flip_h(self):
        out = _Img(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                out.put(self.w - 1 - x, y, self.get(x, y))
        return out

    def blit(self, src, dx, dy):
        for y in range(src.h):
            for x in range(src.w):
                c = src.get(x, y)
                if c[3]:
                    self.put(dx + x, dy + y, c)

    def tile(self, src, x0, y0, w, h):
        for y in range(0, h, src.h):
            for x in range(0, w, src.w):
                self.blit(src.crop(0, 0, min(src.w, w - x), min(src.h, h - y)), x0 + x, y0 + y)

    def png(self):
        return png_bytes(self.w, self.h, bytes(self.px))


def _steel_frame(c):
    """The riveted steel border: corners 25x30, 6 px edges; middle = one 36 px edge tile."""
    tl, tr, bl, br = (_Img.sprite(c, s) for s in (310, 311, 312, 313))
    top = _Img.sprite(c, 314).trimmed()          # 36 x 6
    right = _Img.sprite(c, 315).trimmed()        # 6 x 36
    cw, ch = tl.w, tl.h
    w, h = cw * 2 + top.w, ch * 2 + right.h
    f = _Img(w, h)
    f.tile(top, cw, 0, w - cw * 2, top.h)
    f.tile(top.flip_v(), cw, h - top.h, w - cw * 2, top.h)
    f.tile(right.flip_h(), 0, ch, right.w, h - ch * 2)
    f.tile(right, w - right.w, ch, right.w, h - ch * 2)
    f.blit(tl, 0, 0)
    f.blit(tr, w - tr.w, 0)
    f.blit(bl, 0, h - bl.h)
    f.blit(br, w - br.w, h - br.h)
    return f, [cw, ch, cw, ch]


def _thin_box(c):
    """The GE's thin inner box line (991-994 corners, 987-990 edges), 8 px slices."""
    m = 8
    tl, tr, bl, br = (_Img.sprite(c, s) for s in (991, 992, 993, 994))
    top, left, bottom, right = (_Img.sprite(c, s).trimmed() for s in (987, 988, 989, 990))
    f = _Img(m * 3, m * 3)
    f.blit(top.crop(0, 0, m, top.h), m, 0)
    f.blit(bottom.crop(0, 0, m, bottom.h), m, m * 3 - bottom.h)
    f.blit(left.crop(0, 0, left.w, m), 0, m)
    f.blit(right.crop(0, 0, right.w, m), m * 3 - right.w, m)
    f.blit(tl.crop(0, 0, m, m), 0, 0)
    f.blit(tr.crop(tr.w - m, 0, m, m), m * 2, 0)
    f.blit(bl.crop(0, bl.h - m, m, m), 0, m * 2)
    f.blit(br.crop(br.w - m, br.h - m, m, m), m * 2, m * 2)
    return f, [m, m, m, m]


def _bevel_button(c, first, face):
    """The bevelled button (913-920 pattern: TL TR BL BR, left top right bottom),
    9 px slices, filled inside its angled corners with the face colour."""
    pieces = [_Img.sprite(c, first + i) for i in range(8)]
    n = 9
    f = _Img(n * 3, n * 3)
    # Fill, then clear what lies outside each angled corner (flood from the
    # outer corner over the corner sprite's transparent pixels).
    for y in range(f.h):
        for x in range(f.w):
            f.put(x, y, face)
    for (cx, cy), piece in zip(((0, 0), (n - 1, 0), (0, n - 1), (n - 1, n - 1)), pieces[:4]):
        ox, oy = (0 if cx == 0 else n * 2), (0 if cy == 0 else n * 2)
        seen, todo = set(), [(cx, cy)]
        while todo:
            x, y = todo.pop()
            if (x, y) in seen or not (0 <= x < n and 0 <= y < n) or piece.get(x, y)[3]:
                continue
            seen.add((x, y))
            f.put(ox + x, oy + y, b"\x00\x00\x00\x00")
            todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    tl, tr, bl, br, left, top, right, bottom = pieces
    f.blit(top, n, 0)
    f.blit(bottom, n, n * 2)
    f.blit(left, 0, n)
    f.blit(right, n * 2, n)
    f.blit(tl, 0, 0)
    f.blit(tr, n * 2, 0)
    f.blit(bl, 0, n * 2)
    f.blit(br, n * 2, n * 2)
    return f, [n, n, n, n]


def export_ge_sprites(pack):
    c = pack.cache
    n = 0

    def save(name, img):
        nonlocal n
        with open(pack._path("ui", "sprites", "%s.png" % name), "wb") as fh:
            fh.write(img.png())
        n += 1

    for sid, name in GE_SPRITES.items():
        try:
            save(name, _Img.sprite(c, sid))
        except Exception:
            pass
    slices = {}
    face = _Img.sprite(c, 897).get(44, 30)
    for name, build in (("ge_frame", lambda: _steel_frame(c)), ("ge_box", lambda: _thin_box(c)),
                        ("ge_bevel", lambda: _bevel_button(c, 913, face)),
                        ("ge_bevel_hover", lambda: _bevel_button(c, 921, face)),
                        ("ge_bevel_pressed", lambda: _bevel_button(c, 929, face))):
        try:
            img, margins = build()
        except Exception as e:
            pack.log("ge sprite %s failed: %s" % (name, e))
            continue
        save(name, img)
        slices[name] = margins
    # GE buttons and the text backdrop, trimmed; dividers as strips.
    for sid, name in ((1110, "ge_button"), (1111, "ge_button_hover")):
        save(name, _Img.sprite(c, sid).trimmed())
        slices[name] = [6, 6, 6, 6]
    l, m_, r = (_Img.sprite(c, s) for s in (1123, 1124, 1125))
    tb = _Img(l.w + m_.w + r.w, l.h)
    tb.blit(l, 0, 0)
    tb.blit(m_, l.w, 0)
    tb.blit(r, l.w + m_.w, 0)
    save("ge_text_box", tb)
    slices["ge_text_box"] = [l.w, 0, r.w, 0]
    save("ge_divider_h", _Img.sprite(c, 2546).trimmed())
    save("ge_divider_v", _Img.sprite(c, 2561).trimmed())
    ui = dict(pack.manifest.get("ui", {}))
    ui["ge_slices"] = slices
    ui["sprites"] = sorted(set(ui.get("sprites", [])) | set(GE_SPRITES.values()) | set(slices) | {"ge_divider_h", "ge_divider_v"})
    pack.manifest["ui"] = ui
    pack.log("ge sprites: %d" % n)

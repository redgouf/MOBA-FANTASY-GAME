"""Sprites (index 8) and textures (index 9) as RGBA images.

PNG encoding uses only zlib, so no image library is needed.
"""
import struct
import zlib

from .buffer import Buffer

SPRITES, TEXTURES = 8, 9


class Sprite:
    def __init__(self, width, height, x_off, y_off, sub_w, sub_h, rgba):
        self.width, self.height = width, height   # full canvas
        self.x_off, self.y_off = x_off, y_off
        self.sub_w, self.sub_h = sub_w, sub_h
        self.rgba = rgba                          # bytearray sub_w*sub_h*4

    def full_rgba(self):
        """The sprite drawn on its full canvas (offsets applied)."""
        out = bytearray(self.width * self.height * 4)
        for y in range(self.sub_h):
            dst = ((y + self.y_off) * self.width + self.x_off) * 4
            src = y * self.sub_w * 4
            out[dst:dst + self.sub_w * 4] = self.rgba[src:src + self.sub_w * 4]
        return out


def decode_sprites(data: bytes):
    b = Buffer(data, len(data) - 2)
    count = b.u16()
    b.pos = len(data) - 7 - count * 8
    width, height = b.u16(), b.u16()
    pal_size = b.u8() + 1
    xo = [b.u16() for _ in range(count)]
    yo = [b.u16() for _ in range(count)]
    ws = [b.u16() for _ in range(count)]
    hs = [b.u16() for _ in range(count)]
    b.pos = len(data) - 7 - count * 8 - (pal_size - 1) * 3
    pal = [0] + [b.u24() for _ in range(pal_size - 1)]
    pal = [p if (i == 0 or p) else 1 for i, p in enumerate(pal)]
    b.pos = 0
    out = []
    for i in range(count):
        w, h = ws[i], hs[i]
        n = w * h
        flags = b.u8()
        idx = [0] * n
        alpha = None
        if flags & 1:
            for x in range(w):
                for y in range(h):
                    idx[x + y * w] = b.u8()
        else:
            idx = list(b.bytes(n))
        if flags & 2:
            alpha = [0] * n
            if flags & 1:
                for x in range(w):
                    for y in range(h):
                        alpha[x + y * w] = b.u8()
            else:
                alpha = list(b.bytes(n))
        rgba = bytearray(n * 4)
        for k in range(n):
            p = pal[idx[k]]
            a = alpha[k] if alpha is not None else (0 if idx[k] == 0 else 255)
            rgba[k * 4:k * 4 + 4] = bytes(((p >> 16) & 255, (p >> 8) & 255, p & 255, a))
        out.append(Sprite(width, height, xo[i], yo[i], w, h, rgba))
    return out


def png_bytes(width, height, rgba) -> bytes:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


class TextureDef:
    def __init__(self, id_):
        self.id = id_
        self.sprite_ids = []
        self.average_hsl = 0
        self.opaque = True
        self.anim_direction = 0
        self.anim_speed = 0


class Textures:
    """Texture definitions and their pixels."""

    ANIM_UV = [(0.0, 0.0), (0.0, -1.0), (-1.0, 0.0), (0.0, 1.0), (1.0, 0.0)]

    def __init__(self, cache, rev=241):
        self.cache = cache
        self.defs = {}
        files = cache.files(TEXTURES, 0)
        for tid, data in files.items():
            d = TextureDef(tid)
            b = Buffer(data)
            if rev >= 233:
                d.sprite_ids = [b.u16()]
                d.average_hsl = b.u16()
                d.opaque = b.u8() == 1
                d.anim_direction = b.u8()
                d.anim_speed = b.u8()
            else:
                d.average_hsl = b.u16()
                d.opaque = b.u8() == 1
                n = b.u8()
                d.sprite_ids = [b.u16() for _ in range(n)]
                if n > 1:
                    b.skip(2 * (n - 1))
                b.skip(4 * n)
                d.anim_direction = b.u8()
                d.anim_speed = b.u8()
            self.defs[tid] = d
        self._img = {}

    def image(self, tid):
        """(size, rgba bytes) for texture tid, or None."""
        if tid in self._img:
            return self._img[tid]
        d = self.defs.get(tid)
        res = None
        if d and d.sprite_ids:
            data = self.cache.file(SPRITES, d.sprite_ids[0], 0)
            if data:
                sp = decode_sprites(data)[0]
                res = (sp.width, sp.height, sp.full_rgba())
        self._img[tid] = res
        return res

    def png(self, tid):
        img = self.image(tid)
        return png_bytes(*img) if img else None

    def anim_uv(self, tid):
        d = self.defs.get(tid)
        if not d:
            return (0.0, 0.0)
        du, dv = self.ANIM_UV[d.anim_direction] if d.anim_direction < 5 else (0.0, 0.0)
        return (du * d.anim_speed, dv * d.anim_speed)

"""Client colours: the packed 16-bit HSL used by models and floors.

`hsl_to_rgb(hsl)` returns the client's palette colour (sRGB bytes) built the
way the client builds it (rs-map-viewer ColorUtil, BSD-2-Clause).
"""
BRIGHTNESS = 0.8


def _brighten(rgb, brightness):
    r = ((rgb >> 16) / 256.0) ** brightness
    g = (((rgb >> 8) & 255) / 256.0) ** brightness
    b = ((rgb & 255) / 256.0) ** brightness
    return (int(r * 256.0) << 16) | (int(g * 256.0) << 8) | int(b * 256.0)


def _build(brightness):
    pal = [0] * 65536
    idx = 0
    for v5 in range(512):
        h = (v5 >> 3) / 64.0 + 0.0078125
        s = (v5 & 7) / 8.0 + 0.0625
        for v10 in range(128):
            l = v10 / 128.0
            r = g = b = l
            if s != 0.0:
                q = l * (1.0 + s) if l < 0.5 else l + s - l * s
                p = 2.0 * l - q
                tr = h + 1.0 / 3.0
                if tr > 1.0:
                    tr -= 1.0
                tb = h - 1.0 / 3.0
                if tb < 0.0:
                    tb += 1.0

                def ch(t):
                    if 6.0 * t < 1.0:
                        return p + (q - p) * 6.0 * t
                    if 2.0 * t < 1.0:
                        return q
                    if 3.0 * t < 2.0:
                        return p + (q - p) * (2.0 / 3.0 - t) * 6.0
                    return p
                r, g, b = ch(tr), ch(h), ch(tb)
            rgb = (int(r * 256.0) << 16) + (int(g * 256.0) << 8) + int(b * 256.0)
            pal[idx] = _brighten(rgb, brightness)
            idx += 1
    return pal


_PALETTE = None


def hsl_to_rgb(hsl: int) -> int:
    global _PALETTE
    if _PALETTE is None:
        _PALETTE = _build(BRIGHTNESS)
    return _PALETTE[hsl & 0xFFFF]


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hsl_to_linear(hsl: int):
    rgb = hsl_to_rgb(hsl)
    return tuple(srgb_to_linear(((rgb >> s) & 255) / 255.0) for s in (16, 8, 0))


def pack_hsl(hue: int, sat: int, light: int) -> int:
    if light > 179:
        sat //= 2
    if light > 192:
        sat //= 2
    if light > 217:
        sat //= 2
    if light > 243:
        sat //= 2
    return ((sat // 32) << 7) + ((hue // 4) << 10) + (light // 2)


def adjust_lightness(hsl: int, lightness: int) -> int:
    if hsl == -1:
        return 12345678
    lightness = (lightness * (hsl & 127)) >> 7
    lightness = max(2, min(126, lightness))
    return (hsl & 0xFF80) + lightness

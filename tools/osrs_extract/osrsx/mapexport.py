"""Map squares (64x64-tile regions) to GLB: terrain, tile shapes, floor
textures and every placed object (walls, decorations, scenery, roofs).

Ported from rs-map-viewer's SceneBuilder / SceneTileModel / LocModelLoader
(BSD-2-Clause). Lighting is left to the engine (the client bakes it into
vertex colours; here colours keep their unlit values).

World space: 1 tile = 1 m, region south-west corner at the origin, east = +X,
north = -Z, up = +Y. Every level (plane) gets its own nodes so upper floors
and roofs can be hidden.
"""
import json
import math
import re

from .colors import hsl_to_linear, pack_hsl
from .export import MeshOptions, build_primitives, to_world, UNIT
from .gltf import Gltf, UINT, USHORT, ELEMENT_ARRAY_BUFFER
from .model import ModelData

MAPS = 5
SQUARE = 64
LEVELS = 4
BORDER = 6
LEVEL_HEIGHT = 240
HEIGHT_BASIS = 8
INVALID_HSL = 12345678

SHAPE_VERTS = [
    [1, 3, 5, 7], [1, 3, 5, 7], [1, 3, 5, 7], [1, 3, 5, 7, 6], [1, 3, 5, 7, 6], [1, 3, 5, 7, 6],
    [1, 3, 5, 7, 6], [1, 3, 5, 7, 2, 6], [1, 3, 5, 7, 2, 8], [1, 3, 5, 7, 2, 8], [1, 3, 5, 7, 11, 12],
    [1, 3, 5, 7, 11, 12], [1, 3, 5, 7, 13, 14],
]
SHAPE_FACES = [
    [0, 1, 2, 3, 0, 0, 1, 3], [1, 1, 2, 3, 1, 0, 1, 3], [0, 1, 2, 3, 1, 0, 1, 3],
    [0, 0, 1, 2, 0, 0, 2, 4, 1, 0, 4, 3], [0, 0, 1, 4, 0, 0, 4, 3, 1, 1, 2, 4],
    [0, 0, 4, 3, 1, 0, 1, 2, 1, 0, 2, 4], [0, 1, 2, 4, 1, 0, 1, 4, 1, 0, 4, 3],
    [0, 4, 1, 2, 0, 4, 2, 5, 1, 0, 4, 5, 1, 0, 5, 3], [0, 4, 1, 2, 0, 4, 2, 3, 0, 4, 3, 5, 1, 0, 4, 5],
    [0, 0, 4, 5, 1, 4, 1, 2, 1, 4, 2, 3, 1, 4, 3, 5],
    [0, 0, 1, 5, 0, 1, 4, 5, 0, 1, 2, 4, 1, 0, 5, 3, 1, 5, 4, 3, 1, 4, 2, 3],
    [1, 0, 1, 5, 1, 1, 4, 5, 1, 1, 2, 4, 0, 0, 5, 3, 0, 5, 4, 3, 0, 4, 2, 3],
    [1, 0, 5, 4, 1, 0, 1, 5, 0, 0, 4, 3, 0, 4, 5, 3, 0, 5, 2, 3, 0, 1, 2, 5],
]
DISP_X, DISP_Y = [1, 0, -1, 0], [0, -1, 0, 1]
DIAG_X, DIAG_Y = [1, -1, -1, 1], [-1, -1, 1, 1]

_COS = [int(65536 * math.cos(i * math.pi / 1024)) for i in range(2048)]


def parse_region(r):
    if isinstance(r, int):
        return r
    s = str(r)
    if s.isdigit():
        return int(s)
    m = re.match(r"^(\d+)[_,](\d+)$", s)
    if m:
        return (int(m.group(1)) << 8) | int(m.group(2))
    return None


# ------------------------------------------------------------- height noise
def _noise(x, y):
    n = (y * 57 + x) & 0xFFFFFFFF
    n = ((n << 13) ^ n) & 0xFFFFFFFF
    if n & 0x80000000:
        n -= 1 << 32
    a = (n * n) & 0xFFFFFFFF
    a = (a * 15731) & 0xFFFFFFFF
    a = (a + 789221) & 0xFFFFFFFF
    b = (n * a) & 0xFFFFFFFF
    b = (b + 1376312589) & 0x7FFFFFFF
    return (b >> 19) & 0xFF


def _smooth(x, y):
    c = _noise(x - 1, y - 1) + _noise(x + 1, y - 1) + _noise(x - 1, y + 1) + _noise(x + 1, y + 1)
    s = _noise(x - 1, y) + _noise(x + 1, y) + _noise(x, y - 1) + _noise(x, y + 1)
    return _noise(x, y) // 4 + s // 8 + c // 16


def _interp(a, b, frac, freq):
    f = (65536 - _COS[(frac * 1024) // freq]) >> 1
    return ((f * b) >> 16) + (((65536 - f) * a) >> 16)


def _inoise(x, y, freq):
    ix, fx, iy, fy = x // freq, x & (freq - 1), y // freq, y & (freq - 1)
    v1, v2 = _smooth(ix, iy), _smooth(ix + 1, iy)
    v3, v4 = _smooth(ix, iy + 1), _smooth(ix + 1, iy + 1)
    return _interp(_interp(v1, v2, fx, freq), _interp(v3, v4, fx, freq), fy, freq)


def generate_height(x, y):
    n = (_inoise(x + 45365, y + 91923, 4) - 128 + ((_inoise(x + 10294, y + 37821, 2) - 128) >> 1)
         + ((_inoise(x, y, 1) - 128) >> 2))
    n = int(0.3 * n) + 35
    return max(10, min(60, n))


# ------------------------------------------------------------- scene data
class Scene:
    def __init__(self, base_x, base_y, size):
        self.base_x, self.base_y, self.size = base_x, base_y, size
        mk = lambda v: [[[v] * size for _ in range(size)] for _ in range(LEVELS)]
        self.heights = [[[0] * (size + 1) for _ in range(size + 1)] for _ in range(LEVELS)]
        self.underlays = mk(0)
        self.overlays = mk(0)
        self.shapes = mk(0)
        self.rotations = mk(0)
        self.flags = mk(0)
        self.walls = {}      # (level, x, y) -> loc id

    def inside(self, x, y):
        return 0 <= x < self.size and 0 <= y < self.size


def _read_val(b, new):
    if new:
        v = (b[0][b[1]] << 8) | b[0][b[1] + 1]
        b[1] += 2
        return v
    v = b[0][b[1]]
    b[1] += 1
    return v


def decode_terrain(scene, data, ox, oy, new_format=True):
    b = [data, 0]
    for level in range(LEVELS):
        for x in range(SQUARE):
            for y in range(SQUARE):
                sx, sy = x + ox, y + oy
                ok = scene.inside(sx, sy)
                if ok:
                    scene.flags[level][sx][sy] = 0
                while True:
                    v = _read_val(b, new_format)
                    if v == 0:
                        if ok:
                            if level == 0:
                                wx, wy = scene.base_x + sx + 932731, scene.base_y + sy + 556238
                                scene.heights[0][sx][sy] = -generate_height(wx, wy) * HEIGHT_BASIS
                            else:
                                scene.heights[level][sx][sy] = scene.heights[level - 1][sx][sy] - LEVEL_HEIGHT
                        break
                    if v == 1:
                        h = data[b[1]]
                        b[1] += 1
                        if h == 1:
                            h = 0
                        if ok:
                            if level == 0:
                                scene.heights[0][sx][sy] = -h * HEIGHT_BASIS
                            else:
                                scene.heights[level][sx][sy] = scene.heights[level - 1][sx][sy] - h * HEIGHT_BASIS
                        break
                    if v <= 49:
                        ov = _read_val(b, new_format)
                        if ok:
                            scene.overlays[level][sx][sy] = ov
                            scene.shapes[level][sx][sy] = (v - 2) // 4
                            scene.rotations[level][sx][sy] = (v - 2) & 3
                    elif v <= 81:
                        if ok:
                            scene.flags[level][sx][sy] = v - 49
                    elif ok:
                        scene.underlays[level][sx][sy] = v - 81


def decode_locs(data):
    """[(loc id, local x, local y, level, type, rotation)]"""
    out = []
    p = 0

    def usmart():
        nonlocal p
        if data[p] < 128:
            v = data[p]
            p += 1
            return v
        v = ((data[p] << 8) | data[p + 1]) - 0x8000
        p += 2
        return v

    def smart3():
        total = 0
        v = usmart()
        while v == 32767:
            v = usmart()
            total += 32767
        return total + v
    lid = -1
    while True:
        d = smart3()
        if d == 0:
            break
        lid += d
        pos = 0
        while True:
            pd = usmart()
            if pd == 0:
                break
            pos += pd - 1
            attr = data[p]
            p += 1
            out.append((lid, (pos >> 6) & 63, pos & 63, pos >> 12, attr >> 2, attr & 3))
    return out


def blend_underlays(scene, level, defs):
    size = scene.size
    R = 5
    colors = [[-1] * size for _ in range(size)]
    hues, sats, lights, muls, nums = ([0] * size for _ in range(5))
    und = scene.underlays[level]
    for xi in range(-R, size + R):
        for yi in range(size):
            xe = xi + R
            if 0 <= xe < size and und[xe][yi] > 0:
                u = defs.underlay(und[xe][yi] - 1)
                if u:
                    hues[yi] += u.hue
                    sats[yi] += u.saturation
                    lights[yi] += u.lightness
                    muls[yi] += u.hue_multiplier
                    nums[yi] += 1
            xw = xi - R
            if 0 <= xw < size and und[xw][yi] > 0:
                u = defs.underlay(und[xw][yi] - 1)
                if u:
                    hues[yi] -= u.hue
                    sats[yi] -= u.saturation
                    lights[yi] -= u.lightness
                    muls[yi] -= u.hue_multiplier
                    nums[yi] -= 1
        if xi < 0 or xi >= size:
            continue
        rh = rs = rl = rm = rn = 0
        for yi in range(-R, size + R):
            yn = yi + R
            if 0 <= yn < size:
                rh += hues[yn]
                rs += sats[yn]
                rl += lights[yn]
                rm += muls[yn]
                rn += nums[yn]
            ys = yi - R
            if 0 <= ys < size:
                rh -= hues[ys]
                rs -= sats[ys]
                rl -= lights[ys]
                rm -= muls[ys]
                rn -= nums[ys]
            if 0 <= yi < size and und[xi][yi] > 0 and rn > 0 and rm != 0:
                colors[xi][yi] = pack_hsl(int(rh * 256 / rm), int(rs / rn), int(rl / rn))
    return colors


def _mix(a, b):
    if a == INVALID_HSL or b == INVALID_HSL:
        return INVALID_HSL
    if a == -1:
        return b
    if b == -1:
        return a
    h = ((a >> 10) & 63) + ((b >> 10) & 63)
    s = ((a >> 7) & 7) + ((b >> 7) & 7)
    l = (a & 127) + (b & 127)
    return ((h >> 1) << 10) + ((s >> 1) << 7) + (l >> 1)


def _und_light(hsl, light):
    if hsl == -1:
        return INVALID_HSL
    l = max(2, min(126, ((hsl & 127) * light) >> 7))
    return (hsl & 0xFF80) + l


def _ovl_light(hsl, light):
    if hsl == -2:
        return INVALID_HSL
    if hsl == -1:
        return max(2, min(126, light))
    l = max(2, min(126, ((hsl & 127) * light) >> 7))
    return (hsl & 0xFF80) + l


# ------------------------------------------------------------- geometry sink
class Sink:
    """Collects triangles per (node, texture, transparent)."""

    def __init__(self):
        self.groups = {}

    def tri(self, node, tex, alpha, pts, cols, uvs=None):
        key = (node, tex, alpha)
        g = self.groups.setdefault(key, {"pos": [], "col": [], "uv": []})
        for i in range(3):
            g["pos"].extend(pts[i])
            g["col"].extend(cols[i])
            if tex != -1:
                g["uv"].extend(uvs[i] if uvs else (0.0, 0.0))


def _lin(hsl, alpha=1.0):
    if hsl == INVALID_HSL or hsl < 0:
        return (1.0, 1.0, 1.0, alpha)
    r, g, b = hsl_to_linear(hsl)
    return (r, g, b, alpha)


def add_tile(sink, node, scene, defs, textures, level, x, y, blended, ox, oy):
    """One tile at scene (x, y); world position relative to the region (ox, oy)."""
    und = scene.underlays[level][x][y] - 1
    ovl = scene.overlays[level][x][y] - 1
    if und == -1 and ovl == -1:
        return
    H = scene.heights[level]
    hsw, hse, hne, hnw = H[x][y], H[x + 1][y], H[x + 1][y + 1], H[x][y + 1]
    light = 128
    u_sw = u_se = u_ne = u_nw = -1
    if und != -1:
        u_sw = blended[x][y]
        u_se = blended[x + 1][y] if x + 1 < scene.size and blended[x + 1][y] != -1 else u_sw
        u_ne = blended[x + 1][y + 1] if x + 1 < scene.size and y + 1 < scene.size and blended[x + 1][y + 1] != -1 else u_sw
        u_nw = blended[x][y + 1] if y + 1 < scene.size and blended[x][y + 1] != -1 else u_sw
    us = [_und_light(c, light) for c in (u_sw, u_se, u_ne, u_nw)]
    shape, rot, tex, ohsl = 0, 0, -1, -2
    if ovl != -1:
        shape = scene.shapes[level][x][y] + 1
        rot = scene.rotations[level][x][y]
        o = defs.overlay(ovl)
        if o is not None:
            if o.texture != -1 and textures.image(o.texture) is not None:
                tex, ohsl = o.texture, -1
            elif o.rgb == 0xFF00FF:
                ohsl = -2
            else:
                ohsl = pack_hsl(o.hue, o.saturation, o.lightness)
    os_ = _ovl_light(ohsl, light)
    tx, ty = (x - ox) * 128, (y - oy) * 128
    verts = []
    for vi in SHAPE_VERTS[shape]:
        if vi & 1 == 0 and vi <= 8:
            vi = ((vi - rot - rot - 1) & 7) + 1
        if 8 < vi <= 12:
            vi = ((vi - 9 - rot) & 3) + 9
        if 12 < vi <= 16:
            vi = ((vi - 13 - rot) & 3) + 13
        sw, se, ne, nw = us
        table = {
            1: (0, 0, hsw, sw), 2: (64, 0, (hse + hsw) >> 1, _mix(se, sw)), 3: (128, 0, hse, se),
            4: (128, 64, (hne + hse) >> 1, _mix(se, ne)), 5: (128, 128, hne, ne),
            6: (64, 128, (hne + hnw) >> 1, _mix(nw, ne)), 7: (0, 128, hnw, nw),
            8: (0, 64, (hnw + hsw) >> 1, _mix(nw, sw)), 9: (64, 32, (hse + hsw) >> 1, _mix(se, sw)),
            10: (96, 64, (hne + hse) >> 1, _mix(se, ne)), 11: (64, 96, (hne + hnw) >> 1, _mix(nw, ne)),
            12: (32, 64, (hnw + hsw) >> 1, _mix(nw, sw)), 13: (32, 32, hsw, sw), 14: (96, 32, hse, se),
            15: (96, 96, hne, ne), 16: (32, 96, hnw, nw),
        }
        dx, dz, h, uc = table[vi]
        verts.append((tx + dx, h, ty + dz, uc))
    faces = SHAPE_FACES[shape]
    for i in range(0, len(faces), 4):
        is_ovl = faces[i] == 1
        idx = [faces[i + 1], faces[i + 2], faces[i + 3]]
        idx = [(k - rot) & 3 if k < 4 else k for k in idx]
        if is_ovl:
            if os_ == INVALID_HSL and tex == -1:
                continue
            t = tex
            col = _lin(os_) if tex == -1 else _lin(-1)
            cols = [col] * 3
        else:
            if verts[idx[0]][3] == INVALID_HSL:
                continue
            t = -1
            cols = [_lin(verts[k][3]) for k in idx]
        pts = [to_world(verts[k][0], verts[k][1], verts[k][2]) for k in idx]
        uvs = [((verts[k][0]) / 128.0, -(verts[k][2]) / 128.0) for k in idx] if t != -1 else None
        sink.tri(node, t, False, pts, cols, uvs)


# ------------------------------------------------------------- locs
def loc_model(pack, loc, shape, rotation):
    """Loc model for a placement shape and rotation (0-3, +4 = diagonal/mirror variants)."""
    if not loc or not loc.models:
        return None
    mirrored = loc.rotated or (shape == 2 and rotation > 3)
    if loc.types is None:
        if shape != 10:
            return None
        ids = loc.models[0]
    else:
        ids = None
        for t, ms in zip(loc.types, loc.models):
            if t == shape:
                ids = ms
                break
        if ids is None:
            return None
    ms = []
    for mid in ids:
        m = pack.models.get(mid)
        if m is None:
            return None
        if mirrored:
            m.mirror()
        ms.append(m)
    m = ModelData.merge(ms) if len(ms) > 1 else ms[0]
    if shape == 4 and rotation > 3:
        m.rotate_angle(256)
        m.translate(45, 0, -45)
    m.rotate(rotation & 3)
    m.recolor(loc.recolor_from, loc.recolor_to)
    m.retexture(loc.retexture_from, loc.retexture_to)
    if loc.model_size != [128, 128, 128]:
        m.scale(loc.model_size[0], loc.model_size[1], loc.model_size[2])
    if loc.offset != [0, 0, 0]:
        m.translate(loc.offset[0], loc.offset[1], loc.offset[2])
    if shape == 10 and rotation > 3:
        m.rotate_angle(256)
    return m


def contour(m, loc, H, Habove, ex, ey, ez):
    t = loc.contour_type
    if t not in (1, 2) or not m.vx:
        return
    n = len(H)

    def ground(vx, vz):
        tx, tz = vx >> 7, vz >> 7
        if tx < 0 or tz < 0 or tx >= n - 1 or tz >= n - 1:
            return None
        rx, rz = vx & 127, vz & 127
        h0 = (H[tx][tz] * (128 - rx) + H[tx + 1][tz] * rx) >> 7
        h1 = (H[tx][tz + 1] * (128 - rx) + H[tx + 1][tz + 1] * rx) >> 7
        return (h0 * (128 - rz) + h1 * rz) >> 7
    miny = min(m.vy)
    for i in range(len(m.vx)):
        g = ground(m.vx[i] + ex, m.vz[i] + ez)
        if g is None:
            continue
        if t == 1:
            m.vy[i] += g - ey
        elif t == 2 and miny != 0:
            ratio = int((m.vy[i] << 16) / miny)
            p = loc.contour_param
            if ratio < p:
                m.vy[i] += int((g - ey) * (p - ratio) / p)


def place_loc(pack, sink_models, scene, lid, x, y, level, shape, rot, ox, oy, draw_level):
    loc = pack.defs.loc(lid)
    if loc is None or not loc.models:
        return
    sx, sy = loc.size_x, loc.size_y
    if rot in (1, 3):
        sx, sy = sy, sx
    size = scene.size
    if x + sx <= size:
        x0, x1 = (sx >> 1) + x, ((sx + 1) >> 1) + x
    else:
        x0, x1 = x, x + 1
    if y + sy <= size:
        y0, y1 = (sy >> 1) + y, ((sy + 1) >> 1) + y
    else:
        y0, y1 = y, y + 1
    H = scene.heights[level]
    Ha = scene.heights[level + 1] if level < LEVELS - 1 else None
    x1, y1 = min(x1, size), min(y1, size)
    ch = (H[x1][y1] + H[x0][y1] + H[x0][y0] + H[x1][y0]) >> 2
    ex = (x << 7) + (sx << 6)
    ez = (y << 7) + (sy << 6)
    entries = []          # (model shape, rotation, extra offset x, z)
    if shape == 22:
        entries.append((22, rot, 0, 0))
    elif shape in (10, 11):
        entries.append((10, rot if shape == 10 else rot + 4, 0, 0))
    elif shape >= 12:
        entries.append((shape, rot, 0, 0))
        ex, ez = (x << 7) + 64, (y << 7) + 64
    elif shape in (0, 1, 3):
        entries.append((shape, rot, 0, 0))
        ex, ez = (x << 7) + 64, (y << 7) + 64
        if shape == 0:
            scene.walls[(level, x, y)] = lid
    elif shape == 2:
        entries.append((2, rot + 4, 0, 0))
        entries.append((2, (rot + 1) & 3, 0, 0))
        ex, ez = (x << 7) + 64, (y << 7) + 64
        scene.walls[(level, x, y)] = lid
    elif shape == 9:
        entries.append((9, rot, 0, 0))
    elif shape == 4:
        entries.append((4, rot, 0, 0))
        ex, ez = (x << 7) + 64, (y << 7) + 64
    elif shape in (5, 6, 8):
        wall = scene.walls.get((level, x, y))
        disp = pack.defs.loc(wall).decor_displacement if wall is not None else 16
        ex, ez = (x << 7) + 64, (y << 7) + 64
        if shape == 5:
            entries.append((4, rot, disp * DISP_X[rot], disp * DISP_Y[rot]))
        else:
            d = disp // 2
            entries.append((4, rot + 4, d * DIAG_X[rot], d * DIAG_Y[rot]))
            if shape == 8:
                entries.append((4, ((rot + 2) & 3) + 4, d * DIAG_X[rot], d * DIAG_Y[rot]))
    elif shape == 7:
        ex, ez = (x << 7) + 64, (y << 7) + 64
        entries.append((4, ((rot + 2) & 3) + 4, 0, 0))
    for mshape, mrot, dx, dz in entries:
        m = loc_model(pack, loc, mshape, mrot)
        if m is None:
            continue
        contour(m, loc, H, Ha, ex, ch, ez)
        m.translate(ex + dx - (ox << 7), ch, ez + dz - (oy << 7))
        group = "roofs" if 12 <= shape <= 21 else "objects"
        sink_models.setdefault((draw_level, group), []).append(m)


# ------------------------------------------------------------- export
def export_region(pack, region_id, levels=LEVELS):
    rx, ry = region_id >> 8, region_id & 255
    cache, defs = pack.cache, pack.defs
    size = SQUARE + 2 * BORDER
    base_x, base_y = rx * SQUARE - BORDER, ry * SQUARE - BORDER
    scene = Scene(base_x, base_y, size + 1)
    found = False
    for mx in (rx - 1, rx, rx + 1):
        for my in (ry - 1, ry, ry + 1):
            gid = (mx << 8) | my
            files = cache.files(MAPS, gid) if cache.has(MAPS, gid) else {}
            terrain = files.get(0)
            if terrain is None:
                name_id = cache.archive_by_name(MAPS, "m%d_%d" % (mx, my))
                if name_id is not None:
                    terrain = cache.file(MAPS, name_id, 0)
            if terrain:
                decode_terrain(scene, terrain, mx * SQUARE - base_x, my * SQUARE - base_y)
                if (mx, my) == (rx, ry):
                    found = True
    if not found:
        pack.log("region %d (%d_%d): no terrain in this cache" % (region_id, rx, ry))
        return False
    # last row/column of heights for the edge
    for level in range(LEVELS):
        for i in range(size + 1):
            scene.heights[level][size][i] = scene.heights[level][size - 1][i]
            scene.heights[level][i][size] = scene.heights[level][i][size - 1]
    files = cache.files(MAPS, region_id)
    loc_data = files.get(1)
    if loc_data is None:
        name_id = cache.archive_by_name(MAPS, "l%d_%d" % (rx, ry))
        if name_id is not None:
            loc_data = cache.file(MAPS, name_id, 0)
    locs = decode_locs(loc_data) if loc_data else []

    def draw_level(level, x, y):
        f = scene.flags
        if f[level][x][y] & 8:
            return 0
        if level > 0 and f[1][x][y] & 2:
            return level - 1
        return level

    sink = Sink()
    for level in range(min(levels, LEVELS)):
        blended = blend_underlays(scene, level, defs)
        for x in range(BORDER, BORDER + SQUARE):
            for y in range(BORDER, BORDER + SQUARE):
                add_tile(sink, "terrain_%d" % draw_level(level, x, y), scene, defs, pack.textures,
                         level, x, y, blended, BORDER, BORDER)
    models = {}
    placements = []
    # walls first so wall decorations find their wall's displacement
    for lid, lx, ly, level, shape, rot in sorted(locs, key=lambda e: 0 if e[4] <= 3 else 1):
        if level >= levels:
            continue
        x, y = lx + BORDER, ly + BORDER
        dl = draw_level(level, x, y)
        place_loc(pack, models, scene, lid, x, y, level, shape, rot, BORDER, BORDER, dl)
        placements.append({"id": lid, "x": lx, "y": ly, "level": level, "draw_level": dl,
                           "shape": shape, "rotation": rot, "name": (defs.loc(lid).name if defs.loc(lid) else None)})
    g = Gltf()
    level_nodes = {}

    def level_node(dl):
        if dl not in level_nodes:
            level_nodes[dl] = []
        return level_nodes[dl]
    # terrain
    by_node = {}
    for (node, tex, alpha), d in sink.groups.items():
        by_node.setdefault(node, []).append((tex, alpha, d))
    for node, parts in sorted(by_node.items()):
        prims = []
        # smooth terrain normals: average face normals per corner position (whole level)
        acc = {}
        for tex, alpha, d in parts:
            fn = _face_normals(d["pos"])
            for i in range(0, len(d["pos"]), 3):
                key = tuple(round(v, 4) for v in d["pos"][i:i + 3])
                a = acc.setdefault(key, [0.0, 0.0, 0.0])
                a[0] += fn[i]
                a[1] += fn[i + 1]
                a[2] += fn[i + 2]
        for k, a in acc.items():
            ln = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) or 1.0
            acc[k] = (a[0] / ln, a[1] / ln, a[2] / ln)
        for tex, alpha, d in parts:
            pos, nrm, col, uv, idx, seen = [], [], [], [], [], {}
            for v in range(len(d["pos"]) // 3):
                p3 = tuple(round(x, 4) for x in d["pos"][v * 3:v * 3 + 3])
                c4 = tuple(d["col"][v * 4:v * 4 + 4])
                u2 = tuple(d["uv"][v * 2:v * 2 + 2]) if tex != -1 else ()
                key = (p3, c4, u2)
                at = seen.get(key)
                if at is None:
                    at = seen[key] = len(pos) // 3
                    pos.extend(p3)
                    nrm.extend(acc[p3])
                    col.extend(round(min(1.0, max(0.0, x)) * 65535) for x in c4)
                    uv.extend(u2)
                idx.append(at)
            n = len(pos) // 3
            attrs = {"POSITION": g.accessor(pos, "VEC3", minmax=True), "NORMAL": g.accessor(nrm, "VEC3"),
                     "COLOR_0": g.accessor(col, "VEC4", comp=USHORT, normalized=True)}
            ti = None
            if tex != -1:
                attrs["TEXCOORD_0"] = g.accessor(uv, "VEC2")
                ti = _tex(g, pack.textures, tex)
            ind = g.accessor(idx, "SCALAR", comp=UINT if n > 65535 else USHORT, target=ELEMENT_ARRAY_BUFFER)
            mat = g.material("floor_tex%d" % tex if tex != -1 else "floor_vc", ti)
            prims.append({"attributes": attrs, "indices": ind, "material": mat})
        dl = int(node.split("_")[1])
        level_node(dl).append(g.node(node, mesh=g.mesh(node, prims)))
    # objects
    g.__dict__["_tex_cache"] = g.__dict__.get("_tex_cache", {})
    for (dl, group), ms in sorted(models.items()):
        merged = ModelData.merge(ms)
        prims = build_primitives(g, merged, MeshOptions(pack.textures, None, group))
        if prims:
            name = "%s_%d" % (group, dl)
            level_node(dl).append(g.node(name, mesh=g.mesh(name, prims)))
    kids = [g.node("level_%d" % dl, children=nodes) for dl, nodes in sorted(level_nodes.items())]
    root = g.node("region_%d_%d" % (rx, ry), children=kids)
    g.add_root(root)
    rel = "maps/%d_%d.glb" % (rx, ry)
    g.write(pack._path(rel))
    # data for gameplay: heights (metres), tile flags and object placements
    info = {
        "region": region_id, "x": rx, "y": ry, "tiles": SQUARE, "world_origin_tile": [rx * SQUARE, ry * SQUARE],
        "heights": [[[round(-scene.heights[l][x + BORDER][y + BORDER] * UNIT, 4) for y in range(SQUARE + 1)]
                     for x in range(SQUARE + 1)] for l in range(LEVELS)],
        "flags": [[[scene.flags[l][x + BORDER][y + BORDER] for y in range(SQUARE)] for x in range(SQUARE)]
                  for l in range(LEVELS)],
        "objects": placements,
        "axes": "tile (x, y) covers world X in [x, x+1], Z in [-(y+1), -y]; heights[level][x][y] is the corner height",
    }
    with open(pack._path("maps/%d_%d.json" % (rx, ry)), "w") as f:
        json.dump(info, f, separators=(",", ":"))
    pack.manifest.setdefault("maps", {})[str(region_id)] = {"file": rel, "data": "maps/%d_%d.json" % (rx, ry),
                                                           "objects": len(placements)}
    pack.log("region %d (%d_%d): %d objects -> %s" % (region_id, rx, ry, len(placements), rel))
    return True


def _tex(g, textures, tex):
    cache = g.__dict__.setdefault("_tex_cache", {})
    if tex not in cache:
        cache[tex] = g.image(textures.png(tex), "texture_%d" % tex)
    return cache[tex]


def _face_normals(pos):
    out = []
    for i in range(0, len(pos), 9):
        ax, ay, az, bx, by, bz, cx, cy, cz = pos[i:i + 9]
        ux, uy, uz = bx - ax, by - ay, bz - az
        vx, vy, vz = cx - ax, cy - ay, cz - az
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        out += [nx / ln, ny / ln, nz / ln] * 3
    return out

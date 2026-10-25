"""OSRS model decoding and edits.

Decoders ported from rs-map-viewer's ModelData (BSD-2-Clause), which follows
the client: formats "old", v1 (-1,-1 footer), v2 (-2,-1) and v3 (-3,-1).
Coordinates are client units (128 per tile), y pointing down.
"""
import math

from .buffer import Buffer

MODELS = 7


def _i8(v):
    v &= 0xFF
    return v - 256 if v > 127 else v


def _i16(v):
    v &= 0xFFFF
    return v - 65536 if v > 32767 else v


class ModelData:
    __slots__ = ("vx", "vy", "vz", "vskins", "maya_groups", "maya_scales",
                 "i1", "i2", "i3", "colors", "render_types", "priorities", "priority",
                 "alphas", "fskins", "textures", "tex_coords", "tex_types",
                 "tex_p", "tex_m", "tex_n", "version", "id")

    def __init__(self):
        self.vx, self.vy, self.vz = [], [], []
        self.vskins = None
        self.maya_groups = None
        self.maya_scales = None
        self.i1, self.i2, self.i3 = [], [], []
        self.colors = []
        self.render_types = None
        self.priorities = None
        self.priority = 0
        self.alphas = None
        self.fskins = None
        self.textures = None
        self.tex_coords = None
        self.tex_types = []
        self.tex_p, self.tex_m, self.tex_n = [], [], []
        self.version = 0
        self.id = -1

    @property
    def vertex_count(self):
        return len(self.vx)

    @property
    def face_count(self):
        return len(self.i1)

    # ------------------------------------------------------------------ decode
    @staticmethod
    def decode(data: bytes, model_id: int = -1) -> "ModelData":
        m = ModelData()
        m.id = model_id
        if data[-1] == 0xFD and data[-2] == 0xFF:
            m._v3(data)
        elif data[-1] == 0xFE and data[-2] == 0xFF:
            m._v2(data)
        elif data[-1] == 0xFF and data[-2] == 0xFF:
            m._v1(data)
        else:
            m._old(data)
        return m

    def _vertices(self, flags_buf, bx, by, bz, skin_buf, count, has_skins):
        lx = ly = lz = 0
        vx, vy, vz = [0] * count, [0] * count, [0] * count
        skins = [0] * count if has_skins else None
        for i in range(count):
            f = flags_buf.u8()
            dx = bx.smart2() if f & 1 else 0
            dy = by.smart2() if f & 2 else 0
            dz = bz.smart2() if f & 4 else 0
            lx += dx
            ly += dy
            lz += dz
            vx[i], vy[i], vz[i] = lx, ly, lz
            if has_skins:
                skins[i] = skin_buf.u8()
        self.vx, self.vy, self.vz, self.vskins = vx, vy, vz, skins

    def _maya(self, buf, count):
        self.maya_groups = [None] * count
        self.maya_scales = [None] * count
        for i in range(count):
            n = buf.u8()
            g, s = [], []
            for _ in range(n):
                g.append(buf.u8())
                s.append(buf.u8())
            self.maya_groups[i] = g
            self.maya_scales[i] = s

    def _indices(self, type_buf, idx_buf, count):
        a = b = c = last = 0
        i1, i2, i3 = [0] * count, [0] * count, [0] * count
        for i in range(count):
            t = type_buf.u8()
            if t == 1:
                a = idx_buf.smart2() + last
                b = idx_buf.smart2() + a
                c = idx_buf.smart2() + b
                last = c
            elif t == 2:
                b = c
                c = idx_buf.smart2() + last
                last = c
            elif t == 3:
                a = c
                c = idx_buf.smart2() + last
                last = c
            elif t == 4:
                a, b = b, a
                c = idx_buf.smart2() + last
                last = c
            i1[i], i2[i], i3[i] = a, b, c
        self.i1, self.i2, self.i3 = i1, i2, i3

    def _v3(self, data):
        self.version = 3
        b = Buffer(data, len(data) - 26)
        vc, fc, tc = b.u16(), b.u16(), b.u8()
        f12, f13, f14, f15, f16, f17, has_maya = (b.u8() for _ in range(7))
        l19, l20, l21, l22, l23, l24 = (b.u16() for _ in range(6))
        simple = complex_ = cube = 0
        self.tex_types = []
        if tc:
            tb = Buffer(data, 0)
            for _ in range(tc):
                t = tb.s8()
                self.tex_types.append(t)
                if t == 0:
                    simple += 1
                if 1 <= t <= 3:
                    complex_ += 1
                if t == 2:
                    cube += 1
        o = tc + vc
        o30 = o
        if f12 == 1:
            o += fc
        o31 = o
        o += fc
        o32 = o
        if f13 == 255:
            o += fc
        o33 = o
        if f15 == 1:
            o += fc
        o34 = o
        o += l24
        o35 = o
        if f14 == 1:
            o += fc
        o36 = o
        o += l22
        o37 = o
        if f16 == 1:
            o += fc * 2
        o38 = o
        o += l23
        o39 = o
        o += fc * 2
        o40 = o
        o += l19
        o41 = o
        o += l20
        o42 = o
        o += l21
        o43 = o
        o += simple * 6
        self._vertices(Buffer(data, tc), Buffer(data, o40), Buffer(data, o41), Buffer(data, o42),
                       Buffer(data, o34), vc, f17 == 1)
        if has_maya == 1:
            sb = Buffer(data, o34 + (vc if f17 == 1 else 0))
            self._maya(sb, vc)
        cb, rb, pb, ab, sb, tb, kb = (Buffer(data, x) for x in (o39, o30, o32, o35, o33, o37, o38))
        self.colors = [0] * fc
        self.render_types = [0] * fc if f12 == 1 else None
        self.priorities = [0] * fc if f13 == 255 else None
        if f13 != 255:
            self.priority = f13
        self.alphas = [0] * fc if f14 == 1 else None
        self.fskins = [0] * fc if f15 == 1 else None
        self.textures = [-1] * fc if f16 == 1 else None
        self.tex_coords = [-1] * fc if (f16 == 1 and tc > 0) else None
        for i in range(fc):
            self.colors[i] = cb.u16()
            if f12 == 1:
                self.render_types[i] = rb.s8()
            if f13 == 255:
                self.priorities[i] = pb.s8()
            if f14 == 1:
                self.alphas[i] = ab.s8()
            if f15 == 1:
                self.fskins[i] = sb.u8()
            if f16 == 1:
                self.textures[i] = _i16(tb.u16() - 1)
            if self.tex_coords is not None and self.textures[i] != -1:
                self.tex_coords[i] = _i8(kb.u8() - 1)
        self._indices(Buffer(data, o31), Buffer(data, o36), fc)
        pb = Buffer(data, o43)       # simple texture triangles
        self.tex_p, self.tex_m, self.tex_n = [0] * tc, [0] * tc, [0] * tc
        for i in range(tc):
            if (self.tex_types[i] & 0xFF) == 0:
                self.tex_p[i], self.tex_m[i], self.tex_n[i] = pb.u16(), pb.u16(), pb.u16()

    def _v2(self, data):
        self.version = 2
        b = Buffer(data, len(data) - 23)
        vc, fc, tc = b.u16(), b.u16(), b.u8()
        f12, f13, f14, f15, has_skins, has_maya = (b.u8() for _ in range(6))
        l18, l19, l20, l21, l22 = (b.u16() for _ in range(5))
        o = vc
        o25 = o
        o += fc
        o26 = o
        if f13 == 255:
            o += fc
        o27 = o
        if f15 == 1:
            o += fc
        o28 = o
        if f12 == 1:
            o += fc
        o29 = o
        o += l22
        o30 = o
        if f14 == 1:
            o += fc
        o31 = o
        o += l21
        o32 = o
        o += fc * 2
        o33 = o
        o += tc * 6
        o34 = o
        o += l18
        o35 = o
        o += l19
        self._vertices(Buffer(data, 0), Buffer(data, o34), Buffer(data, o35), Buffer(data, o),
                       Buffer(data, o29), vc, has_skins == 1)
        if has_maya == 1:
            self._maya(Buffer(data, o29 + (vc if has_skins == 1 else 0)), vc)
        self._faces_old(data, fc, tc, f12, f13, f14, f15, o32, o28, o26, o30, o27)
        self._indices(Buffer(data, o25), Buffer(data, o31), fc)
        self._simple_tex(data, o33, tc)
        self._fix_tex_coords()

    def _old(self, data):
        self.version = 0
        b = Buffer(data, len(data) - 18)
        vc, fc, tc = b.u16(), b.u16(), b.u8()
        uses_tex, f13, f14, f15, f16 = (b.u8() for _ in range(5))
        l17, l18, l19, l20 = (b.u16() for _ in range(4))
        o = vc
        o23 = o
        o += fc
        o24 = o
        if f13 == 255:
            o += fc
        o25 = o
        if f15 == 1:
            o += fc
        o26 = o
        if uses_tex == 1:
            o += fc
        o27 = o
        if f16 == 1:
            o += vc
        o28 = o
        if f14 == 1:
            o += fc
        o29 = o
        o += l20
        o30 = o
        o += fc * 2
        o31 = o
        o += tc * 6
        o32 = o
        o += l17
        o33 = o
        o += l18
        self._vertices(Buffer(data, 0), Buffer(data, o32), Buffer(data, o33), Buffer(data, o),
                       Buffer(data, o27), vc, f16 == 1)
        self._faces_old(data, fc, tc, uses_tex, f13, f14, f15, o30, o26, o24, o28, o25)
        self._indices(Buffer(data, o23), Buffer(data, o29), fc)
        self._simple_tex(data, o31, tc)
        self._fix_tex_coords()

    def _faces_old(self, data, fc, tc, uses_tex, f13, f14, f15, oc, ot, op, oa, os_):
        cb, tb, pb, ab, sb = (Buffer(data, x) for x in (oc, ot, op, oa, os_))
        self.colors = [0] * fc
        has_render = has_tex = False
        if uses_tex == 1:
            self.render_types = [0] * fc
            self.tex_coords = [-1] * fc
            self.textures = [-1] * fc
        self.priorities = [0] * fc if f13 == 255 else None
        if f13 != 255:
            self.priority = f13
        self.alphas = [0] * fc if f14 == 1 else None
        self.fskins = [0] * fc if f15 == 1 else None
        for i in range(fc):
            self.colors[i] = cb.u16()
            if uses_tex == 1:
                fl = tb.u8()
                if fl & 1:
                    self.render_types[i] = 1
                    has_render = True
                if fl & 2:
                    self.tex_coords[i] = _i8(fl >> 2)
                    self.textures[i] = _i16(self.colors[i])
                    self.colors[i] = 127
                    if self.textures[i] != -1:
                        has_tex = True
            if f13 == 255:
                self.priorities[i] = pb.s8()
            if f14 == 1:
                self.alphas[i] = ab.s8()
            if f15 == 1:
                self.fskins[i] = sb.u8()
        if uses_tex == 1:
            if not has_tex:
                self.textures = None
            if not has_render:
                self.render_types = None
        self.tex_types = [0] * tc

    def _simple_tex(self, data, off, tc):
        b = Buffer(data, off)
        self.tex_p, self.tex_m, self.tex_n = [0] * tc, [0] * tc, [0] * tc
        for i in range(tc):
            self.tex_p[i], self.tex_m[i], self.tex_n[i] = b.u16(), b.u16(), b.u16()

    def _fix_tex_coords(self):
        if self.tex_coords is None:
            return
        valid = False
        for i in range(self.face_count):
            c = self.tex_coords[i] & 0xFF
            if c != 255:
                if (self.i1[i] == self.tex_p[c] and self.i2[i] == self.tex_m[c]
                        and self.i3[i] == self.tex_n[c]):
                    self.tex_coords[i] = -1
                else:
                    valid = True
        if not valid:
            self.tex_coords = None

    def _v1(self, data):
        self.version = 1
        b = Buffer(data, len(data) - 23)
        vc, fc, tc = b.u16(), b.u16(), b.u8()
        flags = b.u8()
        has_render = flags & 1
        if flags & 8:
            b.pos -= 7
            self.version = b.u8()
            b.pos += 6
        prio, has_alpha, has_fskins, has_tex, has_vskins = (b.u8() for _ in range(5))
        lx, ly, lz, lidx, ltex = (b.u16() for _ in range(5))
        simple = complex_ = cube = 0
        self.tex_types = []
        if tc:
            tb = Buffer(data, 0)
            for _ in range(tc):
                t = tb.s8()
                self.tex_types.append(t)
                if t == 0:
                    simple += 1
                if 1 <= t <= 3:
                    complex_ += 1
                if t == 2:
                    cube += 1
        o = tc + vc
        o_render = o
        if has_render:
            o += fc
        o_ctype = o
        o += fc
        o_prio = o
        if prio == 255:
            o += fc
        o_fskin = o
        if has_fskins == 1:
            o += fc
        o_vskin = o
        if has_vskins == 1:
            o += vc
        o_alpha = o
        if has_alpha == 1:
            o += fc
        o_idx = o
        o += lidx
        o_mat = o
        if has_tex == 1:
            o += fc * 2
        o_tidx = o
        o += ltex
        o_col = o
        o += fc * 2
        o_x = o
        o += lx
        o_y = o
        o += ly
        o_z = o
        o += lz
        o_simple = o
        self._vertices(Buffer(data, tc), Buffer(data, o_x), Buffer(data, o_y), Buffer(data, o_z),
                       Buffer(data, o_vskin), vc, has_vskins == 1)
        cb, rb, pb, ab, sb, mb, kb = (Buffer(data, x) for x in (o_col, o_render, o_prio, o_alpha, o_fskin, o_mat, o_tidx))
        self.colors = [0] * fc
        self.render_types = [0] * fc if has_render else None
        self.priorities = [0] * fc if prio == 255 else None
        if prio != 255:
            self.priority = prio
        self.alphas = [0] * fc if has_alpha == 1 else None
        self.fskins = [0] * fc if has_fskins == 1 else None
        self.textures = [-1] * fc if has_tex == 1 else None
        self.tex_coords = [-1] * fc if (has_tex == 1 and tc > 0) else None
        for i in range(fc):
            self.colors[i] = cb.u16()
            if has_render:
                self.render_types[i] = rb.s8()
            if prio == 255:
                self.priorities[i] = pb.s8()
            if has_alpha == 1:
                self.alphas[i] = ab.s8()
            if has_fskins == 1:
                self.fskins[i] = sb.u8()
            if has_tex == 1:
                self.textures[i] = _i16(mb.u16() - 1)
            if self.tex_coords is not None:
                if self.textures and self.textures[i] != -1:
                    self.tex_coords[i] = _i8(kb.u8() - 1)
        self._indices(Buffer(data, o_ctype), Buffer(data, o_idx), fc)
        pb = Buffer(data, o_simple)
        self.tex_p, self.tex_m, self.tex_n = [0] * tc, [0] * tc, [0] * tc
        for i in range(tc):
            if (self.tex_types[i] & 0xFF) == 0:
                self.tex_p[i], self.tex_m[i], self.tex_n[i] = pb.u16(), pb.u16(), pb.u16()
        if self.version >= 13:
            self.vx = [v >> 2 for v in self.vx]
            self.vy = [v >> 2 for v in self.vy]
            self.vz = [v >> 2 for v in self.vz]

    # ------------------------------------------------------------------ edits
    def copy(self) -> "ModelData":
        m = ModelData()
        for k in self.__slots__:
            v = getattr(self, k)
            setattr(m, k, list(v) if isinstance(v, list) else v)
        return m

    def recolor(self, frm, to):
        for f, t in zip(frm, to):
            self.colors = [t if c == f else c for c in self.colors]

    def retexture(self, frm, to):
        if self.textures is None:
            return
        for f, t in zip(frm, to):
            self.textures = [_i16(t) if x == _i16(f) else x for x in self.textures]

    def scale(self, sx, sy, sz):
        """Resize (128 = 100%)."""
        self.vx = [v * sx // 128 for v in self.vx]
        self.vy = [v * sy // 128 for v in self.vy]
        self.vz = [v * sz // 128 for v in self.vz]

    def translate(self, x, y, z):
        self.vx = [v + x for v in self.vx]
        self.vy = [v + y for v in self.vy]
        self.vz = [v + z for v in self.vz]

    def rotate90(self):
        self.vx, self.vz = list(self.vz), [-v for v in self.vx]

    def rotate(self, quarter_turns: int):
        for _ in range(quarter_turns & 3):
            self.rotate90()

    def rotate_angle(self, angle: int):
        """Client yaw in 2048ths of a turn."""
        a = angle * 2 * math.pi / 2048
        s, c = math.sin(a), math.cos(a)
        nx = [round(z * s + x * c) for x, z in zip(self.vx, self.vz)]
        nz = [round(z * c - x * s) for x, z in zip(self.vx, self.vz)]
        self.vx, self.vz = nx, nz

    def mirror(self):
        self.vz = [-v for v in self.vz]
        self.i1, self.i3 = self.i3, self.i1

    @staticmethod
    def merge(models) -> "ModelData":
        """Concatenates models (no vertex welding, so labels stay intact)."""
        models = [m for m in models if m is not None]
        out = ModelData()
        out.version = 12
        any_ = lambda attr: any(getattr(m, attr) is not None for m in models)
        has_rt, has_alpha, has_fs, has_tex, has_tc = (any_(a) for a in
                                                     ("render_types", "alphas", "fskins", "textures", "tex_coords"))
        out.vskins = [] if any_("vskins") else None
        out.maya_groups = [] if any_("maya_groups") else None
        out.maya_scales = [] if out.maya_groups is not None else None
        out.render_types = [] if has_rt else None
        out.alphas = [] if has_alpha else None
        out.fskins = [] if has_fs else None
        out.textures = [] if has_tex else None
        out.tex_coords = [] if has_tc else None
        out.priorities = []
        for m in models:
            vbase = len(out.vx)
            tbase = len(out.tex_p)
            out.vx += m.vx
            out.vy += m.vy
            out.vz += m.vz
            if out.vskins is not None:
                out.vskins += m.vskins if m.vskins is not None else [-1] * m.vertex_count
            if out.maya_groups is not None:
                out.maya_groups += m.maya_groups if m.maya_groups is not None else [[] for _ in range(m.vertex_count)]
                out.maya_scales += m.maya_scales if m.maya_scales is not None else [[] for _ in range(m.vertex_count)]
            out.i1 += [i + vbase for i in m.i1]
            out.i2 += [i + vbase for i in m.i2]
            out.i3 += [i + vbase for i in m.i3]
            out.colors += m.colors
            fc = m.face_count
            if has_rt:
                out.render_types += m.render_types if m.render_types is not None else [0] * fc
            if has_alpha:
                out.alphas += m.alphas if m.alphas is not None else [0] * fc
            if has_fs:
                out.fskins += m.fskins if m.fskins is not None else [-1] * fc
            if has_tex:
                out.textures += m.textures if m.textures is not None else [-1] * fc
            if has_tc:
                if m.tex_coords is not None:
                    out.tex_coords += [(c + tbase) if c != -1 else -1 for c in m.tex_coords]
                else:
                    out.tex_coords += [-1] * fc
            out.priorities += m.priorities if m.priorities is not None else [m.priority] * fc
            out.tex_types += m.tex_types
            out.tex_p += [p + vbase for p in m.tex_p]
            out.tex_m += [p + vbase for p in m.tex_m]
            out.tex_n += [p + vbase for p in m.tex_n]
        return out

    # ------------------------------------------------------------------ uvs
    def face_uvs(self, i):
        """Texture coordinates for face i's three corners (simple mapping only)."""
        tc = self.tex_coords[i] if self.tex_coords is not None else -1
        a, b, c = self.i1[i], self.i2[i], self.i3[i]
        if tc != -1:
            tc &= 0xFF
            if tc >= len(self.tex_types) or (self.tex_types[tc] & 0xFF) != 0:
                return (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
            p, m, n = self.tex_p[tc], self.tex_m[tc], self.tex_n[tc]
        else:
            p, m, n = a, b, c
        vx, vy, vz = self.vx, self.vy, self.vz
        if max(p, m, n) >= len(vx):
            return (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
        x0, y0, z0 = vx[p], vy[p], vz[p]
        f882, f883, f884 = vx[m] - x0, vy[m] - y0, vz[m] - z0
        f885, f886, f887 = vx[n] - x0, vy[n] - y0, vz[n] - z0
        pts = [(vx[k] - x0, vy[k] - y0, vz[k] - z0) for k in (a, b, c)]
        f897 = f883 * f887 - f884 * f886
        f898 = f884 * f885 - f882 * f887
        f899 = f882 * f886 - f883 * f885
        f900 = f886 * f899 - f887 * f898
        f901 = f887 * f897 - f885 * f899
        f902 = f885 * f898 - f886 * f897
        d = f900 * f882 + f901 * f883 + f902 * f884
        if d == 0:
            return (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
        us = [(f900 * x + f901 * y + f902 * z) / d for x, y, z in pts]
        g900 = f883 * f899 - f884 * f898
        g901 = f884 * f897 - f882 * f899
        g902 = f882 * f898 - f883 * f897
        d2 = g900 * f885 + g901 * f886 + g902 * f887
        if d2 == 0:
            return (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
        vs = [(g900 * x + g901 * y + g902 * z) / d2 for x, y, z in pts]
        u0, u1, u2 = us
        if 0.99 < u1 - u0 < 1.1:
            u1 = 1.0
        if 0.99 < u2 - u1 < 1.1:
            u2 = 1.0
        if 0.99 < u0 - u2 < 1.1:
            u0 = 1.0
        if 0.99 < u0 - u1 < 1.1:
            u0 = 1.0
        if 0.99 < u1 - u2 < 1.1:
            u1 = 1.0
        if 0.99 < u2 - u0 < 1.1:
            u2 = 1.0
        return (u0, vs[0]), (u1, vs[1]), (u2, vs[2])

    def bounds(self):
        if not self.vx:
            return (0, 0, 0), (0, 0, 0)
        return (min(self.vx), min(self.vy), min(self.vz)), (max(self.vx), max(self.vy), max(self.vz))


class ModelLoader:
    def __init__(self, cache):
        self.cache = cache
        self._memo = {}

    def get(self, model_id: int):
        if model_id is None or model_id < 0:
            return None
        if model_id not in self._memo:
            data = self.cache.file(MODELS, model_id, 0)
            self._memo[model_id] = ModelData.decode(data, model_id) if data else None
        m = self._memo[model_id]
        return m.copy() if m is not None else None

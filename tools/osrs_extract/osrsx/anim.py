"""Classic (frame-based) OSRS animations as per-label affine transforms.

The client animates a model by moving groups of vertices ("labels", the
vertex skin values) with a framemap's ORIGIN / TRANSLATE / ROTATE / SCALE
operations (rs-map-viewer Model.transform, BSD-2-Clause). Every vertex in a
label receives the same sequence of operations, so each label's motion in a
frame is exactly one affine map. We track those maps instead of moving
vertices, which turns a label into a bone.

Coordinates are client units, y down. Matrices are 3x4 row-major lists.
"""
import math

from .buffer import Buffer

ANIMATIONS, SKELETONS = 0, 1
ORIGIN, TRANSLATE, ROTATE, SCALE, ALPHA, TYPE6, LIGHT, TYPE10 = 0, 1, 2, 3, 5, 6, 7, 10

IDENTITY = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]


def mat_mul(a, b):
    """a * b for 3x4 affine matrices."""
    return [
        a[0] * b[0] + a[1] * b[4] + a[2] * b[8],
        a[0] * b[1] + a[1] * b[5] + a[2] * b[9],
        a[0] * b[2] + a[1] * b[6] + a[2] * b[10],
        a[0] * b[3] + a[1] * b[7] + a[2] * b[11] + a[3],
        a[4] * b[0] + a[5] * b[4] + a[6] * b[8],
        a[4] * b[1] + a[5] * b[5] + a[6] * b[9],
        a[4] * b[2] + a[5] * b[6] + a[6] * b[10],
        a[4] * b[3] + a[5] * b[7] + a[6] * b[11] + a[7],
        a[8] * b[0] + a[9] * b[4] + a[10] * b[8],
        a[8] * b[1] + a[9] * b[5] + a[10] * b[9],
        a[8] * b[2] + a[9] * b[6] + a[10] * b[10],
        a[8] * b[3] + a[9] * b[7] + a[10] * b[11] + a[11],
    ]


def mat_apply(m, x, y, z):
    return (m[0] * x + m[1] * y + m[2] * z + m[3],
            m[4] * x + m[5] * y + m[6] * z + m[7],
            m[8] * x + m[9] * y + m[10] * z + m[11])


def _translate(x, y, z):
    return [1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, z]


def _rotation(tx, ty, tz):
    """The client's roll (z), then pitch (x), then yaw (y), 256ths of a turn."""
    def ang(t):
        return ((t & 0xFF) * 8) * 2.0 * math.pi / 2048.0
    m = list(IDENTITY)
    az, ax, ay = ang(tz), ang(tx), ang(ty)
    if tz & 0xFF:
        s, c = math.sin(az), math.cos(az)
        m = mat_mul([c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0], m)
    if tx & 0xFF:
        s, c = math.sin(ax), math.cos(ax)
        m = mat_mul([1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0], m)
    if ty & 0xFF:
        s, c = math.sin(ay), math.cos(ay)
        m = mat_mul([c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0], m)
    return m


class Framemap:
    def __init__(self, id_, types, labels):
        self.id = id_
        self.types = types
        self.labels = labels


class Frame:
    def __init__(self, base, groups, xs, ys, zs, resets):
        self.base = base
        self.groups = groups
        self.xs, self.ys, self.zs = xs, ys, zs
        self.resets = resets


class AnimLoader:
    def __init__(self, cache):
        self.cache = cache
        self._bases = {}
        self._frames = {}

    def base(self, base_id):
        if base_id not in self._bases:
            data = self.cache.file(SKELETONS, base_id, 0)
            fm = None
            if data:
                b = Buffer(data)
                n = b.u8()
                types = [b.u8() for _ in range(n)]
                types = [ROTATE if t == TYPE6 else t for t in types]
                counts = [b.u8() for _ in range(n)]
                labels = [[b.u8() for _ in range(c)] for c in counts]
                fm = Framemap(base_id, types, labels)
            self._bases[base_id] = fm
        return self._bases[base_id]

    def frame(self, frame_id):
        if frame_id in self._frames:
            return self._frames[frame_id]
        group = frame_id >> 16
        files = self.cache.files(ANIMATIONS, group)
        for fid, data in files.items():
            self._frames[(group << 16) | fid] = self._decode(data)
        return self._frames.get(frame_id)

    def _decode(self, data):
        b = Buffer(data)
        base = self.base(b.u16())
        if base is None:
            return None
        count = b.u8()
        d = Buffer(data, b.pos + count)
        groups, xs, ys, zs, resets = [], [], [], [], []
        reset_group = last_reset = -1
        for i in range(count):
            t = base.types[i] if i < len(base.types) else -1
            if t == ORIGIN:
                reset_group = i
            flag = b.u8()
            if flag == 0:
                continue
            if t == ORIGIN:
                last_reset = i
            default = 128 if t in (SCALE, TYPE10) else 0
            groups.append(i)
            xs.append(d.smart2() if flag & 1 else default)
            ys.append(d.smart2() if flag & 2 else default)
            zs.append(d.smart2() if flag & 4 else default)
            r = -1
            if t in (TRANSLATE, ROTATE, SCALE) and reset_group > last_reset:
                r = reset_group
                last_reset = reset_group
            resets.append(r)
        return Frame(base, groups, xs, ys, zs, resets)


class LabelRig:
    """Rest data for one model's labels: vertex sums and counts per label."""

    def __init__(self, model):
        self.sums = {}
        self.counts = {}
        if model.vskins is None:
            return
        for x, y, z, l in zip(model.vx, model.vy, model.vz, model.vskins):
            if l < 0:
                continue
            s = self.sums.get(l)
            if s is None:
                self.sums[l] = [x, y, z]
                self.counts[l] = 1
            else:
                s[0] += x
                s[1] += y
                s[2] += z
                self.counts[l] += 1

    @property
    def labels(self):
        return sorted(self.counts)

    def centroid(self, l):
        s, n = self.sums[l], self.counts[l]
        return (s[0] / n, s[1] / n, s[2] / n)

    def pose(self, frame):
        """{label: 3x4 matrix} mapping rest positions to this frame's pose."""
        mats = {l: list(IDENTITY) for l in self.counts}
        if frame is None:
            return mats
        base = frame.base
        origin = [0.0, 0.0, 0.0]

        def do(t, labels, tx, ty, tz):
            nonlocal origin
            if t == ORIGIN:
                sx = sy = sz = 0.0
                n = 0
                for l in labels:
                    if l in mats:
                        m = mats[l]
                        s = self.sums[l]
                        c = self.counts[l]
                        px, py, pz = mat_apply(m, s[0] / c, s[1] / c, s[2] / c)
                        sx += px * c
                        sy += py * c
                        sz += pz * c
                        n += c
                if n:
                    origin = [tx + int(sx / n), ty + int(sy / n), tz + int(sz / n)]
                else:
                    origin = [tx, ty, tz]
            elif t == TRANSLATE:
                tm = _translate(tx, ty, tz)
                for l in labels:
                    if l in mats:
                        mats[l] = mat_mul(tm, mats[l])
            elif t == ROTATE:
                rm = mat_mul(_translate(*origin), mat_mul(_rotation(tx, ty, tz), _translate(-origin[0], -origin[1], -origin[2])))
                for l in labels:
                    if l in mats:
                        mats[l] = mat_mul(rm, mats[l])
            elif t == SCALE:
                sm = [tx / 128.0, 0, 0, 0, 0, ty / 128.0, 0, 0, 0, 0, tz / 128.0, 0]
                sm = mat_mul(_translate(*origin), mat_mul(sm, _translate(-origin[0], -origin[1], -origin[2])))
                for l in labels:
                    if l in mats:
                        mats[l] = mat_mul(sm, mats[l])
            # ALPHA / LIGHT change face colours, not positions: ignored.

        for i, g in enumerate(frame.groups):
            if g >= len(base.types):
                continue
            r = frame.resets[i]
            if r != -1:
                do(ORIGIN, base.labels[r], 0, 0, 0)
            do(base.types[g], base.labels[g], frame.xs[i], frame.ys[i], frame.zs[i])
        return mats


def seq_frames(seq, anims):
    """[(frame, length_in_client_cycles)] for a classic sequence."""
    out = []
    for fid, ln in zip(seq.frame_ids, seq.frame_lengths):
        out.append((anims.frame(fid), max(1, ln)))
    return out

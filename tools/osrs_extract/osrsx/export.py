"""Turns decoded models and animations into GLB files for Godot.

World space: 1 tile (128 client units) = 1 metre, y up. The client's
(x, y-down, z) becomes (x, -y, -z), a 180-degree turn about X, so handedness
and face winding are kept.
"""
import math

from .anim import LabelRig, mat_mul
from .colors import hsl_to_linear, srgb_to_linear
from .gltf import USHORT, UINT, ELEMENT_ARRAY_BUFFER, Gltf

UNIT = 1.0 / 128.0
CYCLE = 0.02          # one client cycle in seconds


def to_world(x, y, z):
    return (x * UNIT, -y * UNIT, -z * UNIT)


# ---------------------------------------------------------------- math helpers
def _decompose(m):
    """3x4 client-space affine -> world TRS (t, quat xyzw, s)."""
    # similarity with D = diag(1,-1,-1), translation scaled by UNIT
    d = (1.0, -1.0, -1.0)
    a = [[m[r * 4 + c] * d[r] * d[c] for c in range(3)] for r in range(3)]
    t = (m[3] * UNIT, -m[7] * UNIT, -m[11] * UNIT)
    cols = [[a[r][c] for r in range(3)] for c in range(3)]
    s = [math.sqrt(sum(v * v for v in col)) or 1e-9 for col in cols]
    x = [v / s[0] for v in cols[0]]
    y = [v / s[1] for v in cols[1]]
    # Gram-Schmidt
    dot = sum(p * q for p, q in zip(x, y))
    y = [q - dot * p for p, q in zip(x, y)]
    ln = math.sqrt(sum(v * v for v in y)) or 1e-9
    y = [v / ln for v in y]
    z = [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]]
    zc = [v / s[2] for v in cols[2]]
    if sum(p * q for p, q in zip(z, zc)) < 0:
        s[2] = -s[2]
    r = [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]
    return t, _quat(r), s


def _quat(r):
    tr = r[0][0] + r[1][1] + r[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w = 0.25 * s
        x = (r[2][1] - r[1][2]) / s
        y = (r[0][2] - r[2][0]) / s
        z = (r[1][0] - r[0][1]) / s
    elif r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        s = math.sqrt(1.0 + r[0][0] - r[1][1] - r[2][2]) * 2
        w = (r[2][1] - r[1][2]) / s
        x = 0.25 * s
        y = (r[0][1] + r[1][0]) / s
        z = (r[0][2] + r[2][0]) / s
    elif r[1][1] > r[2][2]:
        s = math.sqrt(1.0 + r[1][1] - r[0][0] - r[2][2]) * 2
        w = (r[0][2] - r[2][0]) / s
        x = (r[0][1] + r[1][0]) / s
        y = 0.25 * s
        z = (r[1][2] + r[2][1]) / s
    else:
        s = math.sqrt(1.0 + r[2][2] - r[0][0] - r[1][1]) * 2
        w = (r[1][0] - r[0][1]) / s
        x = (r[0][2] + r[2][0]) / s
        y = (r[1][2] + r[2][1]) / s
        z = 0.25 * s
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    return (x / n, y / n, z / n, w / n)


# ---------------------------------------------------------------- meshes
class MeshOptions:
    def __init__(self, textures=None, joint_of_label=None, name="mesh"):
        self.textures = textures
        self.joint_of_label = joint_of_label
        self.name = name


def _vertex_normals(model, wpos):
    n = len(wpos)
    acc = [[0.0, 0.0, 0.0] for _ in range(n)]
    fnorm = []
    for f in range(model.face_count):
        a, b, c = model.i1[f], model.i2[f], model.i3[f]
        pa, pb, pc = wpos[a], wpos[b], wpos[c]
        ux, uy, uz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
        vx, vy, vz = pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        nn = (nx / ln, ny / ln, nz / ln)
        fnorm.append(nn)
        for k in (a, b, c):
            acc[k][0] += nn[0]
            acc[k][1] += nn[1]
            acc[k][2] += nn[2]
    vn = []
    for x, y, z in acc:
        ln = math.sqrt(x * x + y * y + z * z) or 1.0
        vn.append((x / ln, y / ln, z / ln))
    return vn, fnorm


def face_visible(model, f):
    if model.render_types is not None and model.render_types[f] == 2:
        return False
    if model.alphas is not None and (model.alphas[f] & 0xFF) == 255:
        return False
    if model.colors[f] == 65534:   # client "hidden" colour
        return False
    return True


DECAL_LIFT = 0.004    # metres a decal face is lifted per priority step above the face under it


def _decal_offsets(model, wpos, fnorm):
    """OSRS draws coplanar faces in priority order (the patterns on d'hide,
    trims on armour); a depth buffer can't, so they flicker. Faces that share
    a plane with lower-priority faces are lifted off it along their normal,
    one small step per priority level. Returns {face: (dx, dy, dz)}."""
    pr = model.priorities
    if pr is None:
        return {}
    planes = {}
    for f in range(model.face_count):
        n = fnorm[f]
        p = wpos[model.i1[f]]
        d = n[0] * p[0] + n[1] * p[1] + n[2] * p[2]
        key = (round(n[0], 2), round(n[1], 2), round(n[2], 2), round(d / 0.002))
        planes.setdefault(key, []).append(f)
    out = {}
    for faces in planes.values():
        levels = sorted({pr[f] for f in faces})
        if len(levels) < 2:
            continue
        for f in faces:
            k = levels.index(pr[f])
            if k:
                n = fnorm[f]
                out[f] = (n[0] * DECAL_LIFT * k, n[1] * DECAL_LIFT * k, n[2] * DECAL_LIFT * k)
    return out


def build_primitives(g: Gltf, model, opts: MeshOptions, flip=False):
    """glTF primitives for one model, split by texture and transparency."""
    wpos = [to_world(x, y, z) for x, y, z in zip(model.vx, model.vy, model.vz)]
    vnorm, fnorm = _vertex_normals(model, wpos)
    lift = _decal_offsets(model, wpos, fnorm)
    groups = {}
    for f in range(model.face_count):
        if not face_visible(model, f):
            continue
        tex = model.textures[f] if model.textures is not None else -1
        if tex != -1 and (opts.textures is None or opts.textures.image(tex) is None):
            tex = -1
        alpha = (model.alphas[f] & 0xFF) if model.alphas is not None else 0
        groups.setdefault((tex, alpha > 0), []).append(f)
    prims = []
    skinned = opts.joint_of_label is not None and model.vskins is not None
    for (tex, transparent), faces in sorted(groups.items()):
        pos, nrm, col, uv, jnt, wgt, indices = [], [], [], [], [], [], []
        seen = {}
        for f in faces:
            idx = (model.i1[f], model.i2[f], model.i3[f])
            if flip:
                idx = (idx[0], idx[2], idx[1])
            flat = model.render_types is not None and model.render_types[f] == 1
            a = 1.0 - ((model.alphas[f] & 0xFF) / 255.0 if model.alphas is not None else 0.0)
            uvs = None
            if tex != -1:
                light = (model.colors[f] & 127) / 127.0 if model.colors[f] not in (127,) else 1.0
                lin = srgb_to_linear(min(1.0, max(0.0, light)))
                c = (lin, lin, lin, a)
                uvs = model.face_uvs(f)
                if flip:
                    uvs = (uvs[0], uvs[2], uvs[1])
            else:
                r, gg, b = hsl_to_linear(model.colors[f])
                c = (r, gg, b, a)
            off = lift.get(f)
            for k, vi in enumerate(idx):
                n = fnorm[f] if flat else vnorm[vi]
                u = uvs[k] if uvs else None
                key = (vi, n, c, u, off)
                at = seen.get(key)
                if at is None:
                    at = seen[key] = len(pos) // 3
                    if off:
                        wp = wpos[vi]
                        pos.extend((wp[0] + off[0], wp[1] + off[1], wp[2] + off[2]))
                    else:
                        pos.extend(wpos[vi])
                    nrm.extend(n)
                    col.extend(round(min(1.0, max(0.0, v)) * 65535) for v in c)
                    if u is not None:
                        uv.extend(u)
                    if skinned:
                        l = model.vskins[vi]
                        j = opts.joint_of_label.get(l, opts.joint_of_label.get("root", 0))
                        jnt.extend((j, 0, 0, 0))
                        wgt.extend((1.0, 0.0, 0.0, 0.0))
                indices.append(at)
        count = len(pos) // 3
        attrs = {"POSITION": g.accessor(pos, "VEC3", minmax=True),
                 "NORMAL": g.accessor(nrm, "VEC3"),
                 "COLOR_0": g.accessor(col, "VEC4", comp=USHORT, normalized=True)}
        if uv:
            attrs["TEXCOORD_0"] = g.accessor(uv, "VEC2")
        if skinned:
            attrs["JOINTS_0"] = g.accessor(jnt, "VEC4", comp=USHORT)
            attrs["WEIGHTS_0"] = g.accessor(wgt, "VEC4")
        ind = g.accessor(indices, "SCALAR", comp=UINT if count > 65535 else USHORT, target=ELEMENT_ARRAY_BUFFER)
        texture_index = None
        if tex != -1:
            texture_index = _texture_index(g, opts.textures, tex)
        name = ("tex%d" % tex if tex != -1 else "vc") + ("_alpha" if transparent else "")
        cutout = tex != -1 and not opts.textures.defs[tex].opaque
        mat = g.material(name, texture_index, blend=transparent, cutout=cutout)
        prims.append({"attributes": attrs, "indices": ind, "material": mat})
    return prims


def _texture_index(g, textures, tex):
    cache = g.__dict__.setdefault("_tex_cache", {})
    if tex not in cache:
        cache[tex] = g.image(textures.png(tex), "texture_%d" % tex)
    return cache[tex]


# ---------------------------------------------------------------- skeletons
class Skeleton:
    """Labels as bones. Bone rest = label centroid (world), no rotation."""

    def __init__(self, labels, centroids):
        self.labels = sorted(labels)
        self.centroids = centroids        # label -> client-space centroid

    @staticmethod
    def from_models(models):
        sums, counts = {}, {}
        for m in models:
            if m is None or m.vskins is None:
                continue
            for x, y, z, l in zip(m.vx, m.vy, m.vz, m.vskins):
                if l < 0:
                    continue
                s = sums.setdefault(l, [0.0, 0.0, 0.0])
                s[0] += x
                s[1] += y
                s[2] += z
                counts[l] = counts.get(l, 0) + 1
        cents = {l: (s[0] / counts[l], s[1] / counts[l], s[2] / counts[l]) for l, s in sums.items()}
        return Skeleton(cents.keys(), cents)

    def add_to(self, g: Gltf, root_name="Armature"):
        """Adds joint nodes under an armature node. Returns (armature, {label: node})."""
        nodes = {}
        children = []
        for l in self.labels:
            w = to_world(*self.centroids[l])
            nodes[l] = g.node("L%d" % l, translation=list(w))
            children.append(nodes[l])
        arm = g.node(root_name, children=children)
        return arm, nodes

    def inverse_binds(self):
        out = []
        for l in self.labels:
            x, y, z = to_world(*self.centroids[l])
            out += [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1]
        return out

    def joint_map(self):
        return {l: i for i, l in enumerate(self.labels)}


def animation_channels(skel: Skeleton, joint_nodes, rig: LabelRig, frames, interp="LINEAR", loop=True):
    """glTF channels for one sequence. frames: [(Frame, cycles)]."""
    times = []
    t = 0.0
    poses = []
    for fr, ln in frames:
        poses.append(rig.pose(fr))
        times.append(t)
        t += ln * CYCLE
    if not poses:
        return [], 0.0
    if loop:
        poses.append(poses[0])
    else:
        poses.append(poses[-1])
    times.append(t)
    chans = []
    for l in skel.labels:
        c = skel.centroids[l]
        cm = [1, 0, 0, c[0], 0, 1, 0, c[1], 0, 0, 1, c[2]]
        T, R, S = [], [], []
        for p in poses:
            m = p.get(l)
            g_ = mat_mul(m, cm) if m is not None else cm
            tr, q, s = _decompose(g_)
            T += tr
            R += q
            S += s
        # keep quaternion signs continuous
        for i in range(4, len(R), 4):
            if sum(R[i + k] * R[i - 4 + k] for k in range(4)) < 0:
                for k in range(4):
                    R[i + k] = -R[i + k]
        node = joint_nodes[l]
        chans.append((node, "translation", times, T, interp))
        chans.append((node, "rotation", times, R, interp))
        if any(abs(v - 1.0) > 1e-4 for v in S):
            chans.append((node, "scale", times, S, interp))
    return chans, t


def write_skinned(path, meshes, skel: Skeleton, clips, textures=None, extra_nodes=None):
    """meshes: [(node_name, ModelData)]. clips: [(name, rig, frames, loop)]."""
    g = Gltf()
    arm, jnodes = skel.add_to(g)
    joints = [jnodes[l] for l in skel.labels]
    skin = g.skin(joints, skel.inverse_binds(), skeleton=arm)
    jm = skel.joint_map()
    root_children = [arm]
    for name, model in meshes:
        prims = build_primitives(g, model, MeshOptions(textures, jm, name))
        if not prims:
            continue
        mesh = g.mesh(name, prims)
        root_children.append(g.node(name, mesh=mesh, skin=skin))
    root = g.node("root", children=root_children)
    g.add_root(root)
    for name, rig, frames, loop in clips:
        chans, _ = animation_channels(skel, jnodes, rig, frames, loop=loop)
        if chans:
            g.animation(name, chans)
    g.write(path)


def write_static(path, meshes, textures=None):
    """Unskinned model(s): [(node_name, ModelData)]."""
    g = Gltf()
    kids = []
    for name, model in meshes:
        prims = build_primitives(g, model, MeshOptions(textures, None, name))
        if prims:
            kids.append(g.node(name, mesh=g.mesh(name, prims)))
    g.add_root(g.node("root", children=kids))
    g.write(path)

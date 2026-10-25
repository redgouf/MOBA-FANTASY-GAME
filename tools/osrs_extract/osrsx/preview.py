"""A small software renderer for checking exports (needs numpy and Pillow).

Previews are for your own eyes: like the models, never commit them.
"""
from .colors import hsl_to_rgb


def render(model, path, size=384, yaw=0.6, pitch=0.35, positions=None, colors=None, textures=None):
    import numpy as np
    from PIL import Image

    vx = np.array(positions[0] if positions else model.vx, dtype=float)
    vy = np.array(positions[1] if positions else model.vy, dtype=float)
    vz = np.array(positions[2] if positions else model.vz, dtype=float)
    # client -> view: y up
    p = np.stack([vx, -vy, vz], 1)
    cy, sy = np.cos(yaw), np.sin(yaw)
    cp, sp = np.cos(pitch), np.sin(pitch)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    p = p @ ry.T @ rx.T
    mn, mx = p.min(0), p.max(0)
    span = max(mx[0] - mn[0], mx[1] - mn[1], 1)
    scale = size * 0.9 / span
    cx = (mn[0] + mx[0]) / 2
    cyy = (mn[1] + mx[1]) / 2
    sx = (p[:, 0] - cx) * scale + size / 2
    syy = size / 2 - (p[:, 1] - cyy) * scale
    sz = p[:, 2]
    img = np.full((size, size, 3), 40, np.uint8)
    zbuf = np.full((size, size), np.inf)
    light = np.array([0.4, 0.8, -0.45])
    light /= np.linalg.norm(light)
    cols = colors if colors is not None else model.colors
    for f in range(model.face_count):
        if model.render_types is not None and model.render_types[f] == 2:
            continue
        if model.alphas is not None and (model.alphas[f] & 0xFF) >= 254:
            continue
        a, b, c = model.i1[f], model.i2[f], model.i3[f]
        tri = np.array([[sx[a], syy[a]], [sx[b], syy[b]], [sx[c], syy[c]]])
        z3 = np.array([sz[a], sz[b], sz[c]])
        n = np.cross(p[b] - p[a], p[c] - p[a])
        ln = np.linalg.norm(n)
        if ln == 0:
            continue
        n /= ln
        shade = 0.45 + 0.55 * abs(float(n @ light))
        if model.textures is not None and model.textures[f] != -1:
            rgb = 0x8a7b62
            if textures is not None:
                d = textures.defs.get(model.textures[f])
                if d:
                    rgb = hsl_to_rgb(d.average_hsl)
        else:
            rgb = hsl_to_rgb(cols[f])
        col = np.array([(rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255], float) * shade
        x0, y0 = np.floor(tri.min(0)).astype(int)
        x1, y1 = np.ceil(tri.max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax_, ay_), (bx_, by_), (cx_, cy_) = tri
        den = (by_ - cy_) * (ax_ - cx_) + (cx_ - bx_) * (ay_ - cy_)
        if abs(den) < 1e-9:
            continue
        w0 = ((by_ - cy_) * (xs - cx_) + (cx_ - bx_) * (ys - cy_)) / den
        w1 = ((cy_ - ay_) * (xs - cx_) + (ax_ - cx_) * (ys - cy_)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = w0 * z3[0] + w1 * z3[1] + w2 * z3[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        m = inside & (z < sub)
        sub[m] = z[m]
        img[y0:y1 + 1, x0:x1 + 1][m] = np.clip(col, 0, 255).astype(np.uint8)
    Image.fromarray(img).save(path)

#!/usr/bin/env python3
"""Turns a League of Legends Summoner's Rift navigation grid (AIPath.aimesh_ngrid,
extracted from Map11.wad.client) into data/map.json, in game metres.

Usage:  python tools/rift_classic/extract_navgrid.py PATH/TO/aipath.aimesh_ngrid [--out data/map.json]

Only the derived layout (wall outlines, brush/river grids, lane lines, camp
spots) is written; the Riot file itself is never copied into the repo.
Needs numpy, scipy and scikit-image. The file layout follows FrankTheBoxMonster's
LoL-NGRID-converter (version 7, 48-byte cells).
"""
import argparse, json, math, struct
import numpy as np
from scipy import ndimage
from skimage import measure

XC, ZC = 295, 296
CELL = 50.0                     # LoL units per cell
UNITS_PER_M = 75.0              # rules.lol_units_per_meter

NEXUS_SARADOMIN = [-78.3, 77.3]   # metres, bottom-left base

# VisionPathingFlags
BRUSH, WALL, STRUCT_WALL, TRANSPARENT, BLUE_ONLY, RED_ONLY = 1, 2, 4, 64, 1024, 2048


def load(path):
    d = open(path, "rb").read()
    assert d[0] == 7, "expected an NGRID version 7 file"
    mn = np.frombuffer(d[3:15], "<f4"); mx = np.frombuffer(d[15:27], "<f4")
    cell = struct.unpack_from("<f", d, 27)[0]
    xc, zc = struct.unpack_from("<2i", d, 31)
    assert (xc, zc) == (XC, ZC) and cell == CELL, (xc, zc, cell)
    n = xc * zc
    base = 39
    rec = np.frombuffer(d[base:base + 48 * n], np.uint8).reshape(n, 48)
    cx = rec[:, 20:22].copy().view("<i2")[:, 0]; cz = rec[:, 22:24].copy().view("<i2")[:, 0]
    o = base + 48 * n
    vp = np.frombuffer(d[o:o + 2 * n], "<u2"); o += 2 * n
    ex = np.frombuffer(d[o:o + 4 * n], np.uint8).reshape(n, 4)
    def grid(a, dtype):
        g = np.zeros((zc, xc), dtype); g[cz, cx] = a; return g
    return dict(min=mn, V=grid(vp, np.uint16), R=grid(ex[:, 0], np.uint8),
                J=grid(ex[:, 1] & 15, np.uint8), M=grid(ex[:, 1] >> 4, np.uint8),
                L=grid(ex[:, 2] & 15, np.uint8), P=grid(ex[:, 2] >> 4, np.uint8))


class Frame:
    """cell (col,row) <-> game metres. The map is point-symmetric about (cx, cy) in LoL units."""
    def __init__(self, mn, sym):
        self.x0 = float(mn[0]); self.y0 = float(mn[2]); self.cx, self.cy = sym
    def metres(self, col, row):          # cell-centre coordinates (floats allowed)
        X = self.x0 + (col + 0.5) * CELL; Y = self.y0 + (row + 0.5) * CELL
        return (X - self.cx) / UNITS_PER_M, -(Y - self.cy) / UNITS_PER_M

    def cell(self, x_m, z_m):            # game metres -> (col, row) cell-centre coordinates
        X = x_m * UNITS_PER_M + self.cx; Y = -z_m * UNITS_PER_M + self.cy
        return (X - self.x0) / CELL - 0.5, (Y - self.y0) / CELL - 0.5


def symmetry_centre(V, mn):
    """Find the point reflection that maps the wall layout onto itself (in cell units)."""
    w = ((V & (WALL | STRUCT_WALL)) > 0).astype(np.int8)
    best = None
    for dz in range(-3, 4):
        for dx in range(-3, 4):
            f = np.roll(np.roll(w[::-1, ::-1], dz, 0), dx, 1)
            s = int((f == w).sum())
            if best is None or s > best[0]:
                best = (s, dx, dz)
    _, dx, dz = best
    # reflection col -> (XC-1) - col + dx  => centre at col = (XC-1+dx)/2
    ccol = (XC - 1 + dx) / 2.0; crow = (ZC - 1 + dz) / 2.0
    X = float(mn[0]) + (ccol + 0.5) * CELL; Y = float(mn[2]) + (crow + 0.5) * CELL
    return (X, Y), best[0] / w.size


def simplify(pts, tol):
    return measure.approximate_polygon(pts, tol)


def area(p):
    x, y = p[:, 0], p[:, 1]
    return 0.5 * float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def trace(mask, tol=0.35, min_cells=2):
    """Outlines of a boolean mask as simple polygons (no holes): a block with a
    hole is split in two until the hole is cut open. Coordinates in (col,row)."""
    out = []
    def go(r0, r1, c0, c1):
        sub = mask[r0:r1, c0:c1]
        if not sub.any():
            return
        pad = np.pad(sub, 1).astype(np.float32)
        cons = [c for c in measure.find_contours(pad, 0.5) if len(c) >= 4]
        holes = 0
        polys = []
        for c in cons:
            c = c[:-1] if np.allclose(c[0], c[-1]) else c
            c = c - 1.0                         # undo padding
            c[:, 0] += r0; c[:, 1] += c0
            polys.append(c)
        # the outer outline of a component has the opposite sign to its holes
        signs = [area(p[:, ::-1]) > 0 for p in polys]
        if len(set(signs)) > 1 and max(r1 - r0, c1 - c0) > 2:
            if (r1 - r0) >= (c1 - c0):
                m = (r0 + r1) // 2; go(r0, m, c0, c1); go(m, r1, c0, c1)
            else:
                m = (c0 + c1) // 2; go(r0, r1, c0, m); go(r0, r1, m, c1)
            return
        for p in polys:
            q = simplify(p, tol)
            if len(q) >= 4:
                out.append(q[:-1])
    # blocks of ~40 cells keep polygons small and mostly hole-free
    for r in range(0, mask.shape[0], 40):
        for c in range(0, mask.shape[1], 40):
            go(r, min(r + 40, mask.shape[0]), c, min(c + 40, mask.shape[1]))
    return out


def rle(g):
    rows = []
    for r in g:
        runs = []; start = 0
        for i in range(1, len(r) + 1):
            if i == len(r) or r[i] != r[start]:
                runs.append([int(r[start]), i - start]); start = i
        rows.append(runs)
    return rows


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("ngrid"); ap.add_argument("--out", default="data/map.json")
    a = ap.parse_args()
    g = load(a.ngrid)
    V = g["V"]
    sym, score = symmetry_centre(V, g["min"])
    F = Frame(g["min"], sym)
    print("symmetry centre (LoL units)", sym, "match", round(score, 4))

    wall = (V & (WALL | STRUCT_WALL)) > 0
    wall &= ~(((V & TRANSPARENT) > 0) & ~((V & WALL) > 0))   # keep it simple: transparent walls stay walls
    brush = (V & BRUSH) > 0
    river = (g["R"] & 16) > 0

    def to_m(poly):
        return [[round(v, 2) for v in F.metres(p[1], p[0])] for p in poly]

    walls = [to_m(p) for p in trace(wall)]
    gates = {}
    for team, bit in (("saradomin", BLUE_ONLY), ("zamorak", RED_ONLY)):
        m = (V & bit) > 0
        lab, n = ndimage.label(m)
        gates[team] = []
        for i in range(1, n + 1):
            zz, xx = np.nonzero(lab == i)
            if len(xx) < 3:
                continue
            gates[team].append(dict(pos=[round(v, 2) for v in F.metres(xx.mean(), zz.mean())],
                                    size=[round((xx.max() - xx.min() + 1) * CELL / UNITS_PER_M, 2),
                                          round((zz.max() - zz.min() + 1) * CELL / UNITS_PER_M, 2)]))

    # points of interest: camp spots (centroids), pits, bases
    poi_names = {3: "baron", 4: "dragon", 5: "red", 6: "blue", 7: "gromp", 8: "krugs", 9: "raptors", 10: "murkwolves"}
    pois = {}
    for k, name in poi_names.items():
        lab, n = ndimage.label(g["P"] == k)
        for i in range(1, n + 1):
            zz, xx = np.nonzero(lab == i)
            if len(xx) < 8:
                continue
            x, z = F.metres(xx.mean(), zz.mean())
            pois.setdefault(name, []).append([round(x, 2), round(z, 2)])
    def sara(l):   # the Saradomin (bottom-left) one: smaller x - z... bottom-left = x < 0 and z > 0 side
        return min(l, key=lambda p: p[0] - p[1])
    camps = {}
    for name, lst in pois.items():
        if name in ("baron", "dragon"):
            camps[name] = [float(v) for v in lst[0]]
        else:
            camps[name] = [float(v) for v in sara(lst)]
    # prayer altars: a roomy open spot 5-9 m from each buff camp, on the side facing the Saradomin base
    clearance = ndimage.distance_transform_edt(~((V & (WALL | STRUCT_WALL)) > 0)) * CELL / UNITS_PER_M
    rr, cc = np.mgrid[0:ZC, 0:XC]
    altars = []
    for name in ("blue", "red"):
        cx_m, cz_m = camps[name]
        X = (F.x0 + (cc + 0.5) * CELL - F.cx) / UNITS_PER_M
        Z = -((F.y0 + (rr + 0.5) * CELL) - F.cy) / UNITS_PER_M
        d = np.hypot(X - cx_m, Z - cz_m)
        ok = (d >= 5.0) & (d <= 9.0) & (clearance >= 2.0) & (V & BRUSH == 0)
        score = np.where(ok, clearance - 0.05 * np.hypot(X - NEXUS_SARADOMIN[0], Z - NEXUS_SARADOMIN[1]), -1e9)
        r, c = np.unravel_index(int(np.argmax(score)), score.shape)
        altars.append(dict(side=name, pos=[round(float(X[r, c]), 2), round(float(Z[r, c]), 2)]))
    # base and fountain
    out = dict(
        _comment="Written by tools/rift_classic/extract_navgrid.py from a Summoner's Rift navigation grid. Metres: x east, z south (screen-up is -z); the map is point-symmetric about (0,0). Saradomin is the bottom-left (x<0, z>0).",
        source="League of Legends Summoner's Rift navigation grid (AIPath), 295 x 296 cells of 50 units; 75 units = 1 m",
        cell_m=round(CELL / UNITS_PER_M, 4),
        grid=dict(cols=XC, rows=ZC, origin=[round(v, 3) for v in F.metres(-0.5, ZC - 0.5)],
                  note="origin = [x_west, z_north] of the grid in metres. Row 0 is the southern-most row, so the centre of cell (col, row) is x = origin_x + (col + 0.5) * cell_m, z = origin_z + (rows - 1 - row + 0.5) * cell_m. Sampling the RLE grids: index = row * cols + col."),
        walls=walls, gates=gates, camps=camps, prayer_altars_saradomin=altars,
        brush_rle=rle((brush & ~wall).astype(np.uint8)), river_rle=rle(river.astype(np.uint8)),
        wall_rle=rle(wall.astype(np.uint8)),
        pit_rle=rle(np.isin(g["P"], (3, 4)).astype(np.uint8)),
        base_rle=rle(np.isin(g["M"], (0, 1)).astype(np.uint8)),
    )
    # structures: the footprints of turrets, inhibitors and the nexus are structure-wall blobs
    lab, n = ndimage.label((V & STRUCT_WALL) > 0, structure=np.ones((3, 3)))
    blobs = []
    for i in range(1, n + 1):
        zz, xx = np.nonzero(lab == i)
        x, z = F.metres(xx.mean(), zz.mean())
        blobs.append(dict(pos=[round(float(x), 2), round(float(z), 2)], cells=int(len(xx))))
    sara = [b for b in blobs if b["pos"][1] - b["pos"][0] > 0 and b["cells"] >= 15 and abs(b["pos"][0]) < 95]
    nex = max(sara, key=lambda b: b["cells"])
    rest = [b for b in sara if b is not nex]
    nexus = dict(saradomin=nex["pos"], zamorak=[-nex["pos"][0], -nex["pos"][1]])
    def dist_to(b, p):
        return math.hypot(b["pos"][0] - p[0], b["pos"][1] - p[1])
    nexus_turrets = sorted([b for b in rest if dist_to(b, nex["pos"]) < 14 and b["cells"] < 30], key=lambda b: b["pos"][0])
    rest = [b for b in rest if b not in nexus_turrets]
    structures = dict(nexus=nex["pos"], nexus_turrets=[b["pos"] for b in nexus_turrets])
    for b in rest:
        b["lane"] = "mid" if abs(b["pos"][0] + b["pos"][1]) < 25 else ("top" if b["pos"][0] + b["pos"][1] < 0 else "bot")
    for lane in ("top", "mid", "bot"):
        mine = sorted([b for b in rest if b["lane"] == lane], key=lambda b: -dist_to(b, nex["pos"]))
        towers = [b for b in mine if b["cells"] < 35]
        inhib = [b for b in mine if b["cells"] >= 35]
        assert len(towers) == 3 and len(inhib) == 1, (lane, len(towers), len(inhib))
        structures[lane] = dict(outer=towers[0]["pos"], inner=towers[1]["pos"], base=towers[2]["pos"], inhibitor=inhib[0]["pos"])
    out["structures_saradomin"] = structures

    # lanes: the cheapest centred path between the two inhibitors of a lane, through lane cells
    from skimage.graph import route_through_array
    M = g["M"]
    hard = (V & WALL) > 0
    dist = ndimage.distance_transform_edt(~wall)
    lanes = {}
    opposite = dict(top="bot", mid="mid", bot="top")
    for name, code in (("top", 2), ("mid", 3), ("bot", 4)):
        a_m = structures[name]["inhibitor"]; z_m = structures[opposite[name]]["inhibitor"]
        z_m = [-z_m[0], -z_m[1]]
        allow = ~hard & ((M == code) | (M == 1) | (M == 0))
        cost = np.where(allow, 1.0 / (1.0 + dist) ** 2 + 0.01, 1e6)
        c0, r0 = F.cell(*a_m); c1, r1 = F.cell(*z_m)
        path, _ = route_through_array(cost, (int(round(r0)), int(round(c0))), (int(round(r1)), int(round(c1))), fully_connected=True, geometric=True)
        pts = np.array(path, float)
        simp = measure.approximate_polygon(pts, 2.5)
        lanes[name] = [[round(float(v), 2) for v in F.metres(p[1], p[0])] for p in simp]
        lanes[name][0] = list(a_m); lanes[name][-1] = z_m
    out["lanes"] = lanes
    out["base_centres"] = nexus
    sp = np.array([c for c in np.argwhere(g["M"] == 0) if c[1] + c[0] < (XC + ZC) / 2]).mean(0)
    out["fountain_saradomin"] = [round(float(v), 2) for v in F.metres(sp[1], sp[0])]
    json.dump(out, open(a.out, "w"), separators=(",", ":"))
    print("walls", len(walls), "polygons,", sum(len(w) for w in walls), "points; lanes", {k: len(v) for k, v in lanes.items()})
    print(json.dumps(structures))


if __name__ == "__main__":
    main()

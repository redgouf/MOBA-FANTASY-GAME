"""Dresses the game's own map (the Wilderness Rift) with OSRS ground.

Reads tools/osrs_extract/rift_layout.json (written from MapLayout by
tools/export_rift_layout.gd) and builds rift/rift.glb: an OSRS-style tile
terrain with real Wilderness ground (underlays and ground clutter copied
tile by tile from a stretch of the real Wilderness), dirt lanes, the
Wilderness Ditch as water, a Falador-stone Saradomin base, an obsidian and
lava Zamorak base, the two epic pits, and rocks and dead trees on every
jungle wall and along the edge. Everything is visual: the game keeps its own
colliders and navigation.

The terrain is built in tiles of TILE metres (the same scale as the
champions' models) and positioned so the map's centre is the origin.
"""
import json
import math
import random

from . import mapexport as me
from .model import ModelData

TILE = 1.4                       # metres per OSRS tile (models.json player_scale)
SAMPLE_REGIONS = [(48, 58), (49, 58), (48, 59), (49, 59)]   # open Wilderness, 2x2 squares

# floors (overlay ids are 1-based as stored in the map)
OV_PATH = 32          # textured earth (texture 11): a worn dirt track
OV_WATER = 6          # water, texture 1
OV_COBBLE = 12        # grey cobblestones (texture 46)
OV_OBSIDIAN = 11      # near-black stone
OV_LAVA = 19          # TzHaar lava, texture 31
OV_SCORCHED = 14      # dark burnt earth
UN_DARK = 150         # the darkest Wilderness ground, under the dark floors

ROCKS = [10790, 11182, 10791, 10790, 11182, 10791]   # the grey Wilderness boulders
WILD_UNDERLAYS = {72, 145, 146, 147, 148, 149, 150}
LAVA_ROCKS = [14814, 14815, 14816, 14817]
DEAD_TREES = [1282, 1283, 14514, 14515, 1286, 1289]
SARA_STATUE, ZAM_STATUE = 585, 587


def _dist_seg(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    cx, cz = ax + t * dx, az + t * dz
    return math.hypot(px - cx, pz - cz)


def build_rift(pack, layout_path):
    L = json.load(open(layout_path))
    defs = pack.defs
    half = L["map_size"] / 2.0 + 10.0                    # 10 m of dressed border
    n = int(math.ceil(2 * half / TILE))
    H = n * TILE / 2.0
    rng = random.Random(7)

    # -- sample the real Wilderness: underlays and ground clutter per tile
    sw = 64 * 2
    s_und = [[0] * sw for _ in range(sw)]
    s_dec = {}
    for i, (rx, ry) in enumerate(SAMPLE_REGIONS):
        files = pack.cache.files(me.MAPS, (rx << 8) | ry)
        ox, oy = (i % 2) * 64, (i // 2) * 64
        if 0 in files:
            sc = me.Scene(0, 0, 65)
            me.decode_terrain(sc, files[0], 0, 0)
            for x in range(64):
                for y in range(64):
                    s_und[ox + x][oy + y] = sc.underlays[0][x][y]
        if 1 in files:
            for lid, x, y, level, shape, rot in me.decode_locs(files[1]):
                if level == 0 and shape == 22:
                    s_dec.setdefault((ox + x, oy + y), []).append((lid, rot))

    def center(tx, ty):            # tile -> game metres (x, z)
        return (tx + 0.5) * TILE - H, H - (ty + 0.5) * TILE

    sara = L["saradomin_base"]
    zam = L["zamorak_base"]
    jad, dragon = L["jad_pit"], L["dragon_pit"]
    br, pr = L["base_radius"], L["pit_radius"]
    lanes = list(L["lanes"].values())
    walls = L["walls"]
    clear = [tuple(c) for c in L["keep_clear"]] + [tuple(c) for c in L["camps"]]
    edge = L["map_size"] / 2.0

    def in_wall(x, z, pad=0.0):
        for w in walls:
            (wx, wz), (sx, sz) = w["pos"], w["size"]
            if abs(x - wx) <= sx / 2 + pad and abs(z - wz) <= sz / 2 + pad:
                return True
        return False

    def classify(x, z):
        ds = math.hypot(x - sara[0], z - sara[1])
        dz_ = math.hypot(x - zam[0], z - zam[1])
        if abs(x) > edge or abs(z) > edge:
            return "edge"
        if ds < br:
            return "sara"
        if dz_ < br:
            return "zam"
        if dz_ < br + 2.2:
            return "zam_rim"
        dj = math.hypot(x - jad[0], z - jad[1])
        if dj < pr:
            return "jad"
        if dj < pr + 1.6:
            return "jad_rim"
        if math.hypot(x - dragon[0], z - dragon[1]) < pr:
            return "dragon"
        if abs(x - z) / math.sqrt(2) < L["river_width"] / 2:
            return "water"
        for pts in lanes:
            for a, b in zip(pts, pts[1:]):
                if _dist_seg(x, z, a[0], a[1], b[0], b[1]) < L["lane_width"] / 2:
                    return "lane"
        return "ground"

    OVERLAY = {"lane": OV_PATH, "water": OV_WATER, "sara": OV_COBBLE, "zam": OV_OBSIDIAN,
               "zam_rim": OV_LAVA, "jad": OV_OBSIDIAN, "jad_rim": OV_LAVA, "dragon": OV_SCORCHED}
    DARK = ("zam", "zam_rim", "jad", "jad_rim", "dragon")
    # corner kinds, then each tile takes the OSRS tile shape that follows its
    # corners: full, or a half-tile triangle where an edge cuts it diagonally
    corner = [[classify(tx * TILE - H, H - ty * TILE) for ty in range(n + 1)] for tx in range(n + 1)]
    scene = me.Scene(0, 0, n + 1)
    kind = [[None] * n for _ in range(n)]
    for tx in range(n):
        for ty in range(n):
            x, z = center(tx, ty)
            und = s_und[tx % sw][ty % sw]
            scene.underlays[0][tx][ty] = und if und in WILD_UNDERLAYS else 147
            k = classify(x, z)
            kind[tx][ty] = k
            cs = [corner[tx][ty], corner[tx + 1][ty], corner[tx + 1][ty + 1], corner[tx][ty + 1]]  # sw se ne nw
            # the overlay this tile carries: its centre's, or the one most of its corners have
            cand = k if k in OVERLAY else max((c for c in cs if c in OVERLAY), key=cs.count, default=None)
            if k in DARK:
                scene.underlays[0][tx][ty] = UN_DARK
            if cand is None:
                continue
            inside = [c == cand for c in cs]
            count = sum(inside)
            if count == 4 or (k == cand and count == 2):
                shape, rot = 0, 0
            elif count == 3:
                out = inside.index(False)
                shape, rot = 1, (2 - out) & 3
            else:
                continue
            scene.overlays[0][tx][ty] = OVERLAY[cand]
            scene.shapes[0][tx][ty] = shape
            scene.rotations[0][tx][ty] = rot
    sink = me.Sink()
    blended = me.blend_underlays(scene, 0, defs)
    for tx in range(n):
        for ty in range(n):
            me.add_tile(sink, "terrain_0", scene, defs, pack.textures, 0, tx, ty, blended, 0, 0)

    models = {}

    def put(lid, tx, ty, rot=0, scale=1.0, group="scenery", shape=10):
        loc = defs.loc(lid)
        m = me.loc_model(pack, loc, shape, rot)
        if m is None:
            return
        if scale != 1.0:
            s = int(128 * scale)
            m.scale(s, s, s)
        sx, sy = (loc.size_x, loc.size_y) if rot in (0, 2) else (loc.size_y, loc.size_x)
        m.translate(int((tx + sx * scale / 2.0) * 128), 0, int((ty + sy * scale / 2.0) * 128))
        models.setdefault((0, group), []).append(m)

    # ground clutter from the real Wilderness, on open ground only
    for tx in range(n):
        for ty in range(n):
            if kind[tx][ty] not in ("ground", "edge"):
                continue
            x, z = center(tx, ty)
            if in_wall(x, z) or any(math.hypot(x - c[0], z - c[1]) < 3.0 for c in clear):
                continue
            for lid, rot in s_dec.get((tx % sw, ty % sw), []):
                put(lid, tx, ty, rot, group="clutter", shape=22)

    def tile_of(x, z):
        return int((x + H) / TILE), int((H - z) / TILE)

    # jungle walls: boulders and dead trees filling each wall's footprint
    for w in walls:
        (wx, wz), (sx, sz) = w["pos"], w["size"]
        zam_side = (wx - wz) > 0          # above the ditch: Zamorak's half
        step = 2.6
        nx, nz = max(1, int(sx / step)), max(1, int(sz / step))
        for i in range(nx):
            for j in range(nz):
                x = wx - sx / 2 + (i + 0.5) * sx / nx + rng.uniform(-0.5, 0.5)
                z = wz - sz / 2 + (j + 0.5) * sz / nz + rng.uniform(-0.5, 0.5)
                tx, ty = tile_of(x, z)
                if rng.random() < 0.22:
                    put(rng.choice(DEAD_TREES), tx, ty, rng.randrange(4), 1.4)
                else:
                    pool = LAVA_ROCKS if zam_side else ROCKS
                    put(rng.choice(pool), tx - 1, ty - 1, rng.randrange(4), rng.uniform(1.5, 2.1))
    # the edge of the map: a ring of rocks and trees
    t = -edge
    while t <= edge:
        for x, z in ((t, -edge - 2.5), (t, edge + 2.5), (-edge - 2.5, t), (edge + 2.5, t)):
            tx, ty = tile_of(x, z)
            if rng.random() < 0.3:
                put(rng.choice(DEAD_TREES), tx, ty, rng.randrange(4), 1.5)
            else:
                pool = LAVA_ROCKS if x + (-z) > 120 else ROCKS
                put(rng.choice(pool), tx - 1, ty - 1, rng.randrange(4), rng.uniform(1.6, 2.4))
        t += 3.2
    # a few dead trees in the open jungle, away from lanes, camps and walls
    for _ in range(140):
        x, z = rng.uniform(-edge + 6, edge - 6), rng.uniform(-edge + 6, edge - 6)
        tx, ty = tile_of(x, z)
        if kind[tx][ty] != "ground" or in_wall(x, z, 2.0) or any(math.hypot(x - c[0], z - c[1]) < 7.0 for c in clear):
            continue
        near_lane = any(_dist_seg(x, z, a[0], a[1], b[0], b[1]) < L["lane_width"] / 2 + 3
                        for pts in lanes for a, b in zip(pts, pts[1:]))
        if not near_lane:
            put(rng.choice(DEAD_TREES), tx, ty, rng.randrange(4), 1.3)
    # base statues
    for base, statue in ((sara, SARA_STATUE), (zam, ZAM_STATUE)):
        for k in range(6):
            a = k * math.pi / 3 + math.pi / 6
            x, z = base[0] + math.cos(a) * (br - 1.5), base[1] + math.sin(a) * (br - 1.5)
            if any(math.hypot(x - c[0], z - c[1]) < 4.0 for c in clear):
                continue
            tx, ty = tile_of(x, z)
            put(statue, tx, ty, rng.randrange(4), 1.6)

    g, level_nodes = me.write_scene_nodes(pack, sink, models)
    kids = [g.node("level_%d" % lv, children=nodes) for lv, nodes in sorted(level_nodes.items())]
    root = g.node("rift", children=kids)
    g.add_root(root)
    rel = "rift/rift.glb"
    g.write(pack._path(rel))
    pack.manifest["rift"] = {"file": rel, "tile": TILE, "tiles": n, "origin": [-H, H],
                             "note": "glb units are tiles; scale by tile and place at origin (x, z)"}
    pack.log("rift: %d x %d tiles, %d objects -> %s" % (n, n, sum(len(v) for v in models.values()), rel))

"""Dresses the game's own map (the Wilderness Rift) with OSRS ground.

Reads tools/osrs_extract/rift_layout.json (written from data/map.json by
tools/export_rift_layout.gd) and builds rift/rift.glb: an OSRS-style tile
terrain with real Wilderness ground (underlays and ground clutter copied
tile by tile from a stretch of the real Wilderness), the jungle walls raised
into rock cliffs crowned with boulders and dead trees, green brush, dirt
lanes, the river as lowered water, a Falador-stone Saradomin base, an
obsidian and lava Zamorak base, the two epic pits, and team-coloured mats on
the base gates. Everything is visual: the game keeps its own colliders and
navigation.

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
UN_BRUSH = 20         # grey-green grass, for the brush
UN_GROUND = 8         # the jungle floor: dusty dark grey
UN_ROCK = 26          # rock tops: light grey stone, so walls stand out from the floor
UN_ROCK_ZAM = 14      # ...and warm red-brown on Zamorak's half
CLIFF = -2.4 * 128    # rock walls rise about 3 m (OSRS heights count upward as negative)
RIVER_BED = 16        # the river sits a little lower than the ground

ROCKS = [10790, 11182, 10791, 10790, 11182, 10791]   # the grey Wilderness boulders
WILD_UNDERLAYS = {72, 145, 146, 147, 148, 149, 150}
LAVA_ROCKS = [14814, 14815, 14816, 14817]
DEAD_TREES = [1282, 1283, 14514, 14515, 1286, 1289]
SARA_STATUE, ZAM_STATUE = 585, 587
BRUSH_PLANTS = [1118, 1119, 1120, 2892, 2893, 1399, 1400, 1298, 1299]   # bushes, jungle bushes and ferns


def _dist_seg(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    cx, cz = ax + t * dx, az + t * dz
    return math.hypot(px - cx, pz - cz)


class Grid:
    """One of the map's run-length encoded terrain grids, sampled in metres."""

    def __init__(self, L, name, outside=0):
        g = L["grid"]
        self.cols, self.rows = int(g["cols"]), int(g["rows"])
        self.ox, self.oz = g["origin"]
        self.cell = L["cell_m"]
        self.outside = outside
        self.data = []
        for row in L[name + "_rle"]:
            out = bytearray()
            for v, n in row:
                out.extend(bytes([int(v)]) * int(n))
            self.data.append(out)

    def at(self, x, z):
        col = int(math.floor((x - self.ox) / self.cell))
        row = self.rows - 1 - int(math.floor((z - self.oz) / self.cell))
        if col < 0 or col >= self.cols or row < 0 or row >= self.rows:
            return self.outside
        return self.data[row][col]

    def near(self, x, z, r):
        """Is any cell within r metres set?"""
        for dx, dz in ((r, 0), (-r, 0), (0, r), (0, -r), (r * .7, r * .7), (-r * .7, r * .7), (r * .7, -r * .7), (-r * .7, -r * .7)):
            if self.at(x + dx, z + dz):
                return True
        return self.at(x, z) == 1


def build_rift(pack, layout_path):
    L = json.load(open(layout_path))
    defs = pack.defs
    half = L["map_size"] / 2.0 + 10.0                    # 10 m of dressed border
    n = int(math.ceil(2 * half / TILE))
    H = n * TILE / 2.0
    rng = random.Random(7)
    wall = Grid(L, "wall", outside=1)
    brush = Grid(L, "brush")
    river = Grid(L, "river")
    pit = Grid(L, "pit")
    base = Grid(L, "base")

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

    jad, dragon = L["jad_pit"], L["dragon_pit"]
    lanes = list(L["lanes"].values())
    clear = [tuple(c) for c in L["keep_clear"]] + [tuple(c) for c in L["camps"]]
    gates = L["gates"]
    lane_half = L["lane_width"] * 0.4

    def in_gate(x, z):
        for g in gates:
            if abs(x - g["pos"][0]) <= g["size"][0] / 2 + 0.6 and abs(z - g["pos"][1]) <= g["size"][1] / 2 + 0.6:
                return g["team"]
        return -1

    def classify(x, z):
        if wall.at(x, z):
            return "rock"
        gt = in_gate(x, z)
        if gt >= 0:
            return "gate_sara" if gt == 0 else "gate_zam"
        if pit.at(x, z):
            return "jad" if math.hypot(x - jad[0], z - jad[1]) < math.hypot(x - dragon[0], z - dragon[1]) else "dragon"
        if pit.near(x, z, 1.5) and math.hypot(x - jad[0], z - jad[1]) < L["pit_radius"] + 4:
            return "jad_rim"
        if river.at(x, z):
            return "water"
        if base.at(x, z):
            return "sara" if z - x > 0 else "zam"
        if z - x < 0 and base.near(x, z, 2.2):
            return "zam_rim"
        if brush.at(x, z):
            return "brush"
        for pts in lanes:
            for a, b in zip(pts[1:-1], pts[2:-1]):
                if _dist_seg(x, z, a[0], a[1], b[0], b[1]) < lane_half:
                    return "lane"
        return "ground"

    OVERLAY = {"lane": OV_PATH, "water": OV_WATER, "sara": OV_COBBLE, "zam": OV_OBSIDIAN, "gate_sara": OV_COBBLE,
               "gate_zam": OV_OBSIDIAN, "zam_rim": OV_SCORCHED, "jad": OV_OBSIDIAN, "jad_rim": OV_LAVA, "dragon": OV_SCORCHED}
    DARK = ("zam", "zam_rim", "jad", "jad_rim", "dragon", "gate_zam")
    # corner kinds, then each tile takes the OSRS tile shape that follows its
    # corners: full, or a half-tile triangle where an edge cuts it diagonally
    corner = [[classify(tx * TILE - H, H - ty * TILE) for ty in range(n + 1)] for tx in range(n + 1)]
    scene = me.Scene(0, 0, n + 1)
    kind = [[None] * n for _ in range(n)]
    for tx in range(n):
        for ty in range(n):
            x, z = center(tx, ty)
            und = s_und[tx % sw][ty % sw]
            scene.underlays[0][tx][ty] = UN_GROUND
            k = classify(x, z)
            kind[tx][ty] = k
            cs = [corner[tx][ty], corner[tx + 1][ty], corner[tx + 1][ty + 1], corner[tx][ty + 1]]  # sw se ne nw
            if k == "rock":
                scene.underlays[0][tx][ty] = UN_ROCK_ZAM if x - z > 0 else UN_ROCK
            elif k in DARK:
                scene.underlays[0][tx][ty] = UN_DARK
            elif k == "brush":
                scene.underlays[0][tx][ty] = UN_BRUSH
            # the overlay this tile carries: its centre's, or the one most of its corners have
            cand = k if k in OVERLAY else max((c for c in cs if c in OVERLAY), key=cs.count, default=None)
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
    # heights: the walls rise into cliffs, the river sits a little lower. A
    # corner's height follows how many of the four tiles around it are rock.
    def tile_kind(tx, ty):
        return kind[min(max(tx, 0), n - 1)][min(max(ty, 0), n - 1)]

    heights = scene.heights[0]
    for cx in range(n + 1):
        for cy in range(n + 1):
            around = [tile_kind(cx - 1, cy - 1), tile_kind(cx, cy - 1), tile_kind(cx - 1, cy), tile_kind(cx, cy)]
            rocks = around.count("rock")
            if rocks == 4:
                heights[cx][cy] = int(CLIFF)
            elif rocks:
                heights[cx][cy] = int(CLIFF * (0.25 * rocks) * 0.6)
            elif around.count("water") == 4:
                heights[cx][cy] = RIVER_BED

    def ground_h(tx, ty):
        """Terrain height under a tile (mean of its corners), in OSRS units."""
        return (heights[tx][ty] + heights[tx + 1][ty] + heights[tx][ty + 1] + heights[tx + 1][ty + 1]) // 4

    sink = me.Sink()
    blended = me.blend_underlays(scene, 0, defs)
    for tx in range(n):
        for ty in range(n):
            me.add_tile(sink, "terrain_0", scene, defs, pack.textures, 0, tx, ty, blended, 0, 0)

    models = {}

    def put(lid, tx, ty, rot=0, scale=1.0, group="scenery", shape=10, lift=0):
        loc = defs.loc(lid)
        m = me.loc_model(pack, loc, shape, rot)
        if m is None:
            return
        if scale != 1.0:
            s = int(128 * scale)
            m.scale(s, s, s)
        sx, sy = (loc.size_x, loc.size_y) if rot in (0, 2) else (loc.size_y, loc.size_x)
        m.translate(int((tx + sx * scale / 2.0) * 128), int(lift), int((ty + sy * scale / 2.0) * 128))
        models.setdefault((0, group), []).append(m)

    def tile_of(x, z):
        return int((x + H) / TILE), int((H - z) / TILE)

    # ground clutter from the real Wilderness, on open ground only
    for tx in range(n):
        for ty in range(n):
            if kind[tx][ty] != "ground":
                continue
            x, z = center(tx, ty)
            if any(math.hypot(x - c[0], z - c[1]) < 3.0 for c in clear):
                continue
            for lid, rot in s_dec.get((tx % sw, ty % sw), []):
                put(lid, tx, ty, rot, group="clutter", shape=22)

    # the rock walls: boulders and dead trees along the cliff tops, deep enough
    # in to hide the raised terrain's edge but no further (nobody sees inside)
    def rock_depth(tx, ty):
        for r in range(1, 4):
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    if max(abs(dx), abs(dy)) == r and tile_kind(tx + dx, ty + dy) != "rock":
                        return r
        return 4

    for tx in range(n):
        for ty in range(n):
            if kind[tx][ty] != "rock":
                continue
            d = rock_depth(tx, ty)
            if d > 3:
                continue
            x, z = center(tx, ty)
            zam_side = (x - z) > 0
            roll = rng.random()
            lift = ground_h(tx, ty)
            if d == 1 and roll < 0.7 or d == 2 and roll < 0.4 or d == 3 and roll < 0.15:
                if rng.random() < 0.16:
                    put(rng.choice(DEAD_TREES), tx, ty, rng.randrange(4), 1.4, lift=lift)
                elif zam_side and rng.random() < 0.5:
                    put(rng.choice(LAVA_ROCKS), tx - 1, ty - 1, rng.randrange(4), rng.uniform(0.9, 1.3), lift=lift)
                else:
                    put(rng.choice(ROCKS), tx - 1, ty - 1, rng.randrange(4), rng.uniform(1.2, 1.7), lift=lift)

    # brush: dense green plants, so the grass reads at a glance
    for tx in range(n):
        for ty in range(n):
            if kind[tx][ty] == "brush" and rng.random() < 0.5:
                put(rng.choice(BRUSH_PLANTS), tx, ty, rng.randrange(4), rng.uniform(1.0, 1.5))

    # a few dead trees in the open jungle, away from lanes, camps and walls
    for _ in range(160):
        x, z = rng.uniform(-L["map_size"] / 2 + 6, L["map_size"] / 2 - 6), rng.uniform(-L["map_size"] / 2 + 6, L["map_size"] / 2 - 6)
        tx, ty = tile_of(x, z)
        if kind[tx][ty] not in ("ground", "brush") or wall.near(x, z, 2.5) or any(math.hypot(x - c[0], z - c[1]) < 7.0 for c in clear):
            continue
        put(rng.choice(DEAD_TREES), tx, ty, rng.randrange(4), 1.3)
    # base statues around each fountain
    for fountain, statue in ((L["saradomin_base"], SARA_STATUE), (L["zamorak_base"], ZAM_STATUE)):
        for k in range(12):
            a = k * math.pi / 6
            x, z = fountain[0] + math.cos(a) * 9.0, fountain[1] + math.sin(a) * 9.0
            tx, ty = tile_of(x, z)
            if not (0 <= tx < n and 0 <= ty < n) or kind[tx][ty] not in ("sara", "zam"):
                continue
            if any(math.hypot(x - c[0], z - c[1]) < 4.0 for c in clear):
                continue
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

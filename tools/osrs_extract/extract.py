#!/usr/bin/env python3
"""Exports OSRS characters, items, NPCs, objects, spell graphics, textures
and map regions from the game cache into the private model pack.

  python tools/osrs_extract/extract.py --cache PATH [--out private_assets/osrs] [--only player,npcs,...]

PATH is either a flat cache (a checkout of github.com/abextm/osrs-cache, or
`fetch_cache.py`) or a client cache folder with main_file_cache.dat2 / .idx
files (OpenRS2 download, osrs.world cache folder). Needs Python 3.9+ only.

What it writes is Jagex's material: private use only, never commit it.
"""
import argparse
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from osrsx.cache import Cache          # noqa: E402
from osrsx.pack import Pack            # noqa: E402
from osrsx.weapons import anims_for    # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
STEPS = ["player", "npcs", "objects", "spotanims", "items", "textures", "maps"]
EXTRA_STEPS = ["sprites"]          # only when asked for with --only


def trailing_id(name):
    m = re.search(r"(\d+)$", name or "")
    return int(m.group(1)) if m else None


def models_json_needs():
    """Item ids and animation ids data/models.json refers to."""
    p = os.path.join(REPO, "data", "models.json")
    items, clips = set(), set()
    if not os.path.exists(p):
        return items, clips
    cfg = json.load(open(p))
    for k in ("default_cast_clip", "eat_clip", "death_clip", "pray_clip"):
        clips.add(trailing_id(cfg.get(k)))
    for c in cfg.get("champions", {}).values():
        items.update(int(i) for i in c.get("gear", []))
        items.add(int(c.get("weapon", 0)))
        for f in c.get("forms", {}).values():
            items.add(int(f.get("weapon", 0)))
        for ab in c.get("abilities", {}).values():
            clips.add(trailing_id(ab.get("clip")))
        clips.add(trailing_id(c.get("passive_clip")))
    for s in cfg.get("spec_weapons", {}).values():
        items.add(int(s.get("weapon", 0)))
        clips.add(trailing_id(s.get("clip")))
    for ov in cfg.get("anim_overrides", {}).values():
        for v in ov.values():
            clips.add(trailing_id(v))
    items.discard(0)
    clips.discard(None)
    return items, clips


class Resolver:
    """Turns recipe entries (id, 'gv:name', 'name:Name', 're:regex') into ids."""

    GV_INDEX = {"obj": 0, "npc": 1, "loc": 6, "seq": 7, "spotanim": 8}

    def __init__(self, pack):
        self.pack = pack
        self._gv = {}

    def gv(self, kind):
        if kind not in self._gv:
            files = self.pack.cache.files(24, self.GV_INDEX[kind])
            self._gv[kind] = {i: v.decode("latin1") for i, v in files.items()}
        return self._gv[kind]

    def ids(self, kind, entry):
        if isinstance(entry, int):
            return [entry]
        s = str(entry)
        if s.isdigit():
            return [int(s)]
        if s.startswith("gv:"):
            return [i for i, n in self.gv(kind).items() if n == s[3:]][:1]
        if s.startswith("re:"):
            rx = re.compile(s[3:])
            return sorted(i for i, n in self.gv(kind).items() if rx.search(n))
        if s.startswith("name:"):
            want = s[5:].lower()
            for i in self.pack.defs.ids(kind):
                d = self.pack.defs.get(kind, i)
                if d and d.name and d.name.lower() == want:
                    return [i]
        return []


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=os.path.join(HERE, "cache"), help="flat cache or main_file_cache folder (default: what fetch_cache.py downloads)")
    ap.add_argument("--out", default=os.path.join(REPO, "private_assets", "osrs"))
    ap.add_argument("--recipe", default=os.path.join(HERE, "recipe.json"))
    ap.add_argument("--keys", help="map keys (xteas.json / keys.json) for caches older than rev 237")
    ap.add_argument("--rev", type=int, help="client revision of the cache (default: the cache's REVISION file, else 241)")
    ap.add_argument("--only", help="comma list of steps: " + ",".join(STEPS + EXTRA_STEPS))
    ap.add_argument("--npc", action="append", default=[], help="extra NPC: slug=id")
    ap.add_argument("--object", action="append", default=[], type=str, help="extra object id")
    ap.add_argument("--item", action="append", default=[], type=int, help="extra worn item id")
    ap.add_argument("--region", action="append", default=[], help="extra map region (id or x_y)")
    ap.add_argument("--all-wearables", action="store_true", help="export every worn item in the game (large)")
    args = ap.parse_args()

    steps = set(args.only.split(",")) if args.only else set(STEPS)
    recipe = json.load(open(args.recipe))
    xteas = {}
    if args.keys:
        raw = json.load(open(args.keys))
        if isinstance(raw, list):
            for e in raw:
                xteas[int(e.get("group", e.get("archive", e.get("mapsquare", 0))))] = e.get("key", e.get("keys"))
        else:
            xteas = {int(k): v for k, v in raw.items()}
    if not os.path.isdir(args.cache):
        sys.exit("no cache at %s: run fetch_cache.py first, or pass --cache" % args.cache)
    rev = args.rev
    if rev is None:
        rf = os.path.join(args.cache, "REVISION")
        rev = int(open(rf).read().strip() or 241) if os.path.exists(rf) else 241
    if not xteas and os.path.exists(os.path.join(args.cache, "keys.json")):
        raw = json.load(open(os.path.join(args.cache, "keys.json")))
        if isinstance(raw, list):
            for e in raw:
                xteas[int(e.get("group", e.get("archive", e.get("mapsquare", 0))))] = e.get("key", e.get("keys"))
    os.makedirs(args.out, exist_ok=True)
    t0 = time.time()
    cache = Cache(args.cache, xteas)
    pack = Pack(cache, args.out, rev)
    res = Resolver(pack)

    if "player" in steps:
        items, clips = models_json_needs()
        items.update(recipe.get("player_items", []))
        items.update(args.item)
        clips.update(recipe.get("player_clips", []))
        if args.all_wearables:
            for oid in pack.defs.ids("obj"):
                o = pack.defs.obj(oid)
                if o.wear_pos[0] >= 0 and o.male_models[0] >= 0 and o.note_template == -1:
                    items.add(oid)
        pack.player_base()
        done = 0
        for iid in sorted(items):
            if pack.player_item(iid):
                done += 1
                o = pack.defs.obj(iid)
                if o.wear_pos[0] == 3:      # weapon: stance and attack clips
                    clips.update(pack.set_item_animations(iid, anims_for(iid, o.name)))
        pack.log("worn items: %d" % done)
        pack.player_animations(sorted(c for c in clips if c))
        pack.save_manifest()

    if "npcs" in steps:
        npcs = dict(recipe.get("npcs", {}))
        for e in args.npc:
            k, _, v = e.partition("=")
            npcs[k] = int(v)
        for slug_name, entry in npcs.items():
            roles = None
            if isinstance(entry, dict):
                roles = {k: v for k, v in entry.items() if k != "id"}
                entry = entry["id"]
            for nid in res.ids("npc", entry)[:1]:
                pack.npc(nid, slug_name, roles_override=roles)
        pack.save_manifest()

    if "objects" in steps:
        n = 0
        for entry in recipe.get("objects", []) + args.object:
            for lid in res.ids("loc", entry):
                n += pack.object(lid)
        pack.log("objects: %d" % n)
        pack.save_manifest()

    if "spotanims" in steps:
        n = 0
        for entry in recipe.get("spotanims", []):
            for sid in res.ids("spotanim", entry):
                n += pack.spotanim(sid)
        pack.log("spot anims: %d" % n)
        pack.save_manifest()

    if "items" in steps:
        n = 0
        for entry in recipe.get("inventory_items", []):
            for iid in res.ids("obj", entry):
                n += pack.item_model(iid)
        pack.log("inventory models: %d" % n)

    if "textures" in steps:
        pack.all_textures()

    if "sprites" in steps:
        pack.all_sprites()

    if "maps" in steps:
        from osrsx.mapexport import export_region, parse_region
        regions = recipe.get("regions", []) + args.region
        for r in regions:
            rid = parse_region(r)
            if rid is not None:
                export_region(pack, rid)
        pack.save_manifest()

    pack.log("done in %.0fs -> %s" % (time.time() - t0, args.out))


if __name__ == "__main__":
    main()

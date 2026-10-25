"""Builds the private model pack the game reads (private_assets/osrs).

Layout (the contract OsrsModels / OsrsActor use):
  manifest.json
  player/player_base.glb          the bare body: Skeleton3D + body_<part> meshes
  player/player_animations.glb    every player clip, one AnimationPlayer
  player/items/<id>.glb           one worn item, node gear_<id>, same skeleton
  bosses/<slug>.glb               an NPC with its own skeleton and clips
  objects/<id>.glb                a map object (static, or animated if it has one)
  spotanims/<id>.glb              a spell / spec graphic with its animation
  items/<id>.glb                  an item's inventory (ground) model
  textures/<id>.png               every texture

Never commit or publish what this writes: it's Jagex's material.
"""
import json
import os
import re

from .anim import AnimLoader, LabelRig, seq_frames
from .defs import Defs
from .export import Skeleton, write_skinned, write_static, UNIT
from .model import ModelData, ModelLoader
from .textures import Textures

# Equipment slot -> body part (kit) it replaces.
SLOT_HIDES_PART = {4: 2, 6: 3, 7: 5, 8: 0, 9: 4, 10: 6, 11: 1}
SLOT_NAMES = {0: "head", 1: "cape", 2: "neck", 3: "weapon", 4: "body", 5: "shield", 7: "legs",
              9: "hands", 10: "feet", 12: "ring", 13: "ammo"}
DEFAULT_KITS = [0, 10, 18, 26, 33, 36, 42]     # male: hair, jaw, torso, arms, hands, legs, feet
PART_NAMES = ["hair", "jaw", "torso", "arms", "hands", "legs", "feet"]

# Base player clips the game always wants under these names.
PLAYER_CORE = {"idle": 808, "walk": 819, "run": 824}


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", (s or "").lower()).strip("_") or "unnamed"


class Pack:
    def __init__(self, cache, out_dir, rev=241, log=print):
        self.cache = cache
        self.out = out_dir
        self.defs = Defs(cache, rev)
        self.models = ModelLoader(cache)
        self.anims = AnimLoader(cache)
        self.textures = Textures(cache, rev)
        self.log = log
        self.gv_seq = {i: v.decode("latin1") for i, v in cache.files(24, 7).items()}
        self.gv_npc = {i: v.decode("latin1") for i, v in cache.files(24, 1).items()}
        self.manifest = {"source": "osrs_extract", "revision": rev, "units": "1 tile = 1 metre",
                         "items": {}, "clips": {}, "clip_ids": {}, "bosses": {}, "npcs": {},
                         "objects": {}, "spotanims": {}, "body_parts": PART_NAMES}
        mpath = os.path.join(out_dir, "manifest.json")
        if os.path.exists(mpath):
            try:
                old = json.load(open(mpath))
                if old.get("source") == "osrs_extract":
                    for k in ("items", "clips", "clip_ids", "bosses", "npcs", "objects", "spotanims"):
                        self.manifest[k].update(old.get(k, {}))
                    for k in ("maps", "rift"):      # steps not re-run keep their entries
                        if k in old:
                            self.manifest[k] = old[k]
            except ValueError:
                pass
        self._player_skel = None

    # ------------------------------------------------------------- helpers
    # Loose PNGs are reference copies (the .glb files embed their textures):
    # a .gdignore keeps Godot from importing thousands of them.
    GDIGNORE = ("textures", "sprites")

    def _path(self, *parts):
        p = os.path.join(self.out, *parts)
        d = os.path.dirname(p)
        if not os.path.isdir(d):
            os.makedirs(d, exist_ok=True)
            if parts[0] in self.GDIGNORE and len(parts) == 2:
                open(os.path.join(d, ".gdignore"), "w").close()
        return p

    def seq_name(self, seq_id):
        n = self.gv_seq.get(seq_id) or "seq"
        return "%s_%d" % (slug(n), seq_id)

    def _merged(self, model_ids, recolor=None, retexture=None):
        ms = [self.models.get(i) for i in model_ids if i is not None and i >= 0]
        ms = [m for m in ms if m is not None]
        if not ms:
            return None
        m = ModelData.merge(ms) if len(ms) > 1 else ms[0]
        if recolor:
            m.recolor(*recolor)
        if retexture:
            m.retexture(*retexture)
        return m

    def _clip(self, rig, seq_id, loop):
        s = self.defs.seq(seq_id)
        if s is None or s.skeletal or not s.frame_ids:
            return None
        return seq_frames(s, self.anims)

    def save_manifest(self):
        with open(self._path("manifest.json"), "w") as f:
            json.dump(self.manifest, f, indent=1, sort_keys=True)

    # ------------------------------------------------------------- player
    def player_skeleton(self):
        """One fixed skeleton for the body and every worn item: every label
        any worn model uses, rest position = average over the default body
        kits (or over all worn items for labels the body doesn't have)."""
        if self._player_skel is not None:
            return self._player_skel
        body = [self.models.get(m) for k in DEFAULT_KITS for m in self.defs.idk(k).models]
        sums, counts = {}, {}

        def add(m, only_new):
            if m is None or m.vskins is None:
                return
            for x, y, z, l in zip(m.vx, m.vy, m.vz, m.vskins):
                if l < 0 or (only_new and l in body_labels):
                    continue
                s = sums.setdefault(l, [0.0, 0.0, 0.0])
                s[0] += x
                s[1] += y
                s[2] += z
                counts[l] = counts.get(l, 0) + 1
        body_labels = set()
        for m in body:
            add(m, False)
        body_labels = set(counts)
        for oid in self.defs.ids("obj"):
            o = self.defs.obj(oid)
            if o.wear_pos[0] < 0 or o.note_template != -1:
                continue
            for mid in o.male_models:
                if mid >= 0:
                    add(self.models.get(mid), True)
        cents = {l: (s[0] / counts[l], s[1] / counts[l], s[2] / counts[l]) for l, s in sums.items()}
        self._player_skel = (Skeleton(cents.keys(), cents), counts)
        return self._player_skel

    def _player_rig(self):
        skel, counts = self.player_skeleton()
        body = self._merged([m for k in DEFAULT_KITS for m in self.defs.idk(k).models])
        rig = LabelRig(body)
        for l, c in skel.centroids.items():
            if l not in rig.counts:
                rig.sums[l] = [c[0], c[1], c[2]]
                rig.counts[l] = 1
        return rig

    def player_base(self):
        skel, _ = self.player_skeleton()
        meshes = []
        for part, k in enumerate(DEFAULT_KITS):
            kit = self.defs.idk(k)
            m = self._merged(kit.models, (kit.recolor_from, kit.recolor_to), (kit.retexture_from, kit.retexture_to))
            if m:
                meshes.append(("body_%d" % part, m))
        # One rest clip so the base gets an AnimationPlayer for the shared clip library.
        idle = seq_frames(self.defs.seq(PLAYER_CORE["idle"]), self.anims)
        write_skinned(self._path("player", "player_base.glb"), meshes, skel,
                      [("rest", self._player_rig(), idle[:1], True)], self.textures)
        self.log("player base: %d body parts, %d bones" % (len(meshes), len(skel.labels)))

    def player_item(self, item_id):
        o = self.defs.obj(item_id)
        if o is None or o.male_models[0] < 0:
            self.log("item %d: not wearable, skipped" % item_id)
            return False
        m = self._merged(o.male_models, (o.recolor_from, o.recolor_to), (o.retexture_from, o.retexture_to))
        if m is None:
            return False
        if o.male_offset:
            m.translate(0, o.male_offset, 0)
        skel, _ = self.player_skeleton()
        rel = "player/items/%d.glb" % item_id
        write_skinned(self._path(rel), [("gear_%d" % item_id, m)], skel, [], self.textures)
        hides = sorted({SLOT_HIDES_PART[s] for s in o.wear_pos if s in SLOT_HIDES_PART})
        self.manifest["items"][str(item_id)] = {
            "name": o.name, "file": rel, "node": "gear_%d" % item_id,
            "slot": SLOT_NAMES.get(o.wear_pos[0], str(o.wear_pos[0])),
            "hides_body_parts": hides, "animations": self.manifest["items"].get(str(item_id), {}).get("animations", {}),
        }
        return True

    def set_item_animations(self, item_id, anims):
        """anims: role -> seq id (stand/walk/run/stab/slash/crush/block/special)."""
        e = self.manifest["items"].setdefault(str(item_id), {})
        e["animations"] = {role: self.seq_name(s) for role, s in anims.items() if s and s > 0}
        return list(anims.values())

    def player_animations(self, seq_ids):
        skel, _ = self.player_skeleton()
        rig = self._player_rig()
        clips = []
        seen = set()
        names = dict((v, k) for k, v in PLAYER_CORE.items())
        for sid in list(PLAYER_CORE.values()) + list(seq_ids):
            if sid in seen or sid is None or sid < 0:
                continue
            seen.add(sid)
            s = self.defs.seq(sid)
            if s is None:
                continue
            if s.skeletal:
                self.log("  seq %d (%s) is a skeletal animation: not supported yet, skipped" % (sid, self.gv_seq.get(sid)))
                continue
            frames = seq_frames(s, self.anims)
            loop = sid in PLAYER_CORE.values() or s.looping or s.frame_step > 0
            for nm in [self.seq_name(sid)] + ([names[sid]] if sid in names else []):
                clips.append((nm, rig, frames, loop))
                self.manifest["clips"][nm] = {"loop": loop, "seq": sid}
            self.manifest["clip_ids"][str(sid)] = self.seq_name(sid)
        write_skinned(self._path("player", "player_animations.glb"),
                      [], skel, clips, self.textures)
        self.log("player animations: %d clips" % len(clips))

    # ------------------------------------------------------------- npcs
    def npc_seqs(self, npc, model):
        """Every classic sequence that animates this NPC's skeleton (same
        framemap as its idle), named by the game's own names."""
        out = {}
        base_id = None
        for sid in (npc.idle_seq, npc.walk_seq):
            s = self.defs.seq(sid) if sid > 0 else None
            if s and not s.skeletal and s.frame_ids:
                fr = self.anims.frame(s.frame_ids[0])
                if fr:
                    base_id = fr.base.id
                    break
        if base_id is None:
            return out
        for sid in self._seqs_by_base().get(base_id, []):
            out[sid] = self.gv_seq.get(sid, "")
        return out

    _base_index = None

    def _seqs_by_base(self):
        if Pack._base_index is None:
            idx = {}
            for sid in self.defs.ids("seq"):
                s = self.defs.seq(sid)
                if not s or s.skeletal or not s.frame_ids:
                    continue
                group = s.frame_ids[0] >> 16
                files = self.cache.files(0, group)
                data = files.get(s.frame_ids[0] & 0xFFFF)
                if not data or len(data) < 2:
                    continue
                base = (data[0] << 8) | data[1]
                idx.setdefault(base, []).append(sid)
            Pack._base_index = idx
        return Pack._base_index

    @staticmethod
    def _role(name):
        n = name.lower()
        for role, pat in (("death", r"death|_die|dying|_dead"), ("attack_magic", r"magic|cast"),
                          ("attack_ranged", r"range|ranged|shoot|throw|fire"),
                          ("attack", r"attack|slash|stab|crush|bite|claw|hit|swipe|punch|smash"),
                          ("block", r"defend|block|def\b|hurt|flinch"), ("run", r"run"),
                          ("walk", r"walk"), ("idle", r"ready|idle|stand")):
            if re.search(pat, n):
                return role
        return None

    GENERIC_TOKENS = {"barrows", "barrow", "update", "npc", "human", "the", "of", "lesser", "superior", "greater",
                      "arceuus", "normal", "champion", "pest", "quest", "osrs", "new", "old", "big", "small"}
    HUMAN_ROLES = {"attack": 422, "block": 424, "death": 836}

    def npc(self, npc_id, slug_name=None, max_clips=40, roles_override=None):
        n = self.defs.npc(npc_id)
        if n is None or not n.models:
            self.log("npc %d: none" % npc_id)
            return None
        m = self._merged(n.models, (n.recolor_from, n.recolor_to), (n.retexture_from, n.retexture_to))
        if m is None:
            return None
        if n.width_scale != 128 or n.height_scale != 128:
            m.scale(n.width_scale, n.height_scale, n.width_scale)
        name = slug_name or slug(self.gv_npc.get(npc_id) or n.name)
        skel = Skeleton.from_models([m])
        rig = LabelRig(m)
        seqs = self.npc_seqs(n, m)
        humanoid = len(seqs) > 120     # shares the player skeleton with thousands of animations
        words = set(re.split(r"[^a-z]+", (self.gv_npc.get(npc_id, "") + " " + (n.name or "")).lower()))
        words = {w for w in words if len(w) >= 4 and w not in self.GENERIC_TOKENS}

        def matches(g):
            return bool(words & set(re.split(r"[^a-z]+", g)))
        if humanoid:
            seqs = {sid: g for sid, g in seqs.items() if matches(g)}
        roles = {"idle": n.idle_seq, "walk": n.walk_seq}
        if n.run_seq > 0:
            roles["run"] = n.run_seq
        # Name-matched animations first, shortest (most generic) name first.
        for sid, gname in sorted(seqs.items(), key=lambda kv: (not matches(kv[1]), len(kv[1]), kv[0])):
            r = self._role(gname)
            if r in ("attack_magic", "attack_ranged") and not matches(gname):
                continue
            if r and r not in roles:
                roles[r] = sid
        # Clip list: name-matched ones first.
        seqs = dict(sorted(seqs.items(), key=lambda kv: (not matches(kv[1]), kv[0])))
        if humanoid:
            for r, sid in self.HUMAN_ROLES.items():
                roles.setdefault(r, sid)
        for r, sid in (roles_override or {}).items():
            roles[r] = sid
        clips = []
        used = set()
        for role, sid in roles.items():
            fr = self._clip(rig, sid, True) if sid and sid > 0 else None
            if fr:
                clips.append((role, rig, fr, role in ("idle", "walk", "run")))
                used.add(sid)
        for sid, gname in list(seqs.items())[:max_clips]:
            fr = self._clip(rig, sid, False)
            if fr:
                clips.append((self.seq_name(sid), rig, fr, False))
        rel = "bosses/%s.glb" % name
        write_skinned(self._path(rel), [("body", m)], skel, clips, self.textures)
        lo, hi = m.bounds()
        size = [(hi[0] - lo[0]) * UNIT, (hi[1] - lo[1]) * UNIT, (hi[2] - lo[2]) * UNIT]
        self.manifest["bosses"][name] = {"size": [round(v, 3) for v in size], "npc": npc_id, "name": n.name,
                                         "tiles": n.size, "clips": [c[0] for c in clips]}
        self.manifest["npcs"][str(npc_id)] = name
        self.log("npc %d %s -> %s (%d clips)" % (npc_id, n.name, rel, len(clips)))
        return name

    # ------------------------------------------------------------- objects
    def loc_model(self, loc, shape=10, rotation=0):
        """A loc's model for a placement shape (10 = centrepiece)."""
        if not loc or not loc.models:
            return None
        ids = None
        if loc.types is None:
            if shape != 10:
                return None
            ids = loc.models[0]
        else:
            for t, ms in zip(loc.types, loc.models):
                if t == shape:
                    ids = ms
                    break
            if ids is None and shape in (10, 11):
                for t, ms in zip(loc.types, loc.models):
                    if t in (10, 11):
                        ids = ms
            if ids is None:
                return None
        ms = []
        for mid in ids:
            mm = self.models.get(mid)
            if mm is None:
                continue
            if loc.rotated ^ (rotation > 3):
                mm.mirror()
            ms.append(mm)
        if not ms:
            return None
        m = ModelData.merge(ms) if len(ms) > 1 else ms[0]
        m.recolor(loc.recolor_from, loc.recolor_to)
        m.retexture(loc.retexture_from, loc.retexture_to)
        if loc.model_size != [128, 128, 128]:
            m.scale(loc.model_size[0], loc.model_size[1], loc.model_size[2])
        m.rotate(rotation & 3)
        if loc.offset != [0, 0, 0]:
            m.translate(loc.offset[0], -loc.offset[1], loc.offset[2])
        return m

    def object(self, loc_id):
        from .mapexport import loc_model
        loc = self.defs.loc(loc_id)
        m = None
        for shape in (10, 22, 4, 0, 2, 9, 1, 3, 12, 17):
            m = loc_model(self, loc, shape, 0)
            if m is not None:
                break
        if m is None:
            self.log("object %d: no model" % loc_id)
            return False
        rel = "objects/%d.glb" % loc_id
        if loc.seq > 0 and m.vskins is not None:
            rig = LabelRig(m)
            fr = self._clip(rig, loc.seq, True)
            write_skinned(self._path(rel), [("body", m)], Skeleton.from_models([m]),
                          [("idle", rig, fr, True)] if fr else [], self.textures)
        else:
            write_static(self._path(rel), [("body", m)], self.textures)
        self.manifest["objects"][str(loc_id)] = {"name": loc.name, "file": rel,
                                                "size": [loc.size_x, loc.size_y]}
        return True

    # ------------------------------------------------------------- spotanims
    def spotanim(self, sa_id):
        sa = self.defs.spotanim(sa_id)
        if sa is None or sa.model < 0:
            return False
        m = self.models.get(sa.model)
        if m is None:
            return False
        m.recolor(sa.recolor_from, sa.recolor_to)
        m.retexture(sa.retexture_from, sa.retexture_to)
        if sa.width_scale != 128 or sa.height_scale != 128:
            m.scale(sa.width_scale, sa.height_scale, sa.width_scale)
        rel = "spotanims/%d.glb" % sa_id
        clips = []
        if sa.seq > 0 and m.vskins is not None:
            rig = LabelRig(m)
            fr = self._clip(rig, sa.seq, False)
            if fr:
                clips.append(("play", rig, fr, False))
        if clips:
            write_skinned(self._path(rel), [("body", m)], Skeleton.from_models([m]), clips, self.textures)
        else:
            write_static(self._path(rel), [("body", m)], self.textures)
        self.manifest["spotanims"][str(sa_id)] = {"file": rel, "seq": sa.seq,
                                                  "name": self.cache.files(24, 8).get(sa_id, b"").decode("latin1")}
        return True

    # ------------------------------------------------------------- inventory models
    def item_model(self, item_id):
        o = self.defs.obj(item_id)
        if o is None or not o.model:
            return False
        m = self._merged([o.model], (o.recolor_from, o.recolor_to), (o.retexture_from, o.retexture_to))
        if m is None:
            return False
        if o.resize != [128, 128, 128]:
            m.scale(*o.resize)
        write_static(self._path("items", "%d.glb" % item_id), [("item_%d" % item_id, m)], self.textures)
        return True

    # ------------------------------------------------------------- textures
    def all_textures(self):
        n = 0
        for tid in self.textures.defs:
            png = self.textures.png(tid)
            if png:
                with open(self._path("textures", "%d.png" % tid), "wb") as f:
                    f.write(png)
                n += 1
        self.log("textures: %d" % n)

    # ------------------------------------------------------------- sprites
    def all_sprites(self):
        """Every UI sprite (icons, interface pieces, map icons) as PNG, named by
        the game's internal sprite name when it has one."""
        from .textures import SPRITES, decode_sprites, png_bytes
        names = {}
        for i, v in self.cache.files(24, 13).items() if self.cache.has(24, 13) else []:
            names[i] = v.decode("latin1")
        n = 0
        for sid in self.cache.archive_ids(SPRITES):
            data = self.cache.file(SPRITES, sid, 0)
            if not data:
                continue
            try:
                frames = decode_sprites(data)
            except Exception:
                continue
            for k, sp in enumerate(frames):
                if sp.width == 0 or sp.height == 0:
                    continue
                label = slug(names.get(sid, "")) if sid in names else ""
                fname = "%d%s%s.png" % (sid, "_%d" % k if len(frames) > 1 else "", "_" + label if label else "")
                with open(self._path("sprites", fname), "wb") as f:
                    f.write(png_bytes(sp.width, sp.height, sp.full_rgba()))
                n += 1
        self.log("sprites: %d" % n)

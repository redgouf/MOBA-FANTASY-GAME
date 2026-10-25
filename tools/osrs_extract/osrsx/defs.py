"""Config decoders for Old School RuneScape (current revisions).

Ported from rs-map-viewer (github.com/dennisdev/rs-map-viewer, BSD-2-Clause)
and osrscachereader (github.com/Dezinater/osrscachereader, BSD-2-Clause),
OSRS paths only. `rev` is the client revision (241 = 20 Oct 2026).
"""
from .buffer import Buffer

CONFIGS = 2
ARCH_UNDERLAY, ARCH_IDK, ARCH_OVERLAY, ARCH_LOC = 1, 3, 4, 6
ARCH_NPC, ARCH_OBJ, ARCH_SEQ, ARCH_SPOTANIM = 9, 10, 12, 13


class DecodeError(Exception):
    pass


def _params(b: Buffer, out: dict) -> None:
    for _ in range(b.u8()):
        t = b.u8()
        key = b.u24()
        if t == 0:
            out[key] = b.s32()
        elif t == 1:
            out[key] = b.string()
        elif t == 2:
            out[key] = (b.s32() << 32) | b.u32()
        else:
            raise DecodeError("param type %d" % t)


def _recolor(b: Buffer):
    n = b.u8()
    f, t = [], []
    for _ in range(n):
        f.append(b.u16())
        t.append(b.u16())
    return f, t


def _u16m1(b: Buffer) -> int:
    v = b.u16()
    return -1 if v == 0xFFFF else v


class Def:
    def __init__(self, id_):
        self.id = id_
        self.name = None
        self.recolor_from = []
        self.recolor_to = []
        self.retexture_from = []
        self.retexture_to = []
        self.params = {}

    def decode(self, data: bytes, rev: int):
        b = Buffer(data)
        while b.remaining > 0:
            op = b.u8()
            if op == 0:
                break
            self.op(op, b, rev)
        self.post()
        return self

    def op(self, op, b, rev):
        raise NotImplementedError

    def post(self):
        pass


class NpcDef(Def):
    def __init__(self, id_):
        super().__init__(id_)
        self.models = []
        self.chathead_models = []
        self.size = 1
        self.idle_seq = self.walk_seq = self.run_seq = -1
        self.turn_left_seq = self.turn_right_seq = -1
        self.walk_back_seq = self.walk_left_seq = self.walk_right_seq = -1
        self.combat_level = -1
        self.width_scale = self.height_scale = 128
        self.ambient = self.contrast = 0
        self.actions = [None] * 5
        self.transforms = None
        self.transform_varbit = self.transform_varp = -1
        self.category = -1

    def op(self, op, b, rev):
        if op == 1:
            self.models = [b.u16() for _ in range(b.u8())]
        elif op == 2:
            self.name = b.string()
        elif op == 3:
            b.string()
        elif op == 12:
            self.size = b.u8()
        elif op == 13:
            self.idle_seq = b.u16()
        elif op == 14:
            self.walk_seq = b.u16()
        elif op == 15:
            self.turn_left_seq = b.u16()
        elif op == 16:
            self.turn_right_seq = b.u16()
        elif op == 17:
            self.walk_seq, self.walk_back_seq, self.walk_left_seq, self.walk_right_seq = (b.u16() for _ in range(4))
        elif op == 18:
            self.category = b.u16()
        elif 30 <= op < 35:
            s = b.string()
            self.actions[op - 30] = None if s.lower() == "hidden" else s
        elif op == 40:
            self.recolor_from, self.recolor_to = _recolor(b)
        elif op == 41:
            self.retexture_from, self.retexture_to = _recolor(b)
        elif op in (42, 44, 45):
            if op == 42:
                b.u8()
            else:
                b.u16()
        elif op == 60:
            self.chathead_models = [b.u16() for _ in range(b.u8())]
        elif op == 61:
            self.models = [b.s32() for _ in range(b.u8())]
        elif op == 62:
            self.chathead_models = [b.s32() for _ in range(b.u8())]
        elif 74 <= op <= 79:
            b.u16()
        elif op == 93:
            pass
        elif op == 95:
            self.combat_level = b.u16()
        elif op == 97:
            self.width_scale = b.u16()
        elif op == 98:
            self.height_scale = b.u16()
        elif op == 99:
            pass
        elif op == 100:
            self.ambient = b.s8()
        elif op == 101:
            self.contrast = b.s8() * 5
        elif op == 102:
            if rev < 210:
                b.u16()
            else:
                flag = b.u8()
                n = 0
                f = flag
                while f:
                    n += 1
                    f >>= 1
                for i in range(n):
                    if flag & (1 << i):
                        b.big_smart()
                        b.usmart_min1()
        elif op == 103:
            b.u16()
        elif op in (106, 118):
            self.transform_varbit = _u16m1(b)
            self.transform_varp = _u16m1(b)
            last = _u16m1(b) if op == 118 else -1
            n = b.u8()
            self.transforms = [_u16m1(b) for _ in range(n + 1)] + [last]
        elif op in (107, 109, 111, 122, 123, 129, 130, 145, 147, 158, 159, 161, 162):
            pass
        elif op == 114:
            self.run_seq = b.u16()
        elif op == 115:
            self.run_seq = b.u16()
            b.skip(6)
        elif op == 116:
            b.u16()
        elif op == 117:
            b.skip(8)
        elif op == 119:
            b.s8()
        elif op == 121:
            for _ in range(b.u8()):
                b.skip(4)
        elif op in (124, 126, 146):
            b.u16()
        elif op == 125:
            b.s8()
        elif op == 127:
            b.u16()
        elif op == 128:
            b.u8()
        elif op == 134:
            b.skip(9)
        elif op in (135, 136):
            b.skip(3)
        elif op in (137, 138, 139, 142, 144):
            b.u16()
        elif op in (140, 163, 165, 168):
            b.u8()
        elif op in (141, 143):
            pass
        elif op == 148:
            b.skip(4)
        elif op == 149:
            b.u8()
        elif op == 150:
            b.skip(6)
        elif op == 151:
            b.u8()
        elif op == 152:
            b.skip(6)
            b.skip(2 * b.u8())
        elif op == 155:
            b.skip(4)
        elif op == 160:
            b.skip(2 * b.u8())
        elif op == 164:
            b.skip(4)
        elif 170 <= op < 176:
            b.u16()
        elif op == 249:
            _params(b, self.params)
        elif op == 251:
            b.skip(2)
            b.string()
        elif op in (252, 253):
            b.skip(1 + 2 + 2 + (2 if op == 253 else 0) + 8)
            if b.u8():
                b.pos -= 1
                b.string()
        else:
            raise DecodeError("npc %d: opcode %d" % (self.id, op))


class ObjDef(Def):
    """An item."""

    def __init__(self, id_):
        super().__init__(id_)
        self.model = 0
        self.male_models = [-1, -1, -1]
        self.female_models = [-1, -1, -1]
        self.male_offset = self.female_offset = 0
        self.wear_pos = [-1, -1, -1]
        self.zoom2d = 2000
        self.xan2d = self.yan2d = self.zan2d = 0
        self.resize = [128, 128, 128]
        self.ambient = self.contrast = 0
        self.note_template = -1
        self.stackable = False
        self.members = False

    def op(self, op, b, rev):
        if op == 1:
            self.model = b.u16()
        elif op == 2:
            self.name = b.string()
        elif op == 3:
            b.string()
        elif op == 4:
            self.zoom2d = b.u16()
        elif op == 5:
            self.xan2d = b.u16()
        elif op == 6:
            self.yan2d = b.u16()
        elif op in (7, 8):
            b.u16()
        elif op == 9:
            b.string()
        elif op == 10:
            b.u16()
        elif op == 11:
            self.stackable = True
        elif op == 12:
            b.s32()
        elif op == 13:
            self.wear_pos[0] = b.u8()
        elif op == 14:
            self.wear_pos[1] = b.u8()
        elif op == 15:
            pass
        elif op == 16:
            self.members = True
        elif op == 23:
            self.male_models[0] = b.u16()
            self.male_offset = b.u8() if rev < 503 else 0
        elif op == 24:
            self.male_models[1] = b.u16()
        elif op == 25:
            self.female_models[0] = b.u16()
            self.female_offset = b.u8() if rev < 503 else 0
        elif op == 26:
            self.female_models[1] = b.u16()
        elif op == 27:
            self.wear_pos[2] = b.u8()
        elif 30 <= op < 40:
            b.string()
        elif op == 40:
            self.recolor_from, self.recolor_to = _recolor(b)
        elif op == 41:
            self.retexture_from, self.retexture_to = _recolor(b)
        elif op == 42:
            b.s8()
        elif op == 43:
            # sub-op text (rev 210+)
            b.u8()
            while True:
                i = b.u8() - 1
                if i < 0:
                    break
                b.string()
        elif op == 44:
            if rev >= 237:
                self.model = b.s32()
            else:
                b.u16()
        elif op == 45:
            if rev >= 237:
                self.male_models[0] = b.s32()
                self.male_offset = b.u8()
            else:
                b.u16()
        elif op == 46:
            self.male_models[1] = b.s32()
        elif op == 47:
            self.male_models[2] = b.s32()
        elif op == 48:
            self.female_models[0] = b.s32()
            self.female_offset = b.u8()
        elif op == 49:
            self.female_models[1] = b.s32()
        elif op == 50:
            self.female_models[2] = b.s32()
        elif 51 <= op <= 54:
            b.s32()
        elif op == 65:
            pass
        elif op == 75:
            b.s16()
        elif op == 78:
            self.male_models[2] = b.u16()
        elif op == 79:
            self.female_models[2] = b.u16()
        elif 90 <= op <= 93:
            b.u16()
        elif op == 94:
            b.u16()
        elif op == 95:
            self.zan2d = b.u16()
        elif op == 96:
            b.u8()
        elif op == 97:
            b.u16()
        elif op == 98:
            self.note_template = b.u16()
        elif 100 <= op < 110:
            b.skip(4)
        elif op in (110, 111, 112):
            self.resize[op - 110] = b.u16()
        elif op == 113:
            self.ambient = b.s8()
        elif op == 114:
            self.contrast = b.s8() * 5
        elif op == 115:
            b.u8()
        elif op in (121, 122):
            b.u16()
        elif op in (125, 126):
            b.skip(3)
        elif 127 <= op <= 130:
            b.skip(3)
        elif op == 132:
            b.skip(2 * b.u8())
        elif op in (139, 140, 148, 149):
            b.u16()
        elif 142 <= op < 147 or 150 <= op < 155:
            b.u16()
        elif op == 99:
            b.u16()
        elif op in (160, 251):
            pass
        elif op == 161:
            b.skip(2 * b.u16())
        elif op == 200:
            b.skip(2)
            b.string()
        elif op in (201, 202):
            b.skip(1 + 2 + 2 + (2 if op == 202 else 0) + 8)
            if b.u8():
                b.pos -= 1
                b.string()
        elif op == 249:
            _params(b, self.params)
        else:
            raise DecodeError("obj %d: opcode %d" % (self.id, op))


class LocDef(Def):
    """A map object (scenery)."""

    def __init__(self, id_):
        super().__init__(id_)
        self.models = None      # [[model ids]]
        self.types = None       # loc shape per model list (None = any)
        self.size_x = self.size_y = 1
        self.clip_type = 2
        self.blocks_projectile = True
        self.interactive = -1
        self.contoured_ground = -1
        self.contour_type = 0
        self.contour_param = -1
        self.merge_normals = False
        self.model_clipped = False
        self.seq = -1
        self.decor_displacement = 16
        self.ambient = self.contrast = 0
        self.actions = [None] * 5
        self.map_function = -1
        self.map_scene = -1
        self.rotated = False
        self.clipped = True
        self.model_size = [128, 128, 128]   # x, height, y
        self.offset = [0, 0, 0]             # x, height, y
        self.obstructs_ground = False
        self.hollow = False
        self.support_items = -1
        self.transforms = None
        self.transform_varbit = self.transform_varp = -1

    def op(self, op, b, rev):
        if op == 1:
            n = b.u8()
            if n:
                self.models, self.types = [], []
                for _ in range(n):
                    self.models.append([b.u16()])
                    self.types.append(b.u8())
        elif op == 2:
            self.name = b.string()
        elif op == 3:
            b.string()
        elif op == 5:
            n = b.u8()
            if n:
                self.types = None
                self.models = [[b.u16() for _ in range(n)]]
        elif op == 6:
            n = b.u8()
            if n:
                self.models, self.types = [], []
                for _ in range(n):
                    self.models.append([b.s32()])
                    self.types.append(b.u8())
        elif op == 7:
            n = b.u8()
            if n:
                self.types = None
                self.models = [[b.s32() for _ in range(n)]]
        elif op == 14:
            self.size_x = b.u8()
        elif op == 15:
            self.size_y = b.u8()
        elif op == 17:
            self.clip_type = 0
            self.blocks_projectile = False
        elif op == 18:
            self.blocks_projectile = False
        elif op == 19:
            self.interactive = b.u8()
        elif op == 21:
            self.contoured_ground = 0
            self.contour_type = 1
        elif op == 22:
            self.merge_normals = True
        elif op == 23:
            self.model_clipped = True
        elif op == 24:
            self.seq = _u16m1(b)
        elif op == 25:
            pass
        elif op == 27:
            self.clip_type = 1
        elif op == 28:
            self.decor_displacement = b.u8()
        elif op == 29:
            self.ambient = b.s8()
        elif op == 39:
            self.contrast = b.s8() * 25
        elif 30 <= op < 39:
            s = b.string()
            self.actions[op - 30] = None if s.lower() == "hidden" else s
        elif op == 40:
            self.recolor_from, self.recolor_to = _recolor(b)
        elif op == 41:
            self.retexture_from, self.retexture_to = _recolor(b)
        elif op in (44, 45, 60, 61):
            v = b.u16()
            if op == 60:
                self.map_function = v
        elif op == 62:
            self.rotated = True
        elif op == 64:
            self.clipped = False
        elif op == 65:
            self.model_size[0] = b.u16()
        elif op == 66:
            self.model_size[1] = b.u16()
        elif op == 67:
            self.model_size[2] = b.u16()
        elif op == 68:
            self.map_scene = b.u16()
        elif op == 69:
            b.u8()
        elif op == 70:
            self.offset[0] = b.s16()
        elif op == 71:
            self.offset[1] = b.s16()
        elif op == 72:
            self.offset[2] = b.s16()
        elif op == 73:
            self.obstructs_ground = True
        elif op == 74:
            self.hollow = True
        elif op == 75:
            self.support_items = b.u8()
        elif op in (77, 92):
            self.transform_varbit = _u16m1(b)
            self.transform_varp = _u16m1(b)
            last = _u16m1(b) if op == 92 else -1
            n = b.u8()
            self.transforms = [_u16m1(b) for _ in range(n + 1)] + [last]
        elif op == 78:
            b.u16()
            b.u8()
            if rev >= 220:
                b.u8()
        elif op == 79:
            b.skip(4)
            b.u8()
            if rev >= 220:
                b.u8()
            b.skip(2 * b.u8())
        elif op == 81:
            self.contoured_ground = b.u8() * 256
            self.contour_type = 2
            self.contour_param = self.contoured_ground
        elif op == 82:
            self.map_function = b.u16()
        elif op in (88, 89, 90, 94, 97, 98, 103, 105, 168, 169, 177, 189, 190, 191):
            pass
        elif op in (91, 95, 96, 104, 178):
            b.u8()
        elif op == 93:
            b.skip(6)
        elif op == 99:
            b.skip(3)
        elif op == 100:
            b.skip(2)
            b.string()
        elif op in (101, 102):
            b.skip(1 + 2 + 2 + (2 if op == 102 else 0) + 8)
            if b.u8():
                b.pos -= 1
                b.string()
        elif op == 106:
            for _ in range(b.u8()):
                b.u16()
                b.u8()
        elif op == 107:
            self.map_function = b.u16()
        elif 150 <= op < 155:
            b.string()
        elif op == 160:
            b.skip(2 * b.u8())
        elif op == 163:
            b.skip(4)
        elif op == 167:
            b.u16()
        elif op in (170, 171):
            b.usmart()
        elif op == 173:
            b.skip(4)
        elif op == 249:
            _params(b, self.params)
        else:
            raise DecodeError("loc %d: opcode %d" % (self.id, op))

    def post(self):
        if self.interactive == -1:
            self.interactive = 1 if (self.models and (not self.types or self.types[0] == 10)) or any(self.actions) else 0
        if self.support_items == -1:
            self.support_items = 1 if self.clip_type != 0 else 0


class SeqDef(Def):
    """An animation sequence."""

    def __init__(self, id_):
        super().__init__(id_)
        self.frame_ids = []
        self.frame_lengths = []
        self.frame_step = -1
        self.masks = None
        self.stretches = False
        self.forced_priority = 5
        self.left_hand_item = -1
        self.right_hand_item = -1
        self.max_loops = 99
        self.looping = False
        self.skeletal_id = -1
        self.skeletal_start = 0
        self.skeletal_end = 0
        self.skeletal_masks = None
        self.debug_name = None

    def _sounds(self, b, sparse, unknown, rev):
        n = b.u16() if sparse else b.u8()
        for _ in range(n):
            if sparse:
                b.u16()
            if rev >= 220:
                b.u16()
                if unknown:
                    b.u8()
                b.skip(3)
            else:
                b.u24()

    def op(self, op, b, rev):
        if op == 1:
            n = b.u16()
            self.frame_lengths = [b.u16() for _ in range(n)]
            ids = [b.u16() for _ in range(n)]
            self.frame_ids = [i + (b.u16() << 16) for i in ids]
        elif op == 2:
            self.frame_step = b.u16()
        elif op == 3:
            n = b.u8()
            self.masks = [b.u8() for _ in range(n)] + [9999999]
        elif op == 4:
            self.stretches = True
        elif op == 5:
            self.forced_priority = b.u8()
        elif op == 6:
            self.left_hand_item = b.u16()
        elif op == 7:
            self.right_hand_item = b.u16()
        elif op == 8:
            self.max_loops = b.u8()
            self.looping = True
        elif op in (9, 10, 11):
            b.u8()
        elif op == 12:
            n = b.u8()
            b.skip(4 * n)
        elif op == 13:
            if rev >= 226:
                self.skeletal_id = b.s32()
            else:
                self._sounds(b, False, False, rev)
        elif op == 14:
            if rev >= 226:
                self._sounds(b, True, True, rev)
            else:
                self.skeletal_id = b.s32()
        elif op == 15:
            if rev >= 226:
                self.skeletal_start = b.u16()
                self.skeletal_end = b.u16()
            else:
                self._sounds(b, True, False, rev)
        elif op == 16:
            if rev < 226:
                self.skeletal_start = b.u16()
                self.skeletal_end = b.u16()
            elif rev >= 233:
                b.u8()
        elif op == 17:
            self.skeletal_masks = [False] * 256
            for _ in range(b.u8()):
                self.skeletal_masks[b.u8()] = True
        elif op == 18:
            if rev >= 230:
                self.debug_name = b.string()
        elif op == 19:
            pass
        elif op == 20:
            b.skip(5)
        else:
            raise DecodeError("seq %d: opcode %d" % (self.id, op))

    @property
    def skeletal(self) -> bool:
        return self.skeletal_id >= 0

    def duration_ticks(self) -> int:
        """Length in client cycles (20 ms each)."""
        if self.skeletal:
            return max(1, self.skeletal_end - self.skeletal_start)
        return sum(max(1, x) for x in self.frame_lengths)


class IdkDef(Def):
    """A player body-part kit."""

    def __init__(self, id_):
        super().__init__(id_)
        self.body_part = -1
        self.models = []
        self.chathead_models = []
        self.non_selectable = False

    def op(self, op, b, rev):
        if op == 1:
            self.body_part = b.u8()
        elif op == 2:
            self.models = [b.u16() for _ in range(b.u8())]
        elif op == 3:
            self.non_selectable = True
        elif op == 5:
            self.models = [b.s32() for _ in range(b.u8())]
        elif op == 40:
            self.recolor_from, self.recolor_to = _recolor(b)
        elif op == 41:
            self.retexture_from, self.retexture_to = _recolor(b)
        elif 60 <= op < 70:
            b.u16()
        elif 70 <= op < 80:
            b.s32()
        else:
            raise DecodeError("idk %d: opcode %d" % (self.id, op))


class SpotAnimDef(Def):
    """A graphic (spell or spec effect)."""

    def __init__(self, id_):
        super().__init__(id_)
        self.model = -1
        self.seq = -1
        self.width_scale = self.height_scale = 128
        self.orientation = 0
        self.ambient = self.contrast = 0

    def op(self, op, b, rev):
        if op == 1:
            self.model = b.u16()
        elif op == 2:
            self.seq = b.u16()
        elif op == 3:
            self.model = b.s32()
        elif op == 4:
            self.width_scale = b.u16()
        elif op == 5:
            self.height_scale = b.u16()
        elif op == 6:
            self.orientation = b.u16()
        elif op == 7:
            self.ambient = b.u8()
        elif op == 8:
            self.contrast = b.u8()
        elif op == 9:
            self.name = b.string()
        elif op == 10:
            pass
        elif op == 40:
            self.recolor_from, self.recolor_to = _recolor(b)
        elif op == 41:
            self.retexture_from, self.retexture_to = _recolor(b)
        elif op == 42:
            b.u16()
        else:
            raise DecodeError("spotanim %d: opcode %d" % (self.id, op))


def rgb_to_hsl_fields(rgb: int, overlay: bool):
    r = ((rgb >> 16) & 255) / 256.0
    g = ((rgb >> 8) & 255) / 256.0
    bl = (rgb & 255) / 256.0
    mn, mx = min(r, g, bl), max(r, g, bl)
    hue = sat = 0.0
    light = (mn + mx) / 2.0
    if mn != mx:
        sat = (mx - mn) / (mx + mn) if light < 0.5 else (mx - mn) / (2.0 - mx - mn)
        if mx == r:
            hue = (g - bl) / (mx - mn)
        elif mx == g:
            hue = 2.0 + (bl - r) / (mx - mn)
        else:
            hue = 4.0 + (r - g) / (mx - mn)
    hue /= 6.0
    s = max(0, min(255, int(sat * 256.0)))
    l = max(0, min(255, int(light * 256.0)))
    mult = int(512.0 * (sat * (1.0 - light))) if light > 0.5 else int(512.0 * (sat * light))
    mult = max(1, mult)
    return int(hue * 256.0), s, l, mult, int(mult * hue)


class UnderlayDef(Def):
    def __init__(self, id_):
        super().__init__(id_)
        self.rgb = 0
        self.texture = -1
        self.texture_size = 128
        self.hue = self.saturation = self.lightness = self.hue_multiplier = 0

    def op(self, op, b, rev):
        if op == 1:
            self.rgb = b.u24()
        elif op == 2:
            self.texture = _u16m1(b)
        elif op == 3:
            self.texture_size = b.u16()
        elif op in (4, 5):
            pass
        else:
            raise DecodeError("underlay %d: opcode %d" % (self.id, op))

    def post(self):
        _, self.saturation, self.lightness, self.hue_multiplier, self.hue = rgb_to_hsl_fields(self.rgb, False)


class OverlayDef(Def):
    def __init__(self, id_):
        super().__init__(id_)
        self.rgb = 0
        self.texture = -1
        self.hide_underlay = True
        self.secondary_rgb = -1
        self.hue = self.saturation = self.lightness = 0
        self.hue_blend = self.hue_multiplier = 0
        self.secondary_hue = self.secondary_saturation = self.secondary_lightness = 0
        self.texture_size = 128
        self.water_color = 0x122B3D

    def op(self, op, b, rev):
        if op == 1:
            self.rgb = b.u24()
        elif op == 2:
            self.texture = b.u8()
        elif op == 3:
            self.texture = _u16m1(b)
        elif op == 5:
            self.hide_underlay = False
        elif op == 6:
            self.name = b.string()
        elif op == 7:
            self.secondary_rgb = b.u24()
        elif op in (8, 10, 12):
            pass
        elif op == 9:
            self.texture_size = b.u16()
        elif op in (11, 14, 16):
            b.u8()
        elif op == 13:
            self.water_color = b.u24()
        elif op == 15:
            _u16m1(b)
        else:
            raise DecodeError("overlay %d: opcode %d" % (self.id, op))

    def post(self):
        if self.secondary_rgb != -1:
            h, s, l, _, _ = rgb_to_hsl_fields(self.secondary_rgb, True)
            self.secondary_hue, self.secondary_saturation, self.secondary_lightness = h, s, l
        self.hue, self.saturation, self.lightness, self.hue_multiplier, self.hue_blend = \
            rgb_to_hsl_fields(self.rgb, True)


class Defs:
    """Lazy, cached access to every config type."""

    KINDS = {
        "npc": (ARCH_NPC, NpcDef), "obj": (ARCH_OBJ, ObjDef), "loc": (ARCH_LOC, LocDef),
        "seq": (ARCH_SEQ, SeqDef), "idk": (ARCH_IDK, IdkDef), "spotanim": (ARCH_SPOTANIM, SpotAnimDef),
        "underlay": (ARCH_UNDERLAY, UnderlayDef), "overlay": (ARCH_OVERLAY, OverlayDef),
    }

    def __init__(self, cache, rev: int = 241):
        self.cache = cache
        self.rev = rev
        self._memo = {}

    def ids(self, kind: str):
        arch, _ = self.KINDS[kind]
        return sorted(self.cache.files(CONFIGS, arch).keys())

    def get(self, kind: str, id_: int):
        key = (kind, id_)
        if key not in self._memo:
            arch, cls = self.KINDS[kind]
            data = self.cache.files(CONFIGS, arch).get(id_)
            d = cls(id_)
            if data is not None:
                d.decode(data, self.rev)
            else:
                d = None
            self._memo[key] = d
        return self._memo[key]

    def npc(self, i): return self.get("npc", i)
    def obj(self, i): return self.get("obj", i)
    def loc(self, i): return self.get("loc", i)
    def seq(self, i): return self.get("seq", i)
    def idk(self, i): return self.get("idk", i)
    def spotanim(self, i): return self.get("spotanim", i)
    def underlay(self, i): return self.get("underlay", i)
    def overlay(self, i): return self.get("overlay", i)

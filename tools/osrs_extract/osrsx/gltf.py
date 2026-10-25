"""A small glTF 2.0 / GLB writer (stdlib only)."""
import json
import struct

FLOAT, UBYTE, USHORT, UINT = 5126, 5121, 5123, 5125
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963


class Gltf:
    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "osrs_extract (Gielinor Legends)"},
                  "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [],
                  "accessors": [], "bufferViews": [], "buffers": []}
        self.bin = bytearray()
        self._materials = {}

    # ---- low level ----------------------------------------------------------
    def _view(self, data: bytes, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.j["bufferViews"].append(v)
        return len(self.j["bufferViews"]) - 1

    def accessor(self, values, kind: str, comp=FLOAT, target=ARRAY_BUFFER, minmax=False, normalized=False):
        """values: flat list. kind: SCALAR/VEC2/VEC3/VEC4/MAT4."""
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[kind]
        fmt = {FLOAT: "f", UBYTE: "B", USHORT: "H", UINT: "I"}[comp]
        data = struct.pack("<%d%s" % (len(values), fmt), *values)
        if comp in (UBYTE, USHORT) and len(data) % 4:
            data += b"\0" * (4 - len(data) % 4)
        view = self._view(data, target)
        a = {"bufferView": view, "componentType": comp, "count": len(values) // n, "type": kind}
        if normalized:
            a["normalized"] = True
        if minmax and values:
            cols = [values[i::n] for i in range(n)]
            a["min"] = [min(c) for c in cols]
            a["max"] = [max(c) for c in cols]
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def image(self, png: bytes, name: str):
        view = self._view(png)
        self.j.setdefault("images", []).append({"bufferView": view, "mimeType": "image/png", "name": name})
        self.j.setdefault("samplers", [{"magFilter": 9728, "minFilter": 9986, "wrapS": 10497, "wrapT": 10497}])
        self.j.setdefault("textures", []).append({"source": len(self.j["images"]) - 1, "sampler": 0})
        return len(self.j["textures"]) - 1

    def material(self, name, texture=None, blend=False, double_sided=False, cutout=False):
        key = (name, texture, blend, double_sided, cutout)
        if key in self._materials:
            return self._materials[key]
        m = {"name": name, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0,
                                                   "roughnessFactor": 1.0}}
        if texture is not None:
            m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": texture}
        if blend:
            m["alphaMode"] = "BLEND"
        elif cutout:
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.5
        if double_sided:
            m["doubleSided"] = True
        self.j.setdefault("materials", []).append(m)
        self._materials[key] = len(self.j["materials"]) - 1
        return self._materials[key]

    def node(self, name, **kw):
        n = {"name": name}
        n.update({k: v for k, v in kw.items() if v is not None})
        self.j["nodes"].append(n)
        return len(self.j["nodes"]) - 1

    def add_root(self, node):
        self.j["scenes"][0]["nodes"].append(node)

    def mesh(self, name, primitives):
        self.j["meshes"].append({"name": name, "primitives": primitives})
        return len(self.j["meshes"]) - 1

    def skin(self, joints, inverse_binds, skeleton=None, name=None):
        ib = self.accessor(inverse_binds, "MAT4", target=None)
        s = {"joints": joints, "inverseBindMatrices": ib}
        if skeleton is not None:
            s["skeleton"] = skeleton
        if name:
            s["name"] = name
        self.j.setdefault("skins", []).append(s)
        return len(self.j["skins"]) - 1

    def animation(self, name, channels):
        """channels: [(node, path, times, values, interpolation)]."""
        samplers, chans = [], []
        time_cache = {}
        for node, path, times, values, interp in channels:
            tk = tuple(times)
            if tk not in time_cache:
                time_cache[tk] = self.accessor(list(times), "SCALAR", target=None, minmax=True)
            kind = {"translation": "VEC3", "scale": "VEC3", "rotation": "VEC4", "weights": "SCALAR"}[path]
            out = self.accessor(values, kind, target=None)
            samplers.append({"input": time_cache[tk], "output": out, "interpolation": interp})
            chans.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": path}})
        self.j.setdefault("animations", []).append({"name": name, "samplers": samplers, "channels": chans})

    def glb(self) -> bytes:
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        for k in [k for k, v in self.j.items() if isinstance(v, list) and not v]:
            del self.j[k]
        js = json.dumps(self.j, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
                + struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin))

    def write(self, path):
        with open(path, "wb") as f:
            f.write(self.glb())

"""Reads the OSRS game cache.

Two layouts are supported:
- a flat cache (RuneLite "flatcache", as in github.com/abextm/osrs-cache):
  one `<index>.flatcache` text file per index;
- a normal client cache folder: `main_file_cache.dat2` + `.idxN` files
  (OpenRS2 archive downloads, osrs.world, a RuneLite jagexcache).

Only file contents are needed by the exporters: `files(index, archive)`
returns {file_id: bytes} for one archive.
"""
import base64
import bz2
import os
import struct
import zlib

from .buffer import Buffer

GOLDEN = 0x9E3779B9


def xtea_decrypt(data: bytearray, start: int, end: int, key) -> None:
    n = (end - start) // 8
    for i in range(n):
        o = start + i * 8
        v0, v1 = struct.unpack_from(">II", data, o)
        s = (GOLDEN * 32) & 0xFFFFFFFF
        for _ in range(32):
            v1 = (v1 - ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (s + key[(s >> 11) & 3]))) & 0xFFFFFFFF
            s = (s - GOLDEN) & 0xFFFFFFFF
            v0 = (v0 - ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (s + key[s & 3]))) & 0xFFFFFFFF
        struct.pack_into(">II", data, o, v0, v1)


def decode_container(raw: bytes, key=None) -> bytes:
    comp = raw[0]
    size = struct.unpack_from(">I", raw, 1)[0]
    if key and any(key):
        buf = bytearray(raw)
        k = [x & 0xFFFFFFFF for x in key]
        xtea_decrypt(buf, 5, 5 + size + (4 if comp else 0), k)
        raw = bytes(buf)
    if comp == 0:
        return raw[5:5 + size]
    actual = struct.unpack_from(">I", raw, 5)[0]
    body = raw[9:9 + size]
    if comp == 1:
        out = bz2.decompress(b"BZh1" + body)
    elif comp == 2:
        out = zlib.decompress(body, 16 + zlib.MAX_WBITS)
    else:
        raise ValueError("unsupported compression %d" % comp)
    if len(out) != actual:
        raise ValueError("container size mismatch")
    return out


def split_archive(data: bytes, file_ids):
    """Splits a group into its files (file_ids in reference-table order)."""
    count = len(file_ids)
    if count == 1:
        return {file_ids[0]: data}
    chunks = data[-1]
    p = len(data) - 1 - chunks * count * 4
    chunk_sizes = []
    sizes = [0] * count
    for _ in range(chunks):
        acc = 0
        row = []
        for i in range(count):
            acc += struct.unpack_from(">i", data, p)[0]
            p += 4
            row.append(acc)
            sizes[i] += acc
        chunk_sizes.append(row)
    parts = [bytearray() for _ in range(count)]
    off = 0
    for row in chunk_sizes:
        for i in range(count):
            parts[i] += data[off:off + row[i]]
            off += row[i]
    return {fid: bytes(parts[i]) for i, fid in enumerate(file_ids)}


class IndexInfo:
    """What a reference table says about one index."""

    def __init__(self):
        self.archives = {}     # archive id -> [file ids]
        self.names = {}        # archive id -> name hash
        self.file_names = {}   # archive id -> [file name hashes]
        self.revision = 0

    @staticmethod
    def decode(data: bytes) -> "IndexInfo":
        info = IndexInfo()
        b = Buffer(data)
        protocol = b.u8()
        if protocol >= 6:
            info.revision = b.s32()
        flags = b.u8()
        named, whirl, sized = flags & 1, flags & 2, flags & 4
        count = b.big_smart_ref() if protocol >= 7 else b.u16()
        ids = []
        last = 0
        for _ in range(count):
            last += b.big_smart_ref() if protocol >= 7 else b.u16()
            ids.append(last)
        if named:
            for a in ids:
                info.names[a] = b.s32()
        if whirl:
            b.skip(64 * count)
        b.skip(4 * count)            # crcs
        if sized:
            b.skip(8 * count)
        b.skip(4 * count)            # revisions
        counts = [b.big_smart_ref() if protocol >= 7 else b.u16() for _ in ids]
        for a, n in zip(ids, counts):
            fl = []
            f = 0
            for _ in range(n):
                f += b.big_smart_ref() if protocol >= 7 else b.u16()
                fl.append(f)
            info.archives[a] = fl
        if named:
            for a, n in zip(ids, counts):
                info.file_names[a] = [b.s32() for _ in range(n)]
        return info


def djb2(name: str) -> int:
    h = 0
    for ch in name.lower():
        h = (h * 31 + ord(ch)) & 0xFFFFFFFF
    return h - (1 << 32) if h & 0x80000000 else h


class Cache:
    """Opens a cache folder; detects flatcache vs dat2/idx."""

    def __init__(self, path: str, xteas=None):
        self.path = path
        self.xteas = xteas or {}
        self._indexes = {}
        self._flat = {}
        if os.path.exists(os.path.join(path, "main_file_cache.dat2")):
            self.kind = "disk"
            self._dat = open(os.path.join(path, "main_file_cache.dat2"), "rb")
            self._dat_size = os.path.getsize(os.path.join(path, "main_file_cache.dat2"))
        elif os.path.exists(os.path.join(path, "2.flatcache")):
            self.kind = "flat"
        else:
            raise FileNotFoundError("no OSRS cache in %s" % path)
        self._split_cache = {}

    # ---- low level -------------------------------------------------------
    def _read_disk(self, index: int, archive: int):
        p = os.path.join(self.path, "main_file_cache.idx%d" % index)
        if not os.path.exists(p):
            return None
        with open(p, "rb") as f:
            f.seek(archive * 6)
            e = f.read(6)
        if len(e) < 6:
            return None
        size = int.from_bytes(e[:3], "big")
        sector = int.from_bytes(e[3:], "big")
        if size <= 0 or sector <= 0:
            return None
        big = archive > 0xFFFF
        hdr = 10 if big else 8
        chunk = 520 - hdr
        out = bytearray()
        part = 0
        while len(out) < size:
            if sector <= 0 or sector * 520 >= self._dat_size:
                return None
            self._dat.seek(sector * 520)
            s = self._dat.read(520)
            n = min(chunk, size - len(out))
            if big:
                nxt = int.from_bytes(s[6:9], "big")
            else:
                nxt = int.from_bytes(s[4:7], "big")
            out += s[hdr:hdr + n]
            sector = nxt
            part += 1
        return bytes(out)

    def _load_flat(self, index: int):
        if index in self._flat:
            return self._flat[index]
        p = os.path.join(self.path, "%d.flatcache" % index)
        info = IndexInfo()
        raw = {}
        if os.path.exists(p):
            cur = None
            with open(p) as f:
                for line in f:
                    k, _, v = line.rstrip("\n").partition("=")
                    if k == "id":
                        cur = int(v)
                        info.archives[cur] = []
                    elif cur is None:
                        if k == "revision":
                            info.revision = int(v)
                    elif k == "file":
                        fid, _, nh = v.partition("=")
                        info.archives[cur].append(int(fid))
                        info.file_names.setdefault(cur, []).append(int(nh))
                    elif k == "namehash":
                        info.names[cur] = int(v)
                    elif k == "contents":
                        raw[cur] = v
        self._flat[index] = (info, raw)
        return self._flat[index]

    def index(self, index: int) -> IndexInfo:
        if index not in self._indexes:
            if self.kind == "flat":
                self._indexes[index] = self._load_flat(index)[0]
            else:
                raw = self._read_disk(255, index)
                self._indexes[index] = IndexInfo.decode(decode_container(raw)) if raw else IndexInfo()
        return self._indexes[index]

    def raw(self, index: int, archive: int):
        if self.kind == "flat":
            r = self._load_flat(index)[1].get(archive)
            return base64.b64decode(r) if r else None
        return self._read_disk(index, archive)

    # ---- public ----------------------------------------------------------
    def archive_ids(self, index: int):
        return sorted(self.index(index).archives)

    def has(self, index: int, archive: int) -> bool:
        return archive in self.index(index).archives

    def archive_by_name(self, index: int, name: str):
        h = djb2(name)
        for a, nh in self.index(index).names.items():
            if nh == h:
                return a
        return None

    def files(self, index: int, archive: int, key=None):
        """{file_id: bytes} for one archive (cached per archive)."""
        ck = (index, archive)
        if ck in self._split_cache:
            return self._split_cache[ck]
        info = self.index(index)
        ids = info.archives.get(archive)
        raw = self.raw(index, archive)
        if raw is None or not ids:
            return {}
        if key is None:
            key = self.xteas.get(archive) if index == 5 else None
        try:
            data = decode_container(raw, key)
        except Exception:
            return {}
        out = split_archive(data, ids)
        if len(self._split_cache) > 4096:
            self._split_cache.clear()
        self._split_cache[ck] = out
        return out

    def file(self, index: int, archive: int, file_id: int = 0, key=None):
        return self.files(index, archive, key).get(file_id)

    def revision(self) -> int:
        """Best guess at the client revision (configs index revision is a timestamp in new caches)."""
        return int(os.environ.get("OSRS_REV", "241"))

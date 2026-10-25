"""Big-endian byte reader with the RuneScape "smart" encodings."""
import struct


class Buffer:
    __slots__ = ("data", "pos")

    def __init__(self, data: bytes, pos: int = 0):
        self.data = data
        self.pos = pos

    @property
    def remaining(self) -> int:
        return len(self.data) - self.pos

    def u8(self) -> int:
        v = self.data[self.pos]
        self.pos += 1
        return v

    def s8(self) -> int:
        v = self.data[self.pos]
        self.pos += 1
        return v - 256 if v > 127 else v

    def u16(self) -> int:
        v = (self.data[self.pos] << 8) | self.data[self.pos + 1]
        self.pos += 2
        return v

    def s16(self) -> int:
        v = self.u16()
        return v - 0x10000 if v > 32767 else v

    def u24(self) -> int:
        d = self.data
        p = self.pos
        self.pos += 3
        return (d[p] << 16) | (d[p + 1] << 8) | d[p + 2]

    def s32(self) -> int:
        v = struct.unpack_from(">i", self.data, self.pos)[0]
        self.pos += 4
        return v

    def u32(self) -> int:
        v = struct.unpack_from(">I", self.data, self.pos)[0]
        self.pos += 4
        return v

    def f32(self) -> float:
        v = struct.unpack_from(">f", self.data, self.pos)[0]
        self.pos += 4
        return v

    def peek(self) -> int:
        return self.data[self.pos]

    def big_smart(self) -> int:
        if self.data[self.pos] & 0x80:
            return self.s32() & 0x7FFFFFFF
        v = self.u16()
        return -1 if v == 32767 else v

    def big_smart_ref(self) -> int:
        """Reference-table big smart (no -1 sentinel)."""
        if self.data[self.pos] & 0x80:
            return self.s32() & 0x7FFFFFFF
        return self.u16()

    def usmart(self) -> int:
        if self.data[self.pos] < 128:
            return self.u8()
        return self.u16() - 0x8000

    def usmart_min1(self) -> int:
        if self.data[self.pos] < 128:
            return self.u8() - 1
        return self.u16() - 0x8001

    def smart2(self) -> int:
        if self.data[self.pos] < 128:
            return self.u8() - 64
        return self.u16() - 49152

    def smart3(self) -> int:
        total = 0
        v = self.usmart()
        while v == 32767:
            v = self.usmart()
            total += 32767
        return total + v

    def string(self) -> str:
        end = self.data.index(0, self.pos)
        s = self.data[self.pos:end].decode("cp1252", errors="replace")
        self.pos = end + 1
        return s

    def bytes(self, n: int) -> bytes:
        v = self.data[self.pos:self.pos + n]
        self.pos += n
        return v

    def skip(self, n: int) -> None:
        self.pos += n

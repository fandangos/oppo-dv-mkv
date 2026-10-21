"""Tiny ELF32 LOAD-segment reader shared by the porting scripts: va <-> file offset, read by VA."""
import struct
class Elf:
    def __init__(self, path):
        self.path = path; self.d = open(path, 'rb').read(); d = self.d
        phoff, = struct.unpack_from('<I', d, 0x1c); phentsize, phnum = struct.unpack_from('<HH', d, 0x2a)
        self.segs = []
        for i in range(phnum):
            t, off, va, pa, fsz, msz, fl, al = struct.unpack_from('<8I', d, phoff + i * phentsize)
            if t == 1: self.segs.append((va, off, fsz, msz, fl))
    def off(self, va):
        for v, o, fs, ms, fl in self.segs:
            if v <= va < v + fs: return o + va - v
        raise ValueError(hex(va))
    def va(self, off):
        for v, o, fs, ms, fl in self.segs:
            if o <= off < o + fs: return v + off - o
        return None
    def rd(self, va, n): o = self.off(va); return self.d[o:o + n]
    def u32(self, va): return struct.unpack('<I', self.rd(va, 4))[0]
    def seg_of(self, va):
        for s in self.segs:
            if s[0] <= va < s[0] + s[2]: return s

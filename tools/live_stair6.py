"""Read-only look at the running game (Extreme or vanilla): path finder counters over a few
seconds, every stairs tile at (nearly) ground height, its links, and the units around it.
Nothing is written to the game.

    python tools/live_stair6.py [seconds]
"""
import ctypes, ctypes.wintypes as W, struct, subprocess, sys, time

K = ctypes.WinDLL('kernel32', use_last_error=True)
K.OpenProcess.restype = W.HANDLE
K.ReadProcessMemory.argtypes = [W.HANDLE, W.LPCVOID, W.LPVOID, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]

LAYOUT = {   # flags, path finder, unit array, tick counter
    'Stronghold_Crusader_Extreme.exe': (0x268B868, 0x13903B8, 0x145D03C, 0x120F71C),
    'Stronghold Crusader.exe': (0x1BF8368, 0x12BB8C8, 0x138854C, 0x117CADC),
}
DIRS = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]


def pid_of(name):
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq ' + name, '/FO', 'CSV', '/NH'],
                         capture_output=True, text=True, encoding='mbcs', errors='replace').stdout or ''
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if parts and parts[0].lower() == name.lower():
            return int(parts[1])


class Game:
    def __init__(self):
        for name, layout in LAYOUT.items():
            pid = pid_of(name)
            if pid:
                self.name, (self.flags, self.pf, self.units, self.ticks) = name, layout
                self.h = K.OpenProcess(0x0010 | 0x0400, False, pid)   # VM_READ | QUERY_INFORMATION
                if not self.h:
                    raise SystemExit('cannot open %s: error %d' % (name, ctypes.get_last_error()))
                self.tms = self.flags - 0x165160
                return
        raise SystemExit('the game is not running')

    def read(self, address, size):
        buf = ctypes.create_string_buffer(size)
        got = ctypes.c_size_t()
        if not K.ReadProcessMemory(self.h, address, buf, size, ctypes.byref(got)):
            raise OSError('read %X failed' % address)
        return buf.raw

    def u32(self, a): return struct.unpack('<I', self.read(a, 4))[0]
    def s16(self, a): return struct.unpack('<h', self.read(a, 2))[0]
    def u8(self, a): return self.read(a, 1)[0]


def counters(g):
    return {'route searches': g.u32(g.pf + 0xAC) + g.u32(g.pf + 0xA8),
            'walk-back failures (each rebuilds every link)': g.u32(g.pf + 0x78),
            'area map rebuilds': g.u32(g.pf + 0x74),
            'ticks': g.u32(g.ticks)}


def main():
    g = Game()
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 3
    print('game:', g.name)
    a = counters(g); time.sleep(secs); b = counters(g)
    print('over %.0f s:' % secs)
    for k in a:
        print('   %-48s %d' % (k, b[k] - a[k]))

    flags = g.read(g.flags, 4 * 160000)
    live = g.read(g.tms + 0x29FA30, 160000)
    base = g.read(g.tms + 0x2B3440, 160000)
    links = g.read(g.tms + 0x38B2F0, 160000)
    low = [t for t in range(80400) if struct.unpack_from('<I', flags, 4 * t)[0] & 0x800
           and live[t] - base[t] <= 8]
    print('stairs tiles at ground height: %d' % len(low))
    near = {}
    unit_bytes = g.read(g.units, 0x490 * 2500)
    for uid in range(1, 2500):
        u = uid * 0x490
        if struct.unpack_from('<h', unit_bytes, u + 0x8C)[0] == 0:
            continue
        tile = struct.unpack_from('<I', unit_bytes, u + 0xD4)[0]
        near.setdefault(tile, []).append(uid)
    for t in low[:40]:
        f = struct.unpack_from('<I', flags, 4 * t)[0]
        print('  tile %6d flags %08X height %d (ground %d) links %s' % (
            t, f, live[t], base[t], format(links[t], '08b')))
    # units standing on or right next to those tiles: who they are and what they do
    print('units on such tiles:')
    for t in low:
        for uid in near.get(t, []):
            u = uid * 0x490
            x, y = struct.unpack_from('<hh', unit_bytes, u + 0xC4)
            print('  unit %4d type %3d at (%d,%d) state %d move %d dest (%d,%d) path %d/%d' % (
                uid, struct.unpack_from('<h', unit_bytes, u + 0x8E)[0], x, y,
                struct.unpack_from('<h', unit_bytes, u + 0x2C0)[0],
                struct.unpack_from('<h', unit_bytes, u + 0xF6)[0],
                *struct.unpack_from('<hh', unit_bytes, u + 0xC8),
                struct.unpack_from('<h', unit_bytes, u + 0xFA)[0],
                struct.unpack_from('<h', unit_bytes, u + 0xFC)[0]))


if __name__ == '__main__':
    main()

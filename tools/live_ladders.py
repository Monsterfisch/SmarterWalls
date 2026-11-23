"""Read-only look at the running game: every ladder / siege tower the path finder knows (climb data),
where its two ends stand, and for each end tile its flags, path links and area. Raised crenellation
parts around them are listed with the same facts. Nothing is written to the game.

    python tools/live_ladders.py
"""
import ctypes, ctypes.wintypes as W, struct, subprocess

K = ctypes.WinDLL('kernel32', use_last_error=True)
K.OpenProcess.restype = W.HANDLE
K.ReadProcessMemory.argtypes = [W.HANDLE, W.LPCVOID, W.LPVOID, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]

LAYOUT = {   # tile flags, path links, area map, path finder, row table, building array
    'Stronghold_Crusader_Extreme.exe': (0x268B868, 0x28B19F8, 0x288A5D8, 0x13903B8, 0x2DCA800),
    'Stronghold Crusader.exe': (0x1BF8368, 0x1E1E4F8, 0x1DF70D8, 0x12BB8C8, 0x2337300),
}
TYPES = {1: 'ladder', 3: 'gatehouse L', 4: 'gatehouse S', 5: 'tower?', 6: 'siege tower?', 7: 'siege tower'}
DIRS = 'N NE E SE S SW W NW'.split()


def pid_of(name):
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq ' + name, '/FO', 'CSV', '/NH'],
                         capture_output=True, text=True, encoding='mbcs', errors='replace').stdout or ''
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if parts and parts[0].lower() == name.lower():
            return int(parts[1])


def main():
    for name, layout in LAYOUT.items():
        pid = pid_of(name)
        if pid:
            break
    else:
        raise SystemExit('the game is not running')
    flags_a, links_a, area_a, pf, rows_a = layout
    h = K.OpenProcess(0x0010 | 0x0400, False, pid)

    def read(a, n):
        buf = ctypes.create_string_buffer(n)
        got = ctypes.c_size_t()
        if not K.ReadProcessMemory(h, a, buf, n, ctypes.byref(got)):
            raise OSError('read %X failed' % a)
        return buf.raw
    u32 = lambda a: struct.unpack('<i', read(a, 4))[0]
    rows = [struct.unpack('<i', read(rows_a + 12 * y, 4))[0] for y in range(400)]
    tile = lambda x, y: rows[y] + x
    flags = lambda t: struct.unpack('<I', read(flags_a + 4 * t, 4))[0]
    links = lambda t: read(links_a + t, 1)[0]
    area = lambda t: struct.unpack('<h', read(area_a + 2 * t, 2))[0]

    def describe(label, x, y):
        t = tile(x, y); f = flags(t); l = links(t)
        print('      %-7s (%3d,%3d) flags %08X%s links %s area %d' % (
            label, x, y, f, ' RAISED' if f & 0x400000 else '', ','.join(d for k, d in enumerate(DIRS) if l >> k & 1) or '-', area(t)))
        return t
    print('game:', name)
    print('climb data in use:')
    seen = []
    for i in range(1, 200):
        base = pf + 0x1084 + i * 0x204
        raw = read(base, 0x44)
        used, typ = struct.unpack_from('<ii', raw, 0)
        if not used:
            continue
        bx, by, btile, tx, ty, ttile, farea, wgroup, users = struct.unpack_from('<iiiiiiiii', raw, 0x1C)
        print('  #%d %s: climbs %d (bottom area %d, top area %d), %d unit(s) using it' % (
            i, TYPES.get(typ, 'type %d' % typ), used, farea, wgroup, users))
        describe('bottom', bx, by)
        describe('top', tx, ty)
        seen.append((tx, ty))
        # the three tiles beyond the top tile, going inland
        for k in range(8):
            dx, dy = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)][k]
            nx, ny = tx + dx, ty + dy
            f = flags(tile(nx, ny))
            if f & 0x400000:
                describe('raised', nx, ny)
    if not seen:
        print('  none - put a ladder or siege tower against a wall first')


if __name__ == '__main__':
    main()

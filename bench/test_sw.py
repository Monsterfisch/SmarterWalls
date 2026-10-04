"""Runs smarter-walls unchanged in the emulator on both exes, against the game's own wall
code (validateWallBuildPath, renderWallDragPreview, placeWalls). Addresses are found here
independently of the module."""
import sys
import harness
from harness import Host, SENTINEL, MASK

FAILS = []
COUNT = [0]
TILES = 400 * 400


def check(label, got, want):
    COUNT[0] += 1
    if got != want:
        FAILS.append(label)
        print('  FAIL %s: got %r want %r' % (label, got, want))


class Bench(Host):
    def __init__(self, *a, **k):
        self.allocations = []
        super().__init__(*a, **k)

    def allocate(self, size, zero=None):
        a = super().allocate(size, zero)
        self.allocations.append((a, int(size)))
        return a


def bresenham(x1, y1, x2, y2):
    out = []
    dx, dy = abs(x2 - x1), -abs(y2 - y1)
    sx, sy = (1 if x1 < x2 else -1), (1 if y1 < y2 else -1)
    err, x, y = dx + dy, x1, y1
    while True:
        out.append((x, y))
        if (x, y) == (x2, y2):
            return out
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x += sx
        if e2 <= dx:
            err += dx; y += sy


def game_line(x1, y1, x2, y2):
    out, x, y = [], x1, y1
    while True:
        out.append((x, y))
        if (x, y) == (x2, y2):
            return out
        if x != x2: x += 1 if x < x2 else -1
        if y != y2: y += 1 if y < y2 else -1


def suite(ext, config):
    tag = ('EXT' if ext else 'VAN') + ' ' + ','.join('%s=%s' % kv for kv in sorted(config.items()))
    print(tag)
    H = Bench(extreme=ext, config=config)
    E = H.E
    f = lambda p: E.find(p)[0]
    call = lambda site: (site + 5 + E.i32(site + 1)) & MASK
    validate = f('83 EC 20 33 C0 39 05 ? ? ? ? 8B D1')
    preview = f('83 EC 14 8B 54 24 1C 57')
    place = f('83 EC 28 8B 54 24 2C 53')
    VALID = E.u32(validate + 0x7A)
    ROWS = E.u32(validate + 0xD1)
    TMS = E.u32(f('F7 04 9D ? ? ? ? 00 01 00 00') + 3) - 0x165160
    FLAGS, BID, LIVE, BASE, DMG, GFX = (TMS + 0x165160, TMS + 0x2029B0, TMS + 0x29FA30,
                                        TMS + 0x2B3440, TMS + 0x3290A0, TMS + 0xA0CC0)
    record = [a for a, s in H.allocations if s == TILES + 16]
    REC = record[0] if record else None
    any_angle = config.get('anyAngle', True)
    flow = config.get('flow', True)
    routing = any_angle or flow

    # every hook the settings ask for, and none other
    patched = {a for a, _ in H.patched}
    check(tag + ' entry hooks', all(x in patched for x in (validate, preview)), routing)
    check(tag + ' placeWalls hook', place in patched, routing or config.get('stairs', True) or config.get('crenellations', True))

    # the map: rows of 400, every tile valid, ground at 8
    for y in range(400):
        H.put32(ROWS + 12 * y, y * 400)
    H.m.write(VALID, b'\x01' * TILES)
    H.m.write(BASE, b'\x08' * TILES)
    H.m.write(LIVE, b'\x08' * TILES)

    def stubs():
        v = validate
        for site, ret in ((0x275, 0x10), (0x2B6, 0x1C), (0x2D1, 0), (0x2E3, 0x10), (0x30D, 0x1C),
                          (0x324, 0x10), (0x342, 0xC)):
            H.stub(call(v + site), 0, ret)
        p = place
        H.stub(call(p + 0x55), 5000, 8)              # getWallTilesThatCanBeBuilt
        for site, ret in ((0x3A3, 8), (0x3AB, 4), (0x3C1, 0xC), (0x523, 0x10), (0x53D, 4)):
            H.stub(call(p + site), 0, ret)
    stubs()

    # the game's neighbour offsets per row (N, NE, E, SE, S, SW, W, NW), set at map load
    for y in range(400):
        for k, d in enumerate((-400, -399, 1, 401, 400, 399, -1, -401)):
            H.put32(TMS + 32 * y + 4 * k, d & MASK)

    def nested(address):
        # an exposeCode call made from lua while the emulator is already running
        def fn(this, *args):
            cpu = H.cpu
            saved, eip, count = dict(cpu.r), cpu.eip, cpu.count
            cpu.r['esp'] = 0x70000000
            for v in reversed(args):
                cpu.push(int(v) & MASK)
            cpu.push(SENTINEL)
            cpu.r['ecx'] = this & MASK
            cpu.eip = address
            cpu.run(SENTINEL, 200000)
            result = cpu.r['eax']
            cpu.r.clear(); cpu.r.update(saved); cpu.eip, cpu.count = eip, count
            return result
        return fn
    H.exposed[call(validate + 0x176)] = nested(call(validate + 0x176))

    def tile(x, y):
        return y * 400 + x

    def reset():
        H.m.write(FLAGS, b'\0' * 4 * TILES)
        H.m.write(BID, b'\0' * 2 * TILES)
        H.m.write(LIVE, b'\x08' * TILES)
        H.m.write(DMG, b'\0' * TILES)
        H.m.write(GFX, b'\0' * 2 * TILES)

    def run_validate(x1, y1, x2, y2, mapper=0x19):
        H.run(validate, regs=dict(ecx=TMS), stack=[1, x1, y1, x2, y2, mapper])
        return H.u32(TMS + 0x55491C) == 0

    def run_place(x1, y1, x2, y2, mapper=0x19):
        cpu = H.run(place, regs=dict(ecx=TMS), stack=[1, x1, y1, x2, y2, mapper, 5000])
        return cpu

    def walls():
        out = set()
        data = H.m.read(FLAGS, 4 * TILES)
        for t in range(TILES):
            if data[4 * t + 1] & 1:
                out.add((t % 400, t // 400))
        return out

    def connected(path):
        return all(max(abs(a[0] - b[0]), abs(a[1] - b[1])) == 1 for a, b in zip(path, path[1:]))

    # A. an open field
    reset()
    a = (100, 100, 113, 105)
    check(tag + ' A valid', run_validate(*a), True)
    run_place(*a)
    want = set(bresenham(*a)) if any_angle else set(game_line(*a))
    got = walls()
    check(tag + ' A wall tiles', got, want)
    check(tag + ' A wall height', {H.m.read(LIVE + tile(x, y), 1)[0] for x, y in got}, {8 + 90})

    # B. a building in the way
    reset()
    block = {(x, y) for x in range(104, 108) for y in range(100, 105)}
    for x, y in block:
        H.put16(BID + 2 * tile(x, y), 7)
    a = (100, 102, 112, 102)
    ok = run_validate(*a)
    check(tag + ' B valid', ok, flow)
    run_place(*a)
    got = walls()
    if flow:
        check(tag + ' B nothing on the building', got & block, set())
        check(tag + ' B ends', {(100, 102), (112, 102)} <= got, True)
        # one 8-connected chain from start to end
        seen, todo = {(100, 102)}, [(100, 102)]
        while todo:
            x, y = todo.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (x + dx, y + dy)
                    if n in got and n not in seen:
                        seen.add(n); todo.append(n)
        check(tag + ' B connected', (112, 102) in seen, True)
        check(tag + ' B hugs the building', max(y for _, y in got) <= 106 or min(y for _, y in got) >= 98, True)
        check(tag + ' B no waste', len(got) <= 17, True)
    else:
        check(tag + ' B nothing built', got, set())

    # C. the preview draws the same tiles the wall gets
    reset()
    for x, y in block:
        H.put16(BID + 2 * tile(x, y), 7)
    H.put32(TMS + 0x554984, 5000)
    H.put32(E.u32(preview + 0x1B6), 0x100)       # the construction sprites' first frame
    run_validate(*a)
    H.run(preview, until=preview + 0x3D4, regs=dict(ecx=TMS), stack=[1, *a, 0x19])
    gfx = H.m.read(GFX, 2 * TILES)
    drawn = {(t % 400, t // 400) for t in range(TILES) if gfx[2 * t] or gfx[2 * t + 1]}
    run_place(*a)
    if flow:
        check(tag + ' C preview = wall', drawn, walls())
        check(tag + ' C cost = tiles', H.u32(TMS + 0x554988), len(walls()))

    # D. a crenellation along a bent wall follows it
    reset()
    bent = game_line(150, 150, 156, 156) + game_line(156, 156, 166, 156)[1:]
    for x, y in bent:
        H.put32(FLAGS + 4 * tile(x, y), 0x100)
        H.put8(LIVE + tile(x, y), 98)
    c = (150, 149, 166, 155)
    okc = run_validate(*c, mapper=0x1A)
    run_place(*c, mapper=0x1A)
    data = H.m.read(FLAGS, 4 * TILES)
    cren = {(t % 400, t // 400) for t in range(TILES) if data[4 * t + 1] & 2}
    if flow:
        check(tag + ' D crenellation valid', okc, True)
        check(tag + ' D crenellation beside the wall', cren & set(bent), set())
        check(tag + ' D crenellation follows', len(cren) >= 15, True)

    # E. damaged stairs and crenellations
    stairs_on = config.get('stairs', True)
    cren_on = config.get('crenellations', True)
    reset()
    # a wall at 98, stairs below it at 82 (knocked to 52 with 10 damage counted)
    H.put32(FLAGS + 4 * tile(200, 200), 0x100); H.put8(LIVE + tile(200, 200), 98)
    t = tile(201, 200)
    H.put32(FLAGS + 4 * t, 0x900); H.put8(LIVE + t, 52); H.put8(DMG + t, 10)
    run_place(201, 200, 201, 200)
    check(tag + ' E stairs height', H.m.read(LIVE + t, 1)[0], 82 if stairs_on else 98)
    check(tag + ' E stairs still stairs', H.u32(FLAGS + 4 * t) & 0x900, 0x900)
    check(tag + ' E stairs undamaged', H.m.read(DMG + t, 1)[0], 0)
    # with a remembered height
    if stairs_on and REC:
        H.put32(FLAGS + 4 * t, 0x900); H.put8(LIVE + t, 40); H.put8(DMG + t, 6); H.put8(REC + t, 66)
        run_place(201, 200, 201, 200)
        check(tag + ' E remembered height', (H.m.read(LIVE + t, 1)[0], H.m.read(REC + t, 1)[0]), (66, 0))
    # low stairs, not knocked: 42 down to 30 with 12 counted
    H.put32(FLAGS + 4 * t, 0x900); H.put8(LIVE + t, 30); H.put8(DMG + t, 12)
    run_place(201, 200, 201, 200)
    check(tag + ' E low stairs height', H.m.read(LIVE + t, 1)[0], 42 if stairs_on else 98)
    # a damaged tall crenellation
    u = tile(210, 200)
    H.put32(FLAGS + 4 * u, 0x300); H.put8(LIVE + u, 8 + 0x62 - 25); H.put8(DMG + u, 5)
    run_place(210, 200, 210, 200)
    check(tag + ' E crenellation repaired', (H.m.read(LIVE + u, 1)[0], H.u32(FLAGS + 4 * u) & 0x300),
          (8 + 0x62, 0x300) if cren_on else (8 + 0x5A, 0x100))
    # a damaged low one
    H.put32(FLAGS + 4 * u, 0x10300); H.put8(LIVE + u, 8 + 0x44 - 3); H.put8(DMG + u, 3)
    run_place(210, 200, 210, 200)
    check(tag + ' E low crenellation repaired', H.m.read(LIVE + u, 1)[0], 8 + 0x44 if cren_on else 8 + 0x5A)
    # an intact one still turns into wall
    H.put32(FLAGS + 4 * u, 0x300); H.put8(LIVE + u, 8 + 0x62); H.put8(DMG + u, 0)
    run_place(210, 200, 210, 200)
    check(tag + ' E intact crenellation -> wall', (H.m.read(LIVE + u, 1)[0], H.u32(FLAGS + 4 * u) & 0x300),
          (8 + 0x5A, 0x100))
    # a damaged plain wall is still rebuilt as wall
    w = tile(220, 200)
    H.put32(FLAGS + 4 * w, 0x100); H.put8(LIVE + w, 60); H.put8(DMG + w, 30)
    run_place(220, 200, 220, 200)
    check(tag + ' E plain wall', H.m.read(LIVE + w, 1)[0], 98)

    # F. the damage hooks remember and forget the stairs' height
    if stairs_on and REC:
        rec_site = f('8B 15 ? ? ? ? 83 05 ? ? ? ? 01 3B C5')
        forget_site = f('81 A4 9F 60 51 16 00 FF F4 BE FF')
        s = tile(230, 200)
        H.put32(FLAGS + 4 * s, 0x900); H.put8(LIVE + s, 82); H.put8(DMG + s, 0); H.put8(REC + s, 0)
        cpu = H.run(rec_site, until=rec_site + 6, regs=dict(ebx=s, edi=TMS, eax=0x1234))
        check(tag + ' F remembered', H.m.read(REC + s, 1)[0], 82)
        check(tag + ' F eax kept', cpu.r['eax'], 0x1234)
        check(tag + ' F edx loaded', cpu.r['edx'], H.u32(E.u32(rec_site + 2)))
        H.put8(LIVE + s, 62)
        H.run(rec_site, until=rec_site + 6, regs=dict(ebx=s, edi=TMS, eax=0))
        check(tag + ' F second chop keeps the first', H.m.read(REC + s, 1)[0], 82)
        H.put8(DMG + s, 3); H.put8(LIVE + s, 90)
        H.run(rec_site, until=rec_site + 6, regs=dict(ebx=s, edi=TMS, eax=0))
        check(tag + ' F damaged: unchanged', H.m.read(REC + s, 1)[0], 82)
        H.put32(FLAGS + 4 * s, 0xFFFFFFFF)
        H.run(forget_site, until=forget_site + 11, regs=dict(ebx=s, edi=TMS))
        check(tag + ' F forgotten', (H.m.read(REC + s, 1)[0], H.u32(FLAGS + 4 * s)), (0, 0xFFBEF4FF))

    check(tag + ' no warnings', [l for l in H.logs if 'WARNING' in l], [])


if __name__ == '__main__':
    configs = [{}, {'anyAngle': False}, {'flow': False}, {'stairs': False, 'crenellations': False},
               {'anyAngle': False, 'flow': False}]
    for ext in (False, True):
        for c in configs:
            suite(ext, c)
    print('%d checks, %d failed' % (COUNT[0], len(FAILS)))
    for f_ in FAILS:
        print('  ', f_)
    sys.exit(1 if FAILS else 0)

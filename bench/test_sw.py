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


def line4(x1, y1, x2, y2):
    out, x, y = [(x1, y1)], x1, y1
    dx, dy = x2 - x1, y2 - y1
    sx, sy = (-1 if dx < 0 else 1), (-1 if dy < 0 else 1)
    while (x, y) != (x2, y2):
        ex = abs(dx * (y - y1) - dy * (x + sx - x1))
        ey = abs(dx * (y + sy - y1) - dy * (x - x1))
        if y == y2 or (x != x2 and (ex < ey or (ex == ey and abs(x2 - x) >= abs(y2 - y)))):
            x += sx
        else:
            y += sy
        out.append((x, y))
    return out


def game_line4(x1, y1, x2, y2):
    out, x, y = [(x1, y1)], x1, y1
    while (x, y) != (x2, y2):
        if abs(x2 - x) > abs(y2 - y):
            x += 1 if x < x2 else -1
        else:
            y += 1 if y < y2 else -1
        out.append((x, y))
    return out


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
        H.stub(call(v + 0xFB), 1, 8)                  # isTileEnclosedByWallsOrGates (stairs start)
        H.stub(call(v + 0x10C), 98, 8)                # getMaxWallHeightInBrushArea
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

    DATA = [x for x, n in H.allocations if n == 0x100 + 4 * 2048][0]

    def reset():
        H.put32(DATA + 0x20, MASK)        # the cached drag: the map changes under it here
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

    # G. an undamaged wall in the way is gone around, a damaged one is walked over
    around = config.get('aroundWalls', True) and flow
    reset()
    old = {(106, y) for y in range(96, 109)}
    for x, y in old:
        H.put32(FLAGS + 4 * tile(x, y), 0x100); H.put8(LIVE + tile(x, y), 98)
    g = (100, 102, 112, 102)
    run_validate(*g)
    run_place(*g)
    got = walls() - old
    if around:
        check(tag + ' G new wall', len(got) > 10, True)
        check(tag + ' G old wall untouched', all(H.m.read(LIVE + tile(x, y), 1)[0] == 98 for x, y in old), True)
        check(tag + ' G goes around the end', any(y in (95, 109) for _, y in got), True)
    else:
        want = set(bresenham(*g) if any_angle else game_line(*g)) - old
        check(tag + ' G crosses the wall', got, want)
    # a diagonal wall may not be squeezed through
    reset()
    diag = {(105 + i, 98 + i) for i in range(10)}
    for x, y in diag:
        H.put32(FLAGS + 4 * tile(x, y), 0x100)
    g = (106, 104, 112, 102)   # from below the diagonal to above it
    run_place(*g)
    got = walls() - diag
    if around:
        data = [x for x, n in H.allocations if n == 0x100 + 4 * 2048][0]
        route = [(H.u16(data + 0x100 + 4 * i), H.u16(data + 0x102 + 4 * i)) for i in range(H.u32(data + 0x40))]
        check(tag + ' G route ends', (route[0], route[-1]), ((106, 104), (112, 102)))
        cross = any(q[0] != p[0] and q[1] != p[1] and (q[0], p[1]) in diag and (p[0], q[1]) in diag
                    for p, q in zip(route, route[1:]))
        check(tag + ' G no squeeze through a diagonal', cross, False)
        check(tag + ' G route is the wall', set(route) - diag, got)
    # a damaged wall is walked over and repaired
    reset()
    for x, y in old:
        H.put32(FLAGS + 4 * tile(x, y), 0x100); H.put8(LIVE + tile(x, y), 60); H.put8(DMG + tile(x, y), 38)
    g = (100, 102, 112, 102)
    run_place(*g)
    check(tag + ' G damaged wall repaired', H.m.read(LIVE + tile(106, 102), 1)[0], 98)
    check(tag + ' G straight through it', max(abs(y - 102) for x, y in walls() - old), 0)

    # H. stairs: straight steps, 16 lower each, around what is in the way
    reset()
    H.put32(TMS + 0x554984, 5000)
    for y in range(290, 311):
        H.put32(FLAGS + 4 * tile(300, y), 0x100); H.put8(LIVE + tile(300, y), 98)
    st = (301, 300, 306, 303)

    def stairs_placed():
        data = H.m.read(FLAGS, 4 * TILES)
        return {(t % 400, t // 400) for t in range(TILES) if data[4 * t + 1] & 8}

    def check_stairs(label, expect_line, blocked=()):
        check(tag + label + ' valid', run_validate(*st, mapper=0x1B), True)
        H.m.write(GFX, b'\0' * 2 * TILES)
        H.run(preview, until=preview + 0x3D4, regs=dict(ecx=TMS), stack=[1, *st, 0x1B])
        gfx = H.m.read(GFX, 2 * TILES)
        drawn = {(t % 400, t // 400) for t in range(TILES) if gfx[2 * t] or gfx[2 * t + 1]}
        run_place(*st, mapper=0x1B)
        got = stairs_placed()
        if expect_line is not None:
            check(tag + label + ' tiles', got, set(expect_line[:len(got)]))
        check(tag + label + ' five steps', len(got), 5)
        check(tag + label + ' preview = stairs', drawn, got)
        check(tag + label + ' nothing on the building', got & set(blocked), set())
        # straight steps only, each 16 lower than the one before
        order = sorted(got, key=lambda t: -H.m.read(LIVE + tile(*t), 1)[0])
        check(tag + label + ' first step', order[0], (301, 300))
        check(tag + label + ' straight steps', all(abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1
                                                   for a, b in zip(order, order[1:])), True)
        check(tag + label + ' heights', [H.m.read(LIVE + tile(*t), 1)[0] for t in order], [82, 66, 50, 34, 18])

    check_stairs(' H stairs', line4(*st) if any_angle else game_line4(*st))
    if flow:
        reset()
        H.put32(TMS + 0x554984, 5000)
        for y in range(290, 311):
            H.put32(FLAGS + 4 * tile(300, y), 0x100); H.put8(LIVE + tile(300, y), 98)
        line = line4(*st) if any_angle else game_line4(*st)
        blocked = [line[2]]
        for x, y in blocked:
            H.put16(BID + 2 * tile(x, y), 9)
        H.put32(DATA + 0x20, MASK)
        check_stairs(' H stairs around', None, blocked)

    # I. the raised part of a crenellation gets path links
    walkable = config.get('walkableCrenellations', True)
    link_self = f('F7 C3 00 00 40 00 0F 85 ? ? ? ?')
    links_of = link_self - 0xE0
    LINKS = TMS + 0x38B2F0
    reset()
    m = tile(250, 250)
    H.put32(FLAGS + 4 * m, 0x400300); H.put8(LIVE + m, 106)
    for x, y in ((249, 250), (251, 250)):
        H.put32(FLAGS + 4 * tile(x, y), 0x300); H.put8(LIVE + tile(x, y), 106)
    for x in range(248, 253):
        H.put32(FLAGS + 4 * tile(x, 251), 0x100); H.put8(LIVE + tile(x, 251), 98)
    H.put8(LINKS + m, 0x55)
    H.run(links_of, regs=dict(ecx=0x12345678), stack=[250, m])
    check(tag + ' I raised part linked', H.m.read(LINKS + m, 1)[0] != 0, walkable)
    H.run(links_of, regs=dict(ecx=0x12345678), stack=[250, tile(249, 250)])
    check(tag + ' I neighbour links to it', bool(H.m.read(LINKS + tile(249, 250), 1)[0] & 0x04), walkable)

    # J. a unit that stops on it is moved to the nearest wall tile
    if walkable:
        tick_site = f('83 C2 01 89 16 8B 15 ? ? ? ? 69 D2 90 04 00 00 33 C9 66 89 8C 32 AE 09 00 00')
        TICKS = E.u32(f('8B 87 50 0A 00 00 8B 8F 98 09 00 00 8B 15') + 14)
        set_pos = f('53 8B 5C 24 0C 81 FB 8F 01 00 00 55 8B E9 0F 87')
        STATE = 0x145CA28 if ext else 0x1387F38
        AREAS = TMS + 0x363ED0
        u = STATE + 0x614 + 5 * 0x490
        moved = []
        H.exposed[set_pos] = lambda *a: moved.append(a) or 1
        for x in range(248, 253):
            H.put8(LINKS + tile(x, 251), 0xFF); H.put16(AREAS + 2 * tile(x, 251), 3)
        H.put16(AREAS + 2 * m, 3); H.put8(LINKS + tile(249, 250), 0)
        H.put32(u + 0xD4, m); H.put16(u + 0xC4, 250); H.put16(u + 0xC6, 250); H.put16(u + 0xF6, 0)
        H.put32(TICKS, 11)                      # 11 + 5 = 16: this unit's turn
        regs = dict(eax=0xA1, ebx=0xB2, ecx=0xC3, edx=5, esi=STATE, edi=0xD4, ebp=0xE5)
        cpu = H.run(tick_site, until=tick_site + 5, regs=regs)
        check(tag + ' J moved', moved, [(STATE, 5, 250, 251, 98)])
        check(tag + ' J registers', [cpu.r[r] for r in ('eax', 'ebx', 'ecx', 'edx', 'edi', 'ebp')],
              [0xA1, 0xB2, 0xC3, 6, 0xD4, 0xE5])
        check(tag + ' J cursor', H.u32(STATE), 6)
        check(tag + ' J stays there', (H.u16(u + 0xEC), H.u16(u + 0xEE), H.u16(u + 0xC8), H.u16(u + 0xCA),
                                       H.u32(u + 0xD8)), (250, 251, 250, 251, tile(250, 251)))
        moved.clear()
        H.put16(u + 0xF6, 2)
        H.run(tick_site, until=tick_site + 5, regs=regs)
        check(tag + ' J walking over it', moved, [])
        H.put16(u + 0xF6, 0); H.put32(TICKS, 12)
        H.run(tick_site, until=tick_site + 5, regs=regs)
        check(tag + ' J not its turn', moved, [])

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
    configs = [{}, {'anyAngle': False}, {'flow': False}, {'aroundWalls': False},
               {'walkableCrenellations': False}, {'stairs': False, 'crenellations': False},
               {'anyAngle': False, 'flow': False}]
    for ext in (False, True):
        for c in configs:
            suite(ext, c)
    print('%d checks, %d failed' % (COUNT[0], len(FAILS)))
    for f_ in FAILS:
        print('  ', f_)
    sys.exit(1 if FAILS else 0)

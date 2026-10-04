"""Experiment: the game's own move order (giveTribeMoveInstruction) for one assassin onto the top
of a wall that has no stairs, run in the emulator with the module on and off. VAN only."""
import struct, sys
import test_sw as T
from harness import MASK, SENTINEL

TMS = 0x1A93208
FLAGS, LIVE, BASE, LINKS, AREAS = (TMS + 0x165160, TMS + 0x29FA30, TMS + 0x2B3440, TMS + 0x38B2F0,
                                   TMS + 0x363ED0)
UNITS = 0x1387F38 + 0x614
TRIBES = 0x1667F78
ORDER = 0x5263A0
DIRS = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
tile = lambda x, y: y * 400 + x


def scene(H, wall, crenels=()):
    E = H.E
    valid = E.u32(E.find('83 EC 20 33 C0 39 05 ? ? ? ? 8B D1')[0] + 0x7A)
    rows = E.u32(E.find('83 EC 20 33 C0 39 05 ? ? ? ? 8B D1')[0] + 0xD1)
    ycomp = E.u32(E.find('83 EC 10 53 55 8B 6C 24 1C 56 69 ED 90 04 00 00')[0] + 0x2E)
    for y in range(400):
        H.put32(rows + 12 * y, y * 400)
        for k, d in enumerate((-400, -399, 1, 401, 400, 399, -1, -401)):
            H.put32(TMS + 32 * y + 4 * k, d & MASK)
    H.m.write(valid, b'\x01' * 160000)
    H.m.write(ycomp, b''.join(struct.pack('<H', t // 400) for t in range(160000)))
    H.m.write(BASE, b'\x08' * 160000); H.m.write(LIVE, b'\x08' * 160000)
    top = set(wall) | set(crenels)
    for x, y in wall:
        H.put32(FLAGS + 4 * tile(x, y), 0x100); H.put8(LIVE + tile(x, y), 98)
    for x, y in crenels:
        raised = (x & 1) != (y & 1)
        H.put32(FLAGS + 4 * tile(x, y), 0x400300 if raised else 0x300); H.put8(LIVE + tile(x, y), 106)
    for y in range(60, 141):
        for x in range(60, 141):
            here = (x, y) in top
            flags_here = H.u32(FLAGS + 4 * tile(x, y))
            bits = 0
            if not flags_here & 0x400000:
                for k, (dx, dy) in enumerate(DIRS):
                    n = (x + dx, y + dy)
                    if (n in top) == here and not H.u32(FLAGS + 4 * tile(*n)) & 0x400000:
                        bits |= 1 << k
            H.put8(LINKS + tile(x, y), bits)
            area = 0 if flags_here & 0x400000 else (2 if here else 1)
            H.put16(AREAS + 2 * tile(x, y), area)


def assassin(H, uid, x, y, tribe):
    u = UNITS + uid * 0x490
    H.put16(u + 0x8C, 2); H.put16(u + 0x8E, 0x49); H.put16(u + 0x96, 1)
    H.put16(u + 0xC4, x); H.put16(u + 0xC6, y); H.put32(u + 0xD4, tile(x, y))
    H.put16(u + 0x2A0, 0); H.put16(u + 0x2D8, tribe)
    t = TRIBES + tribe * 0x334
    H.put16(t + 0x40, 2); H.put16(t + 0x5A, uid); H.put16(t + 0x5C, 1)
    H.put16(t + 0x60 + 2 * (uid // 16), 1 << (uid % 16))


def order(config, target, wall, crenels=()):
    H = T.Bench(extreme=False, config=config)
    sent = []
    H.stub(0x53D3D0, 1, 0x10, record=sent)          # setDestinationForUnit
    H.stub(0x490340, 0, 0)                           # throttledMultiplayerSyncUpdate
    H.stub(0x524EF0, 0, 8)                           # applyUnitTopSpeedDelayBasedOnTribeSize
    scene(H, wall, crenels)
    assassin(H, 5, 100, 90, 3)
    try:
        cpu = H.run(ORDER, regs=dict(ecx=TRIBES), stack=[3, target[0], target[1], 0, 0, 0], limit=20_000_000)
        result = cpu.r['eax']
    except Exception as e:
        result = 'crash: %s' % str(e)[:120]
    return result, [(a[1][0], a[1][1] % 0x10000, a[1][2] % 0x10000) for a in sent], H


if __name__ == '__main__':
    wall = [(x, 100) for x in range(90, 111)]
    crenels = [(x, 99) for x in range(90, 111)]
    off = dict(anyAngle=False, flow=False, aroundWalls=False, stairs=False, crenellations=False,
               walkableCrenellations=False, diagonalSiege=False, crenellationHeights=False)
    for name, cfg in (('module off', off), ('module on', {})):
        for label, cren in (('plain wall', ()), ('crenellated wall', crenels)):
            r, sent, H = order(cfg, (100, 100), wall, cren)
            u = UNITS + 5 * 0x490
            planned = (H.u16(u + 0x2DC), H.u16(u + 0x2DE))
            print('%-10s %-17s order %r, setDestination %r, planned %r, dest %r' % (
                name, label, r, sent, planned, (H.u16(u + 0xC8), H.u16(u + 0xCA))))

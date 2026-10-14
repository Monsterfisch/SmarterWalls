"""Experiment: a staircase whose last step is at ground height ("stair 6"), links built by the
game's own link builder, then checked for one-way links (A -> B linked, B -> A not)."""
import struct
import test_sw as T
from harness import MASK
import exp_assassin_order as X

TMS = 0x1A93208
FLAGS, LIVE, BASE, LINKS, DMG = (TMS + 0x165160, TMS + 0x29FA30, TMS + 0x2B3440, TMS + 0x38B2F0,
                                 TMS + 0x3290A0)
DIRS = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
tile = lambda x, y: y * 400 + x


def build(config, scene):
    H = T.Bench(extreme=False, config=config)
    E = H.E
    X.scene(H, [])                                   # rows, valid, neighbour table, flat ground
    for (x, y), flags, live in scene:
        H.put32(FLAGS + 4 * tile(x, y), flags); H.put8(LIVE + tile(x, y), live)
    builder = E.find('F7 C3 00 00 40 00 0F 85 ? ? ? ?')[0] - 0xE0
    pf = E.u32(E.find('83 EC 10 53 55 8B 6C 24 1C 56 69 ED 90 04 00 00')[0] + 0x5B)
    xs = [p[0][0] for p in scene]; ys = [p[0][1] for p in scene]
    box = (min(xs) - 3, max(xs) + 3, min(ys) - 3, max(ys) + 3)
    for y in range(box[2], box[3] + 1):
        for x in range(box[0], box[1] + 1):
            H.run(builder, regs=dict(ecx=pf), stack=[y, tile(x, y)])
    return H, box


def one_way(H, box):
    out = []
    for y in range(box[2] + 1, box[3]):
        for x in range(box[0] + 1, box[1]):
            links = H.m.read(LINKS + tile(x, y), 1)[0]
            for k, (dx, dy) in enumerate(DIRS):
                back = H.m.read(LINKS + tile(x + dx, y + dy), 1)[0]
                if bool(links & (1 << k)) != bool(back & (1 << ((k + 4) % 8))):
                    out.append(((x, y), (x + dx, y + dy), 'there' if links & (1 << k) else 'back'))
    return out


def staircase(base_wall=98, crenel=True, steps=6):
    scene = [((x, 100), 0x100, base_wall) for x in range(94, 107)]
    if crenel:
        scene += [((x, 99), 0x400300 if (x & 1) != (99 & 1) else 0x300, base_wall + 8) for x in range(94, 107)]
    top = base_wall + (8 if crenel else 0)
    for i in range(steps):
        h = top - 16 * (i + 1)
        if h <= 8:
            break
        scene.append(((100, 101 + i), 0x900, h))
    return scene


if __name__ == '__main__':
    for label, cfg in (('module off', dict(anyAngle=False, flow=False, aroundWalls=False, stairs=False,
                        crenellations=False, walkableCrenellations=False, diagonalSiege=False,
                        crenellationHeights=False)), ('module on', {})):
        for name, sc in (('stairs off a crenellated wall (6 steps)', staircase()),
                         ('stairs off a plain wall (5 steps)', staircase(crenel=False))):
            H, box = build(cfg, sc)
            heights = [(p[0], p[2]) for p in sc if p[1] == 0x900]
            print(label, '|', name, '| steps:', heights)
            for a, b, way in one_way(H, box):
                print('    one-way link', a, '->', b, '(only %s)' % way,
                      'flags %X/%X heights %d/%d' % (H.u32(FLAGS + 4 * tile(*a)), H.u32(FLAGS + 4 * tile(*b)),
                                                     H.m.read(LIVE + tile(*a), 1)[0], H.m.read(LIVE + tile(*b), 1)[0]))

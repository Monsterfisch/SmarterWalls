"""Experiment: a siege tower docked in front of a wall with N rows of crenellations. Links come
from the game's own link builder (with this module's hooks), plus the forced cross the game ORs
in every tick for a placed tower. Then: can a unit on the tower reach the plain wall?"""
from collections import deque
import exp_stair6 as S

TOWER_ID = 7
B_TYPE = 0xF98606          # building 0's type word (VAN), stride 0x32C


def scene(rows, wall_h=98, crenel_h=106, tower_h=106):
    sc = [((x, 100), 0x100, wall_h) for x in range(90, 111)]
    for r in range(1, rows + 1):
        y = 100 - r
        # as the game lays it out: the row beside the wall alternates, every row further out is raised
        sc += [((x, y), 0x400300 if r > 1 or (x + y) & 1 else 0x300, crenel_h) for x in range(90, 111)]
    front = 100 - rows - 1                           # tower footprint rows front-2 .. front
    return sc, (99, front - 2)                       # footprint top-left (x 99..101)


def run(rows, cfg, fx_shift=0):
    sc, (bx, by) = scene(rows)
    bx += fx_shift
    tower = [((x, y), 0x10000000, 106) for y in range(by, by + 3) for x in range(bx, bx + 3)]
    H, box = S.build_pre(cfg, sc + tower, lambda H: (
        [H.put16(S.TMS + 0x2029B0 + 2 * S.tile(x, y), TOWER_ID) for (x, y), _, _ in tower],
        H.put16(B_TYPE + TOWER_ID * 0x32C, 0x45)))
    L = lambda t: H.m.read(S.LINKS + t, 1)[0]
    def orl(x, y, v):
        H.put8(S.LINKS + S.tile(x, y), L(S.tile(x, y)) | v)
    cx = bx + 1                                      # the game's forced cross
    orl(cx, by - 1, 0x10); orl(cx, by, 0x11); orl(cx, by + 2, 0x11); orl(cx, by + 3, 0x01)
    orl(bx - 1, by + 1, 0x04); orl(bx, by + 1, 0x44); orl(bx + 2, by + 1, 0x44); orl(bx + 3, by + 1, 0x40)
    start = (cx, by + 1)
    seen = {start}; q = deque([start])
    while q:
        x, y = q.popleft()
        for k, (dx, dy) in enumerate(S.DIRS):
            n = (x + dx, y + dy)
            if L(S.tile(x, y)) >> k & 1 and n not in seen and box[0] <= n[0] <= box[1] and box[2] <= n[1] <= box[3]:
                seen.add(n); q.append(n)
    wall = sorted(p for p in seen if p[1] == 100)
    return H, box, seen, wall


if __name__ == '__main__':
    for rows in (1, 2, 3, 4):
        for shift in (0, 1):
            H, box, seen, wall = run(rows, {}, shift)
            front = 100 - rows - 1 - 2
            print('rows %d tower x %d: reaches %d wall tiles; crenel tiles reached per row: %s' % (
                rows, 99 + shift, len(wall), [sum(1 for p in seen if p[1] == 100 - r) for r in range(1, rows + 1)]))
            if not wall:
                for y in range(100 - rows - 1, 101):
                    print('      %3d ' % y + ' '.join('%02X' % H.m.read(S.LINKS + S.tile(x, y), 1)[0] for x in range(95, 106)))

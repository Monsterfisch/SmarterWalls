import exp_stair6 as S
from harness import SENTINEL
tile = S.tile
OFF = dict(anyAngle=False, flow=False, aroundWalls=False, stairs=False, crenellations=False,
           walkableCrenellations=False, diagonalSiege=False, crenellationHeights=False)
def scene(wall_h=12, stair_h=10):
    # W1 G / S W2: two walls touching diagonally, stairs in one corner, ground in the other
    return [((100, 100), 0x100, wall_h), ((101, 101), 0x100, wall_h), ((100, 101), 0x900, stair_h),
            ((99, 99), 0x100, wall_h), ((102, 102), 0x100, wall_h)]          # the wall carries on diagonally
for label, cfg in (('module off', OFF), ('module on', {})):
    for wh in (12, 98):
        H, box = S.build(cfg, scene(wall_h=wh))
        s, g = tile(100, 101), tile(101, 100)
        ls, lg = H.m.read(S.LINKS + s, 1)[0], H.m.read(S.LINKS + g, 1)[0]
        print('%s, walls %d high: stair->ground(NE) %s, ground->stair(SW) %s' % (
            label, wh, bool(ls & 0x02), bool(lg & 0x20)))
        PF = 0x12BB8C8; fails = []
        H.cpu.hooks[0x4A97D0 + 0x30A] = lambda cpu: (fails.append(1), setattr(cpu, 'eip', SENTINEL))
        for a, b in (((100, 101), (101, 100)), ((101, 100), (100, 101))):
            del fails[:]; H.put32(PF + 0x1BB3C, 0)
            found = H.run(0x497B80, regs=dict(ecx=PF), stack=[a[0], a[1], b[0], b[1], 100000, 0]).r['eax']
            r = 'no route'
            if found:
                H.run(0x4A97D0, regs=dict(ecx=PF), stack=[a[0], a[1], b[0], b[1], 1])
                r = 'WALK-BACK FAILED (rebuilds every link)' if fails else 'ok, %d steps' % H.u32(PF + 0x1BB3C)
            print('    route', a, '->', b, ':', r)

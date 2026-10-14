import exp_stair6 as S
from harness import SENTINEL
tile = S.tile
OFF = dict(anyAngle=False, flow=False, aroundWalls=False, stairs=False, crenellations=False,
           walkableCrenellations=False, diagonalSiege=False, crenellationHeights=False)
WALL, STAIR = (0x100, 12), (0x900, 10)
for n1, w1 in (('wall', WALL), ('stair6', STAIR)):
    for n2, w2 in (('wall', WALL), ('stair6', STAIR)):
        sc = [((100, 100),) + w1, ((101, 101),) + w2, ((100, 101), 0x900, 10),
              ((99, 99),) + w1, ((102, 102),) + w2]
        H, box = S.build(OFF, sc)
        s, g = tile(100, 101), tile(101, 100)
        ls, lg = H.m.read(S.LINKS + s, 1)[0], H.m.read(S.LINKS + g, 1)[0]
        PF = 0x12BB8C8; fails = []
        H.cpu.hooks[0x4A97D0 + 0x30A] = lambda cpu: (fails.append(1), setattr(cpu, 'eip', SENTINEL))
        H.put32(PF + 0x1BB3C, 0)
        found = H.run(0x497B80, regs=dict(ecx=PF), stack=[100, 101, 101, 100, 100000, 0]).r['eax']
        steps = None
        if found:
            H.run(0x4A97D0, regs=dict(ecx=PF), stack=[100, 101, 101, 100, 1])
            steps = H.u32(PF + 0x1BB3C)
        stuck = found and steps == 1 and not (ls & 0x02)
        print('W1 %-6s W2 %-6s: stair->ground %-5s ground->stair %-5s route %s%s' % (
            n1, n2, bool(ls & 0x02), bool(lg & 0x20), steps, '  <- STUCK (route step has no link)' if stuck else ''))

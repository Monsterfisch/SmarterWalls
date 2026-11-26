"""Thick crenellation: closed while its wall is too damaged to walk, reopened all the way out
when one wall tile is repaired and the game relinks it (the module's relink wrapper)."""
import exp_stair6 as S
import exp_tower_rows as R

RELINK = 0x4A5F90   # updatePathLinkagesInAllEightDirections (VAN), hooked by the module

def linked_rows(H, rows, xs=range(95, 106)):
    return [sum(1 for x in xs if H.m.read(S.LINKS + S.tile(x, 100 - r), 1)[0]) for r in range(1, rows + 1)]

rows = 4
sc, _ = R.scene(rows)
H, box = S.build_pre({}, sc, lambda H: [H.put8(S.DMG + S.tile(x, y), 0x30) for x in range(90, 111) for y in (99, 100)])
print('wall + row 1 damaged: raised rows with links (row 1 has its plain crenels):', linked_rows(H, rows))
H.put8(S.DMG + S.tile(101, 99), 0)   # a plain crenel beside the wall
pf = H.E.u32(H.E.find('83 EC 10 53 55 8B 6C 24 1C 56 69 ED 90 04 00 00')[0] + 0x5B)
H.run(RELINK, regs=dict(ecx=pf), stack=[99, S.tile(101, 99)])
print('one row-1 crenel repaired + relinked:', linked_rows(H, rows))

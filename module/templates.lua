-- FASM sources. Upper-case names are filled in by init.lua.
local templates = {}

-- At the start of validateWallBuildPath, renderWallDragPreview and placeWalls (all thiscall,
-- args: player, x1, y1, x2, y2, mapper[, budget]). Hands the drag to PREPARE and switches
-- this function's own path walk on when a route is ready.
templates.entry = [[
  pushad
  mov ebx, STATE
  mov dword [ebx + 0x78], -1
  xor eax, eax
  mov [ebx + ACTIVE], eax
  mov [ebx + IDX], eax
  mov [ebx + 0x7C], eax
  movzx eax, word [esp + 0x38]
  cmp eax, 0x19
  je wanted
  cmp eax, 0x2E
  je wanted
  cmp eax, 0x1A
  je wanted
  cmp eax, 0x1B
  jne skip
  mov dword [ebx + 0x7C], 1
wanted:
  mov [ebx + 0x10], eax
  mov eax, [esp + 0x24]
  mov [ebx + 0x14], eax
  mov eax, [esp + 0x28]
  mov [ebx], eax
  mov eax, [esp + 0x2C]
  mov [ebx + 4], eax
  mov eax, [esp + 0x30]
  mov [ebx + 8], eax
  mov eax, [esp + 0x34]
  mov [ebx + 0xC], eax
  mov [ebx + 0x18], ecx
  mov dword [ebx + 0x1C], FRESH
  call PREPARE
  mov ebx, STATE
  mov [ebx + ACTIVE], eax
skip:
  popad
  ORIGINAL
  jmp RESUME
]]

-- placeWalls' start when only the repairs are switched on: forget the last repaired tile.
templates.placeEntry = [[
  mov dword [STATE + 0x78], -1
  ORIGINAL
  jmp RESUME
]]

-- Reuses the last route while the drag has not changed (and is not too old), else asks lua.
-- in: ebx = STATE. out: eax = 1 if a route is ready. Changes everything but esp.
templates.prepare = [[
  cmp dword [ebx + 0x1C], 0
  jne compute
  mov eax, [ebx]
  cmp eax, [ebx + 0x20]
  jne compute
  mov eax, [ebx + 4]
  cmp eax, [ebx + 0x24]
  jne compute
  mov eax, [ebx + 8]
  cmp eax, [ebx + 0x28]
  jne compute
  mov eax, [ebx + 0xC]
  cmp eax, [ebx + 0x2C]
  jne compute
  mov eax, [ebx + 0x10]
  cmp eax, [ebx + 0x30]
  jne compute
  mov eax, [ebx + 0x14]
  cmp eax, [ebx + 0x34]
  jne compute
  inc dword [ebx + 0x3C]
  cmp dword [ebx + 0x3C], MAX_AGE
  ja compute
  mov eax, [ebx + 0x38]
  ret
compute:
  mov eax, [ebx]
  mov [ebx + 0x20], eax
  mov eax, [ebx + 4]
  mov [ebx + 0x24], eax
  mov eax, [ebx + 8]
  mov [ebx + 0x28], eax
  mov eax, [ebx + 0xC]
  mov [ebx + 0x2C], eax
  mov eax, [ebx + 0x10]
  mov [ebx + 0x30], eax
  mov eax, [ebx + 0x14]
  mov [ebx + 0x34], eax
  mov dword [ebx + 0x3C], 0
  mov dword [ebx + 0x38], 0
  call ROUTE
  mov ebx, STATE
  mov eax, [ebx + 0x38]
  ret
]]

-- The three steps below also lower the stairs' height by 16 a tile, as the game's own steps
-- do, when the drag is stairs ([STATE+0x7C] set by the entry hook).

-- validateWallBuildPath's step to the next tile: edi = x, esi = y, [esp+0x14] = row pointer,
-- [esp+0x24] = the stairs' height.
templates.validateStep = [[
  cmp dword [STATE + ACTIVE], 0
  je vanilla
  mov eax, [STATE + IDX]
  inc eax
  mov [STATE + IDX], eax
  cmp eax, [STATE + COUNT]
  jge finished
  movzx edi, word [STATE + PATH + eax*4]
  movzx esi, word [STATE + PATH + eax*4 + 2]
  lea eax, [esi + esi*2]
  lea eax, [ROWS + eax*4]
  mov [esp + 0x14], eax
  cmp dword [STATE + 0x7C], 0
  je go
  cmp dword [esp + 0x24], 0x10
  jle go
  sub dword [esp + 0x24], 0x10
go:
  jmp TOP
finished:
  jmp DONE
vanilla:
  mov ebp, [esp + 0x40]
  cmp edi, ebp
  jmp RESUME
]]

-- placeWalls' step: [esp+0x20] = x (also esi), [esp+0x44] = y, [esp+0x14] = row pointer,
-- [esp+0x24] = the stairs' height.
templates.placeStep = [[
  cmp dword [STATE + ACTIVE], 0
  je vanilla
  mov eax, [STATE + IDX]
  inc eax
  mov [STATE + IDX], eax
  cmp eax, [STATE + COUNT]
  jge finished
  movzx esi, word [STATE + PATH + eax*4]
  mov [esp + 0x20], esi
  movzx ecx, word [STATE + PATH + eax*4 + 2]
  mov [esp + 0x44], ecx
  lea ecx, [ecx + ecx*2]
  lea ecx, [ROWS + ecx*4]
  mov [esp + 0x14], ecx
  cmp dword [STATE + 0x7C], 0
  je go
  cmp dword [esp + 0x24], 0x10
  jl go
  sub dword [esp + 0x24], 0x10
go:
  jmp TOP
finished:
  jmp DONE
vanilla:
  mov esi, [esp + 0x20]
  mov ebp, [esp + 0x48]
  jmp RESUME
]]

-- renderWallDragPreview's step: ebx = [esp+0x1C] = x, edi = y, [esp+0x10] = row pointer,
-- [esp+0x20] = the stairs' height, ecx = TileMapState and must survive.
templates.previewStep = [[
  cmp dword [STATE + ACTIVE], 0
  je vanilla
  mov eax, [STATE + IDX]
  inc eax
  mov [STATE + IDX], eax
  cmp eax, [STATE + COUNT]
  jge finished
  movzx ebx, word [STATE + PATH + eax*4]
  mov [esp + 0x1C], ebx
  movzx edi, word [STATE + PATH + eax*4 + 2]
  lea eax, [edi + edi*2]
  lea eax, [ROWS + eax*4]
  mov [esp + 0x10], eax
  cmp dword [STATE + 0x7C], 0
  je go
  cmp dword [esp + 0x20], 0x10
  jle go
  sub dword [esp + 0x20], 0x10
go:
  jmp TOP
finished:
  jmp DONE
vanilla:
  mov ebx, [esp + 0x1C]
  cmp ebx, [esp + 0x34]
  jmp RESUME
]]

-- placeWalls, a tile that is a wall or damaged and about to be (re)built:
-- esi = tile, edi = TileMapState, dx = mapper, [esp+0x20] = x, [esp+0x44] = y,
-- ebx/ebp = the game's "new tile" and
-- "crenellation turns into wall" flags. Lua decides whether a damaged staircase or
-- crenellation is put back as it was instead.
-- R_RESULT: 0 = as the game does it, 1 = stairs put back (costs a tile), 2 = crenellation
-- put back (free, like the game's own crenellation-to-wall change), 3 = leave the tile alone
-- (the game walks a one-tile wall twice; the second time must not undo the repair).
templates.restore = [[
  cmp dx, 0x19
  je known
  cmp dx, 0x2E
  jne vanilla
  cmp dword [STATE + 0xB0], 0
  je vanilla
  test dword [edi + esi*4 + FLAGS_OFF], 0x800
  jz vanilla
known:
  test dword [edi + esi*4 + FLAGS_OFF], 0xA00
  jz vanilla
  push eax
  mov eax, [esp + 0x24]
  mov [STATE + 0x70], eax
  mov eax, [esp + 0x48]
  mov [STATE + 0x74], eax
  push ecx
  push edx
  mov [STATE + 0x60], esi
  mov [STATE + 0x64], edi
  mov dword [STATE + 0x68], 0
  call REPAIR
  pop edx
  pop ecx
  pop eax
  mov ecx, [STATE + 0x68]
  test ecx, ecx
  jz vanilla
  cmp ecx, 3
  je alone
  mov al, [STATE + 0x6C]
  mov [esi + edi + LIVE_OFF], al
  mov byte [esi + edi + DAMAGE_OFF], 0
  mov byte [esi + RECORD], 0
  cmp ecx, 1
  jne crenel
  test dword [edi + esi*4 + FLAGS_OFF], 0x10000
  jz counted
  mov dword [esp + 0x34], 1
counted:
  mov ebx, 1
  xor ebp, ebp
  jmp STAIRS_BUILT
crenel:
  jmp FREE_BUILT
alone:
  jmp SKIP
vanilla:
  mov byte [esi + RECORD], 0
  cmp byte [esi + edi + DAMAGE_OFF], 0
  jne DAMAGED
  jmp UNDAMAGED
]]

-- processDamageToBuilding, wall branch, before the first hit knocks the top off:
-- ebx = tile, edi = TileMapState, eax is live. Remembers a staircase's height before damage.
templates.record = [[
  cmp byte [ebx + edi + DAMAGE_OFF], 0
  jne done
  test dword [edi + ebx*4 + FLAGS_OFF], 0x800
  jz done
  push eax
  mov al, [ebx + edi + LIVE_OFF]
  cmp al, [ebx + RECORD]
  jbe keep
  mov [ebx + RECORD], al
keep:
  pop eax
done:
  mov edx, [SCRATCH]
  jmp RESUME
]]

-- processDamageToBuilding, the wall tile is gone: forget its height.
templates.forget = [[
  mov byte [ebx + RECORD], 0
  and dword [edi + ebx*4 + FLAGS_OFF], 0xFFBEF4FF
  jmp RESUME
]]

-- updateUnits, every live unit before its update: edx = unit id, esi = UnitsState.
-- Every 16 ticks per unit: a unit on the raised part of a crenellation has its checks on that
-- tile counted (COUNTS / LAST per unit id). A unit standing still (move status +0xF6 = 0)
-- with no climb on its route (+0x294) is handed to lua at the first check; one using a
-- ladder or still walking only after LONG checks, so troops queueing for a ladder down get
-- time. Replays add edx, 1 / mov [esi], edx.
templates.unitTick = [[
  pushad
  cmp edx, MAX_UNITS
  jae done
  mov eax, [TICKS]
  add eax, edx
  test eax, 15
  jnz done
  imul eax, edx, 0x490
  lea edi, [esi + eax + UNITS_OFF]
  mov ecx, [edi + 0xD4]
  cmp ecx, TILES
  jae off
  mov eax, [FLAGS + ecx*4]
  and eax, 0x400100
  cmp eax, 0x400100
  je raised
off:
  mov byte [COUNTS + edx], 0
  jmp done
raised:
  cmp [LAST + edx*4], ecx
  je same
  mov [LAST + edx*4], ecx
  mov byte [COUNTS + edx], 0
same:
  movzx eax, byte [COUNTS + edx]
  cmp eax, 255
  jae counted
  inc eax
  mov [COUNTS + edx], al
counted:
  mov ebx, 1
  cmp word [edi + 0x294], 0
  jne slow
  cmp word [edi + 0xF6], 0
  je limit
slow:
  mov ebx, LONG
limit:
  cmp eax, ebx
  jb done
  mov byte [COUNTS + edx], 0
  mov [STATE + 0x94], ebx
  mov [STATE + 0x80], edx
  mov [STATE + 0x84], esi
  call PUSH_OFF
done:
  popad
  add edx, 1
  mov [esi], edx
  jmp RESUME
]]

-- UnitsState::findFreeTileNearby(unit, wallTile), the spot a siege tower docks on: the game's
-- own search first; when it finds nothing, lua tries the diagonal spots.
templates.freeTile = [[
  push dword [esp + 8]
  push dword [esp + 8]
  call GAME_SEARCH
  test eax, eax
  jnz done
  push ecx
  push edx
  mov eax, [esp + 0xC]
  mov [STATE + 0x88], eax
  mov eax, [esp + 0x10]
  mov [STATE + 0x8C], eax
  mov dword [STATE + 0x90], 0
  call DIAGONAL
  pop edx
  pop ecx
  mov eax, [STATE + 0x90]
done:
  ret 8
]]

-- The game's findFreeTileNearby, its first 9 bytes replayed.
templates.freeTileGame = [[
  sub esp, 0x10
  push ebx
  push ebp
  mov ebp, [esp + 0x1C]
  jmp RESUME
]]

-- placeWalls, a new crenellation: replaces call hasOnlyTowerNeighborsNoWalls(tile, y), whose two
-- arguments are already pushed. esi = tile, edi = TileMapState, [esp+0x20] = x, [esp+0x44] = y
-- once the arguments are dropped. Lua works out the height; 0 = the game's own choice.
templates.crenelHeight = [[
  add esp, 8
  push eax
  push ecx
  push edx
  mov [STATE + 0x98], esi
  mov [STATE + 0x9C], edi
  mov eax, [esp + 0x2C]
  mov [STATE + 0xA0], eax
  mov eax, [esp + 0x50]
  mov [STATE + 0xA4], eax
  mov dword [STATE + 0xA8], 0
  mov dword [STATE + 0xAC], 0
  call HEIGHT
  pop edx
  pop ecx
  pop eax
  mov eax, [STATE + 0xA8]
  test eax, eax
  jz vanilla
  mov [esi + edi + LIVE_OFF], al
  cmp dword [STATE + 0xAC], 0
  je tall
  mov dword [esp + 0x34], 1
tall:
  jmp PARITY
vanilla:
  push dword [STATE + 0xA4]
  push esi
  mov ecx, edi
  call TOWERS_ONLY
  jmp AFTER_CALL
]]

-- A group ordered onto a wall spreads out over the tiles its search found: pathFindingResultBased
-- takes wall tiles (test [tile flags], 0x10000100 / je skip). esi = tile. A raised crenellation
-- part answers "not a wall" so nobody is sent to stand on one. edx is free here.
templates.spreadWall = [[
  mov edx, [esi*4 + FLAGS]
  test edx, 0x400000
  jnz raised
  test edx, 0x10000100
  jmp RESUME
raised:
  xor edx, edx
  jmp RESUME
]]

-- Its fallback when no wall tile is left (findNextTileInExistingSearchThatIsModuloDistanceAway)
-- takes any tile: cmp ebp, 0xFA0 / jl take. edi = tile. Raised parts are skipped there too.
templates.spreadAny = [[
  test dword [edi*4 + FLAGS], 0x400000
  jnz skip
  cmp ebp, 0xFA0
  jl TAKE
skip:
  jmp NEXT
]]

-- setDestinationForUnit, once the target has passed the game's first checks: ebp = x, edi = y,
-- esi = the unit (UnitsState-relative). A target on the raised part of a crenellation is moved
-- to the nearest wall tile beside it (straight neighbours first; a plain wall tile before a
-- plain crenellation tile), so nothing - an order, a
-- formation, an idle unit making room, a patrol, the AI - ever sends a unit to stand there.
-- Passing over one on the way stays allowed. Replays movzx eax, word [esi+0x6D8].
templates.destination = [[
  cmp ebp, 400
  jae keep
  cmp edi, 400
  jae keep
  lea eax, [edi + edi*2]
  mov eax, [ROWS + eax*4]
  add eax, ebp
  test dword [FLAGS + eax*4], 0x400000
  jz keep
  push ebx
  push ecx
  push edx
  push 0x400202
  jmp pass
second:
  mov dword [esp], 0x400002
pass:
  xor ebx, ebx
next:
  mov ecx, ebp
  add ecx, [DIRECTIONS + ebx*8]
  mov edx, edi
  add edx, [DIRECTIONS + ebx*8 + 4]
  cmp ecx, 400
  jae skip
  cmp edx, 400
  jae skip
  imul eax, edx, 400
  cmp byte [VALID + eax + ecx], 0
  je skip
  lea eax, [edx + edx*2]
  mov eax, [ROWS + eax*4]
  add eax, ecx
  test dword [FLAGS + eax*4], 0x100
  jz skip
  push edx
  mov edx, [FLAGS + eax*4]
  test edx, [esp + 4]
  pop edx
  jnz skip
  cmp byte [LINKS + eax], 0
  je skip
  mov ebp, ecx
  mov edi, edx
  jmp found
skip:
  inc ebx
  cmp ebx, 8
  jb next
  cmp dword [esp], 0x400002
  jne second
found:
  add esp, 4
  pop edx
  pop ecx
  pop ebx
keep:
  movzx eax, word [esi + 0x6D8]
  jmp RESUME
]]

-- The link builder, a wall, stairs or tower tile: it takes its diagonal link away when the two
-- straight neighbours beside the diagonal are walls (and byte [esp+0x13], MASK). A ground tile
-- does that only when it cannot step onto either of them. With two low walls touching
-- diagonally and ground-level stairs in the corner, the ground gets a link onto the stairs but
-- not back: the route search plans the step, the step itself is refused, and the unit asks for
-- a new route every tick. Here the diagonal is taken away only when neither straight neighbour
-- is linked either, as for ground.
templates.diagonalCut = [[
  test byte [esp + 0x13], SIDES
  jnz keep
  and byte [esp + 0x13], MASK
keep:
  jmp RESUME
]]

-- Does this raised crenellation part touch a walkable wall? One of its eight neighbours is a wall,
-- stairs or crenellation tile (0x100) that is not itself a raised part or a stockpile (0x400002)
-- and not worn down past what the game still lets units walk on (damage byte <= 0x14, the
-- game's own test in the link builder). in: eax = tile. out: eax = 1 or 0. Keeps other registers.
templates.attached = [[
  push ebx
  push ecx
  push edx
  push esi
  mov esi, eax
  movzx ecx, word [TILE_Y + esi*2]
  shl ecx, 5
  add ecx, TMS
  xor ebx, ebx
next:
  mov eax, [ecx + ebx*4]
  add eax, esi
  mov edx, [FLAGS + eax*4]
  test edx, 0x100
  jz skip
  test edx, 0x400002
  jnz skip
  cmp byte [DAMAGE + eax], 0x14
  jle yes
skip:
  inc ebx
  cmp ebx, 8
  jb next
  xor eax, eax
  jmp finish
yes:
  mov eax, 1
finish:
  pop esi
  pop edx
  pop ecx
  pop ebx
  ret
]]

-- The link builder, the tile itself (ebx = flags, ecx = tile): the game gives a raised part no
-- links; here it keeps them unless it hangs off nothing walkable.
templates.linkSelf = [[
  test ebx, 0x400000
  jz plain
  push eax
  mov eax, ecx
  call ATTACHED
  test eax, eax
  pop eax
  jz closed
plain:
  jmp CONTINUE
closed:
  jmp NO_LINKS
]]

-- The link builder, a neighbour (eax = its flags, ecx = its tile): a raised part is no step to
-- take (the game's own branch) unless it is attached to a walkable wall.
templates.linkNeighbour = [[
  test eax, 0x400000
  jz plain
  push eax
  mov eax, ecx
  call ATTACHED
  test eax, eax
  pop eax
  jnz plain
  jmp RAISED
plain:
  jmp WALL
]]

-- updatePathLinkagesInAllEightDirections(y, tile): the game relinks the tile and its eight
-- neighbours. A neighbour that is a raised part also gets its own neighbours relinked, so a wall
-- going down or being repaired next to it opens or closes the ways onto it on both sides.
templates.relink = [[
  push dword [esp + 8]
  push dword [esp + 8]
  call GAME_RELINK
  pushad
  mov esi, [esp + 0x28]
  movzx edi, word [TILE_Y + esi*2]
  shl edi, 5
  add edi, TMS
  xor ebp, ebp
around:
  mov eax, [edi + ebp*4]
  add eax, esi
  test dword [FLAGS + eax*4], 0x400000
  jz further
  push ebp
  push edi
  mov ebx, eax
  movzx edi, word [TILE_Y + ebx*2]
  shl edi, 5
  add edi, TMS
  xor ebp, ebp
inner:
  mov eax, [edi + ebp*4]
  add eax, ebx
  movzx ecx, word [TILE_Y + eax*2]
  push eax
  push ecx
  mov ecx, PATHS
  call BUILD_LINKS
  inc ebp
  cmp ebp, 8
  jb inner
  pop edi
  pop ebp
  mov dword [DIRTY_A], 1
  mov dword [DIRTY_B], 1
further:
  inc ebp
  cmp ebp, 8
  jb around
  popad
  ret 8
]]

-- updatePathLinkagesInAllEightDirections, its first 7 bytes replayed.
templates.relinkGame = [[
  push ecx
  mov eax, [esp + 0xC]
  push ebx
  push ebp
  jmp RESUME
]]

-- The link builder's final store (al = the tile's links, [esp+0x58] = the tile): any link
-- between a crenellation tile (flag 0x200) and a tower, keep, gatehouse or other building tile
-- (flag 0x10000000 or a building id) is taken away, in both directions - the builder runs for
-- both tiles - so a crenellation never leads into one, as stairs do not into a tower.
-- Replays mov edx, [esp+0x58] / mov [edx+links], al.
templates.towerAccess = [[
  mov edx, [esp + 0x58]
  test al, al
  jz put
  push ebx
  push ecx
  push esi
  push edi
  mov esi, edx
  mov edi, [FLAGS + esi*4]
  movzx ecx, word [TILE_Y + esi*2]
  shl ecx, 5
  add ecx, TMS
  xor ebx, ebx
dir:
  bt eax, ebx
  jnc nextdir
  mov edx, [ecx + ebx*4]
  add edx, esi
  push eax
  mov eax, [FLAGS + edx*4]
  test edi, 0x200
  jz curnot
  test eax, 0x10000000
  jnz cut
  cmp word [BUILDINGS + edx*2], 0
  jne cut
curnot:
  test eax, 0x200
  jz keep
  test edi, 0x10000000
  jnz cut
  cmp word [BUILDINGS + esi*2], 0
  jne cut
keep:
  pop eax
  jmp nextdir
cut:
  pop eax
  btr eax, ebx
nextdir:
  inc ebx
  cmp ebx, 8
  jb dir
  mov edx, esi
  pop edi
  pop esi
  pop ecx
  pop ebx
put:
  mov [edx + LINKS], al
  jmp RESUME
]]

return templates

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
  jne vanilla
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
-- A unit standing still (move status +0xF6 = 0) on the raised part of a crenellation is
-- handed to lua, which moves it to the nearest wall tile. Each unit is looked at once every
-- 16 ticks. Replays add edx, 1 / mov [esi], edx.
templates.unitTick = [[
  pushad
  mov eax, [TICKS]
  add eax, edx
  test eax, 15
  jnz done
  imul eax, edx, 0x490
  lea edi, [esi + eax + UNITS_OFF]
  cmp word [edi + 0xF6], 0
  jne done
  mov ecx, [edi + 0xD4]
  cmp ecx, TILES
  jae done
  mov eax, [FLAGS + ecx*4]
  and eax, 0x400100
  cmp eax, 0x400100
  jne done
  mov [STATE + 0x80], edx
  mov [STATE + 0x84], esi
  call PUSH_OFF
done:
  popad
  add edx, 1
  mov [esi], edx
  jmp RESUME
]]

return templates

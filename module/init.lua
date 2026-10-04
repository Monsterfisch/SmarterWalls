--[[
  Smarter Walls

  1. Walls at any angle. The game walks a dragged wall diagonally until it lines up with the
     end point and then straight on, so every wall is made of 45 and 90 degree pieces. Here
     the wall follows the straight line between the two points instead.
  2. Walls flow around what is in the way. When the line runs into a building, a tree, rocks
     or anything else a wall cannot stand on, the wall goes around it, hugging its outline,
     and comes back to the line. Crenellations follow the wall they are dragged along.
     The game draws, checks and builds a dragged wall in three functions
     (renderWallDragPreview, validateWallBuildPath, placeWalls), each with its own copy of
     the step to the next tile. The route is worked out once per drag (in lua, cached while
     the drag stays the same) and each of the three steps reads the next tile from it, so
     the preview, the cost, the red/green check and the wall that is built always agree.
     placeWalls always works the route out afresh from the map as it is at that moment, so
     every machine in a multiplayer game builds the same wall.
  3. Building a wall over damaged stairs puts the stairs back at the height they had. The
     game reset them to wall height instead. The height before the first hit is remembered
     when stairs are damaged; for stairs damaged before the game was loaded it is worked out
     from the damage counter and the stairs next to them.
  4. Building a wall over a damaged crenellation repairs the crenellation. Only an intact
     crenellation is turned into wall, as before.
  5. Troops can walk over the raised part of a crenellation (tile flag 0x400000). The game's
     path link builder refuses those tiles in two tests; both are switched off, and the game
     rebuilds every link when a map or save loads. A group ordered onto a wall spreads out
     over the tiles its search found (pathFindingResultBased, wall tiles, then any tile);
     raised parts are taken out of both picks. A unit that stops on one is moved to the
     nearest wall tile (never another crenellation: with only those in reach it stays),
     checked once every 16 ticks per unit from updateUnits; one waiting
     for a ladder or still walking gets ladderWait seconds first and is then sent on to where
     it was going. Whatever it remembered of the raised tile (destination, the place it goes
     back to after a fight, its place in the formation) is moved to the new tile, so it does
     not walk back. Ladders may be
     leant against them (UpdateLadderman's wall test) and siege towers and ladders sent at a
     wall may pick them (the wall/free-tile pair search); a siege tower's own wall search
     already takes any wall tile, and its links now meet links coming back.
  6. Ladders and siege towers take on diagonal walls. Troops sent at a wall look for a free
     tile next to it in all eight directions instead of four (a ladder already leans and
     climbs diagonally). A siege tower only ever docked two tiles straight out from a wall
     that runs straight past it; where the game finds no such spot, the tower docks with
     the corner of its 3x3 against a diagonal wall, which the path links already join.
  8. Crenellation heights. The game makes a crenellation 0x62 above the ground, or 0x44 (and
     flag 0x10000) when its straight neighbours are only low walls - so it is 8 above a stone
     or wood wall on flat ground and wrong on any other. Here it is 8 above the tallest wall
     beside it; next to stairs only, by the step directly beside it - tall for steps 1-3,
     low from 4 on; next to crenellations only, as tall as they are. Repairing a crenellation uses the same rule.
  7. Assassins. Their route search never climbs onto a raised crenellation part; with 5 on it
     does. (Diagonal climbs are left alone: the game's walk back from the goal refuses them.)
  Stairs and crenellations are routed too: crenellations around undamaged walls like walls,
  stairs only in straight steps (the game's stairs never step diagonally) and around every
  wall, since the game ends stairs at the first wall they meet. Each route step also lowers
  the stairs by 16, as the game's own step does.

  Every address is found by pattern scan or read out of the instruction that uses it, so the
  module runs on Stronghold Crusader.exe and Stronghold_Crusader_Extreme.exe alike.
]]

local templates = require("templates")

local MODULE_NAME = "smarter-walls"

local DEFAULTS = { anyAngle = true, flow = true, aroundWalls = true, stairs = true,
  crenellations = true, walkableCrenellations = true, diagonalSiege = true, ladderWait = 10,
  crenellationHeights = true }

---------------------------------------------------------------------------------------
-- What the game's code looks like where this module touches it
---------------------------------------------------------------------------------------

-- The three functions that walk a dragged wall, with their first instructions (replayed by
-- the entry hook) and, as offsets from the start, the step to the next tile, the top of the
-- tile loop and the code after it.
local FUNCTIONS = {
  validate = {
    aob = "83 EC 20 33 C0 39 05 ? ? ? ? 8B D1 89 14 24",
    original = "sub esp, 0x20\nxor eax, eax", size = 5,
    step = 0x3A3, stepBytes = { 0x8B, 0x6C, 0x24, 0x40, 0x3B, 0xFD }, stepSize = 6,
    loop = 0x195, loopBytes = { 0x8B, 0x54, 0x24, 0x10 },
    done = 0x4A5, doneBytes = { 0x8B, 0x54, 0x24, 0x10, 0xC7, 0x82 },
    template = "validateStep", fresh = 0,
  },
  preview = {
    aob = "83 EC 14 8B 54 24 1C 57 33 FF 81 FA 8F 01 00 00",
    original = "sub esp, 0x14\nmov edx, [esp + 0x1C]", size = 7,
    step = 0x299, stepBytes = { 0x8B, 0x5C, 0x24, 0x1C, 0x3B, 0x5C, 0x24, 0x34 }, stepSize = 8,
    loop = 0x100, loopBytes = { 0x66, 0x8B, 0x54, 0x24, 0x3C },
    done = 0x3BC, doneBytes = { 0x66, 0x8B, 0x54, 0x24, 0x3C },
    template = "previewStep", fresh = 0,
  },
  place = {
    aob = "83 EC 28 8B 54 24 2C 53 8B 5C 24 40 55",
    original = "sub esp, 0x28\nmov edx, [esp + 0x2C]", size = 7,
    step = 0x3CA, stepBytes = { 0x8B, 0x74, 0x24, 0x20, 0x8B, 0x6C, 0x24, 0x48 }, stepSize = 8,
    loop = 0xD0, loopBytes = { 0x8B, 0x44, 0x24, 0x50 },
    done = 0x4F6, doneBytes = { 0x8B, 0x44, 0x24, 0x50 },
    template = "placeStep", fresh = 1,
  },
}

-- validateWallBuildPath: operands of the instructions that name the map tables.
local VALIDATE_VALID = { 0x77, { 0x80, 0xBC, 0x38 } }      -- cmp byte [eax+edi+validTiles], 0
local VALIDATE_ROWS = { 0xCE, { 0x8D, 0x2C, 0x85 } }       -- lea ebp, [eax*4+rows]
local VALIDATE_TREES = { 0x1F4, { 0x0F, 0xBF, 0x80 } }     -- movsx eax, word [eax+treeType]
local VALIDATE_ENCLOSED = 0x176                            -- call isTileEnclosedByWalls

-- placeWalls, a tile being (re)built: cmp byte [esi+edi+damage], 0 / jne +4. Offsets from
-- the start of placeWalls of where the game goes on from there.
local PLACE_RESTORE = { at = 0x18F, size = 10,
  bytes = { 0x80, 0xBC, 0x3E, 0xA0, 0x90, 0x32, 0x00, 0x00, 0x75, 0x04 } }
local PLACE_UNDAMAGED = { 0x199, { 0x85, 0xED, 0x74, 0x32 } }
local PLACE_DAMAGED = { 0x19D, { 0x85, 0xED, 0x8A, 0x8C } }
local PLACE_COUNTED = { 0x2AC, { 0x8B, 0x84, 0xB7, 0x60, 0x51, 0x16, 0x00 } }
local PLACE_FREE = { 0x398, { 0x8B, 0x4C, 0x24, 0x44, 0x56, 0x51 } }
-- placeWalls, a new crenellation: call hasOnlyTowerNeighborsNoWalls(tile, y), the game's whole
-- height rule (low, +0x44 and flag 0x10000, when its straight neighbours are only wood walls
-- or low crenellations; tall, +0x62, otherwise). After the call: test eax, eax; after the
-- height: the row/column parity test that raises every other crenellation tile.
local PLACE_CRENEL_CALL = { 0x20E, { 0xE8 } }
local PLACE_CRENEL_AFTER = { 0x213, { 0x85, 0xC0, 0x74, 0x12 } }
local PLACE_CRENEL_PARITY = { 0x231, { 0x8B, 0x44, 0x24, 0x20, 0x83, 0xE0, 0x01 } }
local CRENEL_ABOVE_WALL = 8        -- a crenellation stands this much above its wall
local CRENEL_TALL = 0x62           -- the game's two crenellation heights above the ground
local CRENEL_LOW = 0x44
local STONE_WALL = 0x5A            -- a stone wall's height above the ground
local STAIR_STEP = 16
local STAIRS_TALL_UP_TO = 3        -- stairs steps 1-3 get tall crenellations, 4-6 low ones

-- processDamageToBuilding, wall branch: mov edx, [global] before the first hit takes the
-- top off, and the line that clears the wall bits once the wall is gone.
local AOB_DAMAGE_RECORD = "8B 15 ? ? ? ? 83 05 ? ? ? ? 01 3B C5"
local DAMAGE_RECORD_SIZE = 6
local AOB_DAMAGE_FORGET = "81 A4 9F 60 51 16 00 FF F4 BE FF"
local DAMAGE_FORGET_SIZE = 11

-- The path link builder (updatePathLinkageLayerBasedOnBuildingsUnk): the tile's own test and
-- the neighbours' test that keep a crenellation's raised part (flag 0x400000) out of every
-- route. Their 0x400000 immediates are set to 0.
local AOB_LINK_SELF = "F7 C3 00 00 40 00 0F 85 ? ? ? ?"           -- test ebx, 0x400000 / jne
local LINK_SELF_IMM = 2
local AOB_LINK_NEIGHBOUR = "A9 00 00 40 00 74 0B 02 96 ? ? ? ?"   -- test eax, 0x400000 / je
local LINK_NEIGHBOUR_IMM = 1
-- Ladders: getOrientationThatIsWallTowerOrGatehouse (UpdateLadderman's choice of the wall tile
-- to lean on) skips a neighbour with 0x400002 (raised part or stockpile); 0x2 is kept.
local AOB_LADDER_WALL = "F7 C2 02 00 40 00 74 10"              -- test edx, 0x400002 / je
local LADDER_WALL_IMM = 2
-- Siege towers and ladders sent at a wall (giveTribeAnInstruction ->
-- populateDestinationsArrayWithWallTileAndFreeTilePairInSameArea): the free tile beside an
-- enemy wall or crenellation, which skips raised parts.
local AOB_WALL_PAIR = "F7 C2 00 00 40 00 75 13"                -- test edx, 0x400000 / jne
local WALL_PAIR_IMM = 2

-- Diagonal walls. The free tile beside a wall that troops sent at it look for (same search as
-- AOB_WALL_PAIR) only looks straight up, down, left and right, through a 4-entry direction
-- table: mov ecx, table / ... / cmp ecx, table end. Pointed at an 8-entry one instead.
local AOB_PAIR_TABLE = "B9 ? ? ? ? 8B 41 04 03 C7"
local AOB_PAIR_TABLE_END = "81 F9 ? ? ? ? 7C B8"
local PAIR_DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
-- UnitsState::findFreeTileNearby(unit, wallTile): where a siege tower stands to dock - two tiles
-- straight out from the wall, and only where the wall runs straight past that tile.
local AOB_FREE_TILE = "83 EC 10 53 55 8B 6C 24 1C 56 69 ED 90 04 00 00"
local FREE_TILE_SIZE = 9
local FREE_TILE_UNITS = { 0x10, { 0x8B, 0x85 } }                -- mov eax, [ebp+units+tile]
local FREE_TILE_Y = { 0x2A, { 0x0F, 0xBF, 0x34, 0x7D } }        -- movsx esi, [edi*2+tileY]
local FREE_TILE_PF = { 0x5A, { 0xB9 } }                         -- mov ecx, PathFindingState
local FREE_TILE_NAVIGATE = 0x67                                 -- call canNavigateToArea
local FREE_TILE_TYPES = { 0x21A, { 0x66, 0x83, 0xB8 } }         -- cmp word [eax+type], 0x43
local SIEGE_BLOCKED = 0x4A5014B1
local U_OWNER = 0x96

-- Assassins: pathFindingWithBuildingsIncluded, the route search for a group of assassins.
-- A step between two tiles without a path link is a climb (onto a wall from the ground or
-- down again), never onto a tile with any of 0x4A5014B1, which includes a crenellation's
-- raised part. It climbs only in the four straight directions, and so does the walk back
-- that turns the search into steps (traceAndCommitPathPlan, mode 3): a diagonal climb in
-- the search alone leaves a route that cannot be walked back, and the assassin goes nowhere
-- (1.0.5/1.0.6). Diagonal walls need no diagonal climb - they always have a straight side.
local AOB_ASSASSIN_SEARCH = "51 53 8B 5C 24 0C 81 FB 8F 01 00 00 56 57"
local ASSASSIN_TARGET = { 0x203, 0x307, 0x409, 0x50E }       -- test edi, 0x4A5014B1
local ASSASSIN_TARGET_BYTES = { 0xF7, 0xC7, 0xB1, 0x14, 0x50, 0x4A, 0x0F, 0x85 }

-- Spreading a group out on a wall: the pick of wall tiles (test [esi*4+flags], 0x10000100,
-- two movsx, je skip) and its any-tile fallback (cmp ebp, 0xFA0 / jl take).
local AOB_SPREAD_WALL = "F7 04 B5 ? ? ? ? 00 01 00 10 0F BF 3C 75 ? ? ? ? 0F BF 2C 75 ? ? ? ? 74 4A"
local SPREAD_WALL_SIZE = 11
local AOB_SPREAD_ANY = "81 FD A0 0F 00 00 7C 1E"
local SPREAD_ANY_SIZE = 8

-- updateUnits, a live unit about to be updated: add edx, 1 / mov [esi], edx.
local AOB_UNIT_TICK = "83 C2 01 89 16 8B 15 ? ? ? ? 69 D2 90 04 00 00 33 C9 66 89 8C 32 AE 09 00 00"
local UNIT_TICK_SIZE = 5
-- The game tick counter, read in updateUnits' notice-frequency test (mov edx, [ticks]).
local AOB_TICKS = "8B 87 50 0A 00 00 8B 8F 98 09 00 00 8B 15"
local TICKS_OPERAND = 14
-- UnitsState::setPositionOfUnit(unit, x, y, height).
local AOB_SET_POSITION = "53 8B 5C 24 0C 81 FB 8F 01 00 00 55 8B E9 0F 87"
-- The tile flags (one dword per tile), the first array of TileMapState that has a global.
local AOB_TILE_FLAGS = "F7 04 9D ? ? ? ? 00 01 00 00"
local TILE_FLAGS_OPERAND = 3

-- Unit layout.
local UNIT_SIZE = 0x490
local UNITS_FROM_STATE = 0x614
local U_X = 0xC4
local U_Y = 0xC6
local U_GOAL_X = 0xC8
local U_GOAL_Y = 0xCA
local U_TILE = 0xD4
local U_GOAL_TILE = 0xD8
local U_DEST_X = 0xEC
local U_DEST_Y = 0xEE
local U_RESUME_X = 0xF0       -- where a unit goes back to after a fight
local U_RESUME_Y = 0xF2
local U_PLANNED_X = 0x2DC     -- its place in its group's formation
local U_PLANNED_Y = 0x2DE
local PUSH_RADIUS = 4
local MAX_UNITS = 4096
local TICKS_PER_SECOND = 40   -- at the default game speed
local CHECK_TICKS = 16        -- each unit is looked at once in this many ticks
-- UnitsState::setDestinationForUnit(unit, x, y, flag); its first bytes are patched by other
-- modules, so the pattern starts 0x11 in.
local AOB_SET_DESTINATION = "8B 6C 24 18 56 8D 34 0A 0F BF 96 A2 06 00 00"
local SET_DESTINATION_START = 0x11

-- TileMapState layout (OpenSHC, the same in both exes).
local TMS_FLAGS = 0x165160
local TMS_TREES = 0x1DB590
local TMS_BUILDINGS = 0x2029B0
local TMS_LIVE = 0x29FA30
local TMS_BASE = 0x2B3440
local TMS_DAMAGE = 0x3290A0
local TMS_AREAS = 0x363ED0
local TMS_LINKS = 0x38B2F0

-- Tile flags.
local F_STOCKPILE = 0x2
local F_WALL = 0x100
local F_CRENEL = 0x200
local F_STAIRS = 0x800
local F_LOW = 0x10000
local F_RAISED = 0x400000    -- the raised part of a crenellation
local F_TREE = 0x3000
-- What validateWallBuildPath refuses outright.
local F_BLOCKED = { 0x14, 0x70000401, 0x300000, 0x80 }

local M_WALL = 0x19
local M_CRENEL = 0x1A
local M_STAIRS = 0x1B
local M_WOODWALL = 0x2E

local MAP_SIZE = 400
local TILES = MAP_SIZE * MAP_SIZE
local MAX_PATH = 2048
local MAX_AGE = 60            -- calls (two a frame) before a drag's route is checked again
local MAX_NODES = 60000

-- DATA block: the request, the cached key, the route and the restore exchange.
local D_REQUEST = 0x00        -- x1, y1, x2, y2, mapper, player, TileMapState, fresh
local D_VALID = 0x38
local D_COUNT = 0x40
local D_IDX = { validate = 0x44, place = 0x48, preview = 0x4C }
local D_ON = { validate = 0x50, place = 0x54, preview = 0x58 }
local D_R_TILE = 0x60
local D_R_TMS = 0x64
local D_R_RESULT = 0x68
local D_R_HEIGHT = 0x6C
local D_R_X = 0x70
local D_R_Y = 0x74
local D_LAST = 0x78            -- the crenellation repaired last in this placeWalls call
local D_STAIRS = 0x7C          -- the drag is stairs
local D_UNIT = 0x80            -- the unit to push off a crenellation, and UnitsState
local D_UNITS_STATE = 0x84
local D_DOCK_UNIT = 0x88       -- findFreeTileNearby's unit and wall tile, and lua's answer
local D_DOCK_WALL = 0x8C
local D_DOCK_RESULT = 0x90
local D_PATIENCE = 0x94        -- 1: the unit simply stopped there; more: ladder or walking
local D_CREN_TILE = 0x98       -- a new crenellation: tile, TileMapState, x, y; lua's height, low
local D_CREN_TMS = 0x9C
local D_CREN_X = 0xA0
local D_CREN_Y = 0xA4
local D_CREN_HEIGHT = 0xA8
local D_CREN_LOW = 0xAC
local D_PATH = 0x100
local DATA_SIZE = D_PATH + 4 * MAX_PATH

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function scan(pattern, purpose)
  local ok, address = pcall(core.AOBScan, pattern)
  if not ok or address == nil then
    error(MODULE_NAME .. ": could not find " .. purpose)
  end
  return address
end

local function expectBytes(address, bytes, purpose)
  for index, byte in ipairs(bytes) do
    if (core.readByte(address + index - 1) & 0xFF) ~= byte then
      error(string.format("%s: %s at 0x%X is not the code this module knows", MODULE_NAME,
        purpose, address))
    end
  end
end

local function readOperand(base, site, purpose)
  expectBytes(base + site[1], site[2], purpose)
  return core.readInteger(base + site[1] + #site[2])
end

local function checked(base, site, purpose)
  expectBytes(base + site[1], site[2], purpose)
  return base + site[1]
end

-- FASM gets a fixed 64 KB for source, symbols and output: only pass what a script uses.
local function assemble(script, values)
  local used = {}
  for name, value in pairs(values) do
    if script:find("%f[%w_]" .. name .. "%f[^%w_]") then
      used[name] = value
    end
  end
  return core.allocateAssembly(script, used)
end

local function jumpTo(address, target, size)
  local code = { 0xE9, core.itob(core.getRelativeAddress(address, target, -5)) }
  for _ = 6, size do
    code[#code + 1] = 0x90
  end
  core.writeCode(address, code)
end

local function setting(config, name)
  if type(config) == "table" and config[name] ~= nil then
    return config[name] == true
  end
  return DEFAULTS[name]
end

local function byte(address)
  return core.readByte(address) & 0xFF
end

-- A whole number setting, kept within low..high.
local function number(config, name, low, high)
  local value = DEFAULTS[name]
  if type(config) == "table" and tonumber(config[name]) ~= nil then
    value = math.tointeger(math.floor(tonumber(config[name]))) or value
  end
  return math.max(low, math.min(high, value))
end

local function word(address)
  return core.readSmallInteger(address) & 0xFFFF
end

local function signedWord(address)
  local value = word(address)
  if value >= 0x8000 then value = value - 0x10000 end
  return value
end

-- A cdecl function with no arguments that runs `callback` in lua.
local function luaFunction(purpose, callback)
  local pad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
  local reported = false
  core.detourCode(function(registers)
    local ok, message = pcall(callback)
    if not ok and not reported then
      reported = true
      log(WARNING, string.format("%s: %s failed: %s", MODULE_NAME, purpose, tostring(message)))
    end
    return registers
  end, pad, 5)
  return pad
end

---------------------------------------------------------------------------------------
-- The route of a dragged wall
---------------------------------------------------------------------------------------

-- A straight line of tiles from (x1, y1) to (x2, y2), one tile per step (Bresenham).
local function straightLine(x1, y1, x2, y2)
  local tiles = {}
  local dx, dy = math.abs(x2 - x1), -math.abs(y2 - y1)
  local sx = x1 < x2 and 1 or -1
  local sy = y1 < y2 and 1 or -1
  local err = dx + dy
  local x, y = x1, y1
  while true do
    tiles[#tiles + 1] = { x, y }
    if x == x2 and y == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x = x + sx end
    if e2 <= dx then err = err + dx; y = y + sy end
  end
  return tiles
end

-- The game's own walk: diagonally until one axis lines up, then straight on.
local function gameLine(x1, y1, x2, y2)
  local tiles = {}
  local x, y = x1, y1
  while true do
    tiles[#tiles + 1] = { x, y }
    if x == x2 and y == y2 then break end
    if x ~= x2 then x = x + (x < x2 and 1 or -1) end
    if y ~= y2 then y = y + (y < y2 and 1 or -1) end
  end
  return tiles
end

-- A small binary heap of { cost, tie, id }.
local function heapPush(heap, item)
  heap[#heap + 1] = item
  local i = #heap
  while i > 1 do
    local p = i // 2
    local a, b = heap[p], heap[i]
    if a[1] < b[1] or (a[1] == b[1] and (a[2] < b[2] or (a[2] == b[2] and a[3] <= b[3]))) then
      break
    end
    heap[p], heap[i] = b, a
    i = p
  end
end

local function heapPop(heap)
  local top = heap[1]
  local last = heap[#heap]
  heap[#heap] = nil
  if #heap > 0 then
    heap[1] = last
    local i, n = 1, #heap
    while true do
      local l, r, s = 2 * i, 2 * i + 1, i
      local function less(a, b)
        return a[1] < b[1] or (a[1] == b[1] and (a[2] < b[2] or (a[2] == b[2] and a[3] < b[3])))
      end
      if l <= n and less(heap[l], heap[s]) then s = l end
      if r <= n and less(heap[r], heap[s]) then s = r end
      if s == i then break end
      heap[i], heap[s] = heap[s], heap[i]
      i = s
    end
  end
  return top
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
-- Stairs only ever step straight, never diagonally.
local NEIGHBOURS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- A straight line of tiles that only steps along x or y, for stairs: each step takes the axis
-- that keeps the tile closer to the line.
local function straightLine4(x1, y1, x2, y2)
  local tiles = { { x1, y1 } }
  local dx, dy = x2 - x1, y2 - y1
  local sx, sy = dx < 0 and -1 or 1, dy < 0 and -1 or 1
  local x, y = x1, y1
  while x ~= x2 or y ~= y2 do
    local ex = math.abs(dx * (y - y1) - dy * (x + sx - x1))
    local ey = math.abs(dx * (y + sy - y1) - dy * (x - x1))
    if y == y2 or (x ~= x2 and (ex < ey or (ex == ey and math.abs(x2 - x) >= math.abs(y2 - y)))) then
      x = x + sx
    else
      y = y + sy
    end
    tiles[#tiles + 1] = { x, y }
  end
  return tiles
end

-- The game's own stairs walk: along x while x is further off, then along y.
local function gameLine4(x1, y1, x2, y2)
  local tiles = { { x1, y1 } }
  local x, y = x1, y1
  while x ~= x2 or y ~= y2 do
    if math.abs(x2 - x) > math.abs(y2 - y) then
      x = x + (x < x2 and 1 or -1)
    else
      y = y + (y < y2 and 1 or -1)
    end
    tiles[#tiles + 1] = { x, y }
  end
  return tiles
end

local function makeRouter(m, options)
  local enclosed = core.exposeCode(m.enclosed, 3, 1)

  local function tileOf(x, y)
    return core.readInteger(m.rows + 12 * y) + x
  end

  -- Can a wall of this kind go on (x, y)? Only what stays put counts - units, enemy range
  -- and the like are left to the game's own check, so the route does not jump about.
  -- Returns the step cost, or nil if not.
  -- An undamaged wall, stairs or crenellation: a new wall goes around it. Damaged ones are
  -- walked over, so the new wall repairs them.
  local function intactWall(tms, x, y)
    if x < 0 or y < 0 or x >= MAP_SIZE or y >= MAP_SIZE then return false end
    if byte(m.valid + y * MAP_SIZE + x) == 0 then return false end
    local tile = tileOf(x, y)
    local flags = core.readInteger(tms + TMS_FLAGS + 4 * tile)
    return flags & F_WALL ~= 0 and flags & F_STOCKPILE == 0 and byte(tms + TMS_DAMAGE + tile) == 0
  end

  local function avoidsWalls(mapper)
    return options.aroundWalls and mapper ~= M_STAIRS
  end

  -- A diagonal step squeezing between two undamaged wall tiles would cross that wall.
  local function crossesWall(tms, mapper, x, y, nx, ny)
    return avoidsWalls(mapper) and nx ~= x and ny ~= y
      and intactWall(tms, nx, y) and intactWall(tms, x, ny)
  end

  -- isEnd: the first or last tile, which may join an existing wall.
  local function cost(tms, mapper, x, y, isEnd)
    if x < 0 or y < 0 or x >= MAP_SIZE or y >= MAP_SIZE then return nil end
    if byte(m.valid + y * MAP_SIZE + x) == 0 then return nil end
    local tile = tileOf(x, y)
    local flags = core.readInteger(tms + TMS_FLAGS + 4 * tile)
    for _, mask in ipairs(F_BLOCKED) do
      if flags & mask ~= 0 then return nil end
    end
    if word(tms + TMS_BUILDINGS + 2 * tile) ~= 0 then return nil end
    if flags & F_TREE ~= 0 then
      local tree = signedWord(tms + TMS_TREES + 2 * tile)
      if tree > 0 and tree < 2000 then
        local kind = signedWord(m.treeTypes + tree * 0x9C) - 5
        if kind < 0 or kind > 14 or kind == 10 then return nil end
      end
    end
    if mapper == M_STAIRS then
      -- the game's stairs end at the first wall they meet, so they go around every wall
      if not isEnd and flags & F_WALL ~= 0 then return nil end
    elseif not isEnd and avoidsWalls(mapper) and flags & F_WALL ~= 0
        and byte(tms + TMS_DAMAGE + tile) == 0 then
      return nil
    end
    if mapper == M_CRENEL then
      if enclosed(tms, tile, y) == 0 then return nil end
      -- along the wall, not over it
      if flags & F_WALL ~= 0 then return 3 end
    end
    return 1
  end

  local function allFree(tms, mapper, tiles)
    for i, t in ipairs(tiles) do
      if cost(tms, mapper, t[1], t[2], i == 1 or i == #tiles) == nil then return false end
      local p = tiles[i - 1]
      if p and crossesWall(tms, mapper, p[1], p[2], t[1], t[2]) then return false end
    end
    return true
  end

  -- A* from start to goal over tiles a wall can take, kept close to the straight line:
  -- every step costs 4 * length, every tile its distance from the line (times the line's
  -- length, so everything stays in whole numbers and every machine gets the same route).
  local function around(tms, mapper, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.max(math.abs(dx), math.abs(dy))
    local margin = 12 + length // 2
    local minX, maxX = math.max(0, math.min(x1, x2) - margin), math.min(MAP_SIZE - 1, math.max(x1, x2) + margin)
    local minY, maxY = math.max(0, math.min(y1, y2) - margin), math.min(MAP_SIZE - 1, math.max(y1, y2) + margin)
    local step = 4 * length
    local function h(x, y)
      return step * math.max(math.abs(x2 - x), math.abs(y2 - y))
    end
    local start, goal = y1 * MAP_SIZE + x1, y2 * MAP_SIZE + x2
    local best, from, closed = { [start] = 0 }, {}, {}
    local heap = {}
    heapPush(heap, { h(x1, y1), h(x1, y1), start })
    local expanded = 0
    while #heap > 0 do
      local item = heapPop(heap)
      local id = item[3]
      if id == goal then
        local tiles = {}
        while id ~= nil do
          table.insert(tiles, 1, { id % MAP_SIZE, id // MAP_SIZE })
          id = from[id]
        end
        return tiles
      end
      if not closed[id] then
        closed[id] = true
        expanded = expanded + 1
        if expanded > MAX_NODES then return nil end
        local x, y = id % MAP_SIZE, id // MAP_SIZE
        for _, n in ipairs(mapper == M_STAIRS and NEIGHBOURS4 or NEIGHBOURS) do
          local nx, ny = x + n[1], y + n[2]
          if nx >= minX and nx <= maxX and ny >= minY and ny <= maxY then
            local nid = ny * MAP_SIZE + nx
            if not closed[nid] then
              local c = (nid == goal) and 1 or cost(tms, mapper, nx, ny)
              if c ~= nil and crossesWall(tms, mapper, x, y, nx, ny) then c = nil end
              if c ~= nil then
                local off = math.abs(dx * (ny - y1) - dy * (nx - x1))
                local g = best[id] + step * c + off
                if best[nid] == nil or g < best[nid] then
                  best[nid] = g
                  from[nid] = id
                  local hn = h(nx, ny)
                  heapPush(heap, { g + hn, hn, nid })
                end
              end
            end
          end
        end
      end
    end
    return nil
  end

  local function route(r)
    local x1, y1, x2, y2 = r.x1, r.y1, r.x2, r.y2
    local line
    if r.mapper == M_STAIRS then
      line = options.anyAngle and straightLine4(x1, y1, x2, y2) or gameLine4(x1, y1, x2, y2)
    else
      line = options.anyAngle and straightLine(x1, y1, x2, y2) or gameLine(x1, y1, x2, y2)
    end
    if not options.flow or allFree(r.tms, r.mapper, line) then
      return options.anyAngle and line or nil
    end
    return around(r.tms, r.mapper, x1, y1, x2, y2) or (options.anyAngle and line or nil)
  end

  return function()
    core.writeInteger(m.data + D_VALID, 0)
    local function at(offset) return core.readInteger(m.data + D_REQUEST + offset) end
    local r = { x1 = at(0), y1 = at(4), x2 = at(8), y2 = at(0xC), mapper = at(0x10) & 0xFFFF,
      tms = at(0x18) }
    for _, v in ipairs({ r.x1, r.y1, r.x2, r.y2 }) do
      if v < 0 or v >= MAP_SIZE then return end
    end
    if r.mapper ~= M_WALL and r.mapper ~= M_WOODWALL and r.mapper ~= M_CRENEL
        and r.mapper ~= M_STAIRS then return end
    local tiles = route(r)
    if tiles == nil or #tiles == 0 or #tiles > MAX_PATH then return end
    for i, t in ipairs(tiles) do
      core.writeInteger(m.data + D_PATH + 4 * (i - 1), t[1] | (t[2] << 16))
    end
    core.writeInteger(m.data + D_COUNT, #tiles)
    core.writeInteger(m.data + D_VALID, 1)
  end
end

---------------------------------------------------------------------------------------
-- How tall a crenellation is
---------------------------------------------------------------------------------------

-- A crenellation's height from what it stands next to:
--   walls first (all eight neighbours): the tallest wall beside it (its height before any
--   damage) plus 8, low (flag 0x10000) when that wall is a low one, such as a wood wall;
--   else stairs: the step directly beside it (straight neighbours; diagonal ones only when
--   there is none), the lowest one when it touches several - steps 1 to 3 counted down from
--   the wall give a tall crenellation, 4 and lower a low one. A crenellation beside step 4 also touches step 3 diagonally, which is
--   why only the straight neighbour counts;
--   else crenellations: as tall as the tallest one beside it.
-- Towers and gatehouses do not count. Nothing to go by: nil, and the game decides.
local STRAIGHT = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local DIAGONAL_ONLY = { { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } }

local function makeCrenelHeight(m)
  local function tileAt(x, y)
    if x < 0 or y < 0 or x >= MAP_SIZE or y >= MAP_SIZE then return nil end
    if byte(m.valid + y * MAP_SIZE + x) == 0 then return nil end
    return core.readInteger(m.rows + 12 * y) + x
  end

  -- A wall-family tile that counts (not a stockpile, tower or gatehouse): its flags and its
  -- height before damage.
  local function piece(tms, x, y)
    local tile = tileAt(x, y)
    if tile == nil then return nil end
    local flags = core.readInteger(tms + TMS_FLAGS + 4 * tile)
    if flags & F_WALL == 0 or flags & F_STOCKPILE ~= 0 then return nil end
    if word(tms + TMS_BUILDINGS + 2 * tile) ~= 0 then return nil end
    return flags, byte(tms + TMS_LIVE + tile) + byte(tms + TMS_DAMAGE + tile)
  end

  -- Which step a stairs tile is, counted from the top: climb to the neighbouring stairs one
  -- step (16) higher until there is none.
  local function step(tms, x, y, height)
    local n = 1
    for _ = 1, 8 do
      local up
      for _, d in ipairs(STRAIGHT) do
        local flags, h = piece(tms, x + d[1], y + d[2])
        if flags ~= nil and flags & F_STAIRS ~= 0 and math.abs(h - height - STAIR_STEP) <= 2 then
          up = { x + d[1], y + d[2], h }
          break
        end
      end
      if up == nil then return n end
      n = n + 1
      x, y, height = up[1], up[2], up[3]
    end
    return n
  end

  return function(tms, x, y)
    local here = tileAt(x, y)
    if here == nil then return nil end
    local base = byte(tms + TMS_BASE + here)
    local wall, wallLow, crenel, crenelLow
    for _, d in ipairs(NEIGHBOURS) do
      local flags, height = piece(tms, x + d[1], y + d[2])
      if flags ~= nil and flags & F_STAIRS == 0 then
        if flags & F_CRENEL ~= 0 then
          if crenel == nil or height > crenel then crenel, crenelLow = height, flags & F_LOW ~= 0 end
        elseif wall == nil or height > wall then
          wall, wallLow = height, flags & F_LOW ~= 0
        end
      end
    end
    if wall ~= nil then
      return math.min(255, wall + CRENEL_ABOVE_WALL), wallLow
    end
    for _, ring in ipairs({ STRAIGHT, DIAGONAL_ONLY }) do
      local best, bestHeight
      for _, d in ipairs(ring) do
        local flags, height = piece(tms, x + d[1], y + d[2])
        if flags ~= nil and flags & F_STAIRS ~= 0 and (best == nil or height < bestHeight) then
          best, bestHeight = d, height
        end
      end
      if best ~= nil then
        if step(tms, x + best[1], y + best[2], bestHeight) <= STAIRS_TALL_UP_TO then
          return math.min(255, base + CRENEL_TALL), false
        end
        return math.min(255, base + CRENEL_LOW), true
      end
    end
    if crenel ~= nil then
      return crenel, crenelLow
    end
    return nil
  end
end

---------------------------------------------------------------------------------------
-- Putting damaged stairs and crenellations back
---------------------------------------------------------------------------------------

local function makeRestore(m, options)
  local crenelHeight = options.crenellationHeights and makeCrenelHeight(m) or nil
  -- The stairs' height before they were damaged, for stairs damaged before this module
  -- saw them: the damage counter gives back what was knocked off one point at a time; the
  -- first hit on tall stairs also took 20 off without counting it. Stairs step by 16, so a
  -- neighbour that is intact says which of the two it was when the numbers allow both.
  local function guessStairs(tms, x, y, flags, live, damage, base)
    local v = live + damage
    if flags & F_LOW ~= 0 or v - base <= 40 then return v end
    if v - base > 60 then return v + 20 end
    local matchLow, matchHigh = false, false
    for _, n in ipairs(NEIGHBOURS) do
      local nx, ny = x + n[1], y + n[2]
      if nx >= 0 and ny >= 0 and nx < MAP_SIZE and ny < MAP_SIZE
          and byte(m.valid + ny * MAP_SIZE + nx) ~= 0 then
        local nt = core.readInteger(m.rows + 12 * ny) + nx
        local nf = core.readInteger(tms + TMS_FLAGS + 4 * nt)
        if nf & F_WALL ~= 0 and nf & F_STOCKPILE == 0 and byte(tms + TMS_DAMAGE + nt) == 0 then
          local nh = byte(tms + TMS_LIVE + nt)
          if math.abs(nh - v) == 16 then matchLow = true end
          if math.abs(nh - (v + 20)) == 16 then matchHigh = true end
        end
      end
    end
    if matchHigh and not matchLow then return v + 20 end
    return v
  end

  return function()
    local tile = core.readInteger(m.data + D_R_TILE)
    local tms = core.readInteger(m.data + D_R_TMS)
    core.writeInteger(m.data + D_R_RESULT, 0)
    if tile < 0 or tile >= TILES then return end
    local flags = core.readInteger(tms + TMS_FLAGS + 4 * tile)
    if flags & F_WALL == 0 or flags & F_STOCKPILE ~= 0 then return end
    local live = byte(tms + TMS_LIVE + tile)
    local base = byte(tms + TMS_BASE + tile)
    local damage = byte(tms + TMS_DAMAGE + tile)
    local height, result
    if flags & F_CRENEL ~= 0 then
      if not options.crenellations then return end
      -- the game's own crenellation heights: low next to low walls, tall otherwise - or, with
      -- crenellationHeights on, the height its neighbours give it
      height = base + ((flags & F_LOW ~= 0) and CRENEL_LOW or CRENEL_TALL)
      if crenelHeight ~= nil then
        height = crenelHeight(tms, core.readInteger(m.data + D_R_X),
          core.readInteger(m.data + D_R_Y)) or height
      end
      if damage == 0 and live >= height then
        -- intact: turned into wall, unless it was repaired a moment ago in this same wall
        if core.readInteger(m.data + D_LAST) == tile then
          core.writeInteger(m.data + D_R_RESULT, 3)
        end
        return
      end
      result = 2
      core.writeInteger(m.data + D_LAST, tile)
    elseif flags & F_STAIRS ~= 0 then
      if not options.stairs or damage == 0 then return end
      local v = live + damage
      local record = byte(m.record + tile)
      if record ~= 0 and record >= v and record <= v + 60 then
        height = record
      else
        height = guessStairs(tms, core.readInteger(m.data + D_R_X), core.readInteger(m.data + D_R_Y),
          flags, live, damage, base)
      end
      result = 1
    else
      return
    end
    core.writeInteger(m.data + D_R_HEIGHT, math.min(height, 255))
    core.writeInteger(m.data + D_R_RESULT, result)
  end
end

---------------------------------------------------------------------------------------
-- Nobody stays on the raised part of a crenellation
---------------------------------------------------------------------------------------

-- Offsets around a tile, nearest first.
local function nearestFirst(radius)
  local offsets = {}
  for dy = -radius, radius do
    for dx = -radius, radius do
      if dx ~= 0 or dy ~= 0 then
        offsets[#offsets + 1] = { dx, dy, dx * dx + dy * dy }
      end
    end
  end
  table.sort(offsets, function(a, b)
    if a[3] ~= b[3] then return a[3] < b[3] end
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  return offsets
end

local function makePushOff(m)
  local setPosition = core.exposeCode(m.setPosition, 5, 1)
  local setDestination = core.exposeCode(m.setDestination, 5, 1)
  local offsets = nearestFirst(PUSH_RADIUS)
  local tms = m.tms

  local function tileAt(x, y)
    if x < 0 or y < 0 or x >= MAP_SIZE or y >= MAP_SIZE then return nil end
    if byte(m.valid + y * MAP_SIZE + x) == 0 then return nil end
    return core.readInteger(m.rows + 12 * y) + x
  end

  local function raised(x, y)
    local tile = tileAt(x, y)
    return tile ~= nil and core.readInteger(tms + TMS_FLAGS + 4 * tile) & F_RAISED ~= 0
  end

  -- A wall tile a unit can stand on: wall or stairs, no crenellation of any kind, not a
  -- stockpile, linked to the map. With none in reach the unit stays where it is.
  local function safe(x, y, area)
    local tile = tileAt(x, y)
    if tile == nil then return nil end
    local flags = core.readInteger(tms + TMS_FLAGS + 4 * tile)
    if flags & F_WALL == 0 or flags & (F_CRENEL | F_RAISED | F_STOCKPILE) ~= 0 then return nil end
    if byte(tms + TMS_LINKS + tile) == 0 then return nil end
    if area ~= nil and word(tms + TMS_AREAS + 2 * tile) ~= area then return nil end
    return tile
  end

  -- Every remembered place that is the raised tile now points at the new one, so nothing
  -- the game does on its own sends the unit back.
  local function forget(base, x, y, nx, ny)
    for _, pair in ipairs({ { U_GOAL_X, U_GOAL_Y }, { U_DEST_X, U_DEST_Y },
        { U_RESUME_X, U_RESUME_Y }, { U_PLANNED_X, U_PLANNED_Y } }) do
      if signedWord(base + pair[1]) == x and signedWord(base + pair[2]) == y then
        core.writeSmallInteger(base + pair[1], nx)
        core.writeSmallInteger(base + pair[2], ny)
      end
    end
  end

  return function()
    local unit = core.readInteger(m.data + D_UNIT)
    local state = core.readInteger(m.data + D_UNITS_STATE)
    local base = state + UNITS_FROM_STATE + unit * UNIT_SIZE
    local x, y = signedWord(base + U_X), signedWord(base + U_Y)
    local here = core.readInteger(base + U_TILE)
    if here < 0 or here >= TILES then return end
    -- where it was going, if that is somewhere else it can still get to
    local goalX, goalY = signedWord(base + U_GOAL_X), signedWord(base + U_GOAL_Y)
    local onward = core.readInteger(m.data + D_PATIENCE) > 1
      and (goalX ~= x or goalY ~= y) and tileAt(goalX, goalY) ~= nil and not raised(goalX, goalY)
    local area = word(tms + TMS_AREAS + 2 * here)
    for _, sameArea in ipairs(area ~= 0 and { true, false } or { false }) do
      for _, o in ipairs(offsets) do
        local nx, ny = x + o[1], y + o[2]
        local tile = safe(nx, ny, sameArea and area or nil)
        if tile ~= nil then
          setPosition(state, unit, nx, ny, byte(tms + TMS_LIVE + tile))
          if onward then
            -- on its way down a ladder or somewhere else: carry on from the new tile
            forget(base, x, y, nx, ny)
            setDestination(state, unit, goalX, goalY, 0)
          else
            -- it has arrived there, so it does not walk back
            forget(base, x, y, nx, ny)
            forget(base, goalX, goalY, nx, ny)
            core.writeSmallInteger(base + U_GOAL_X, nx)
            core.writeSmallInteger(base + U_GOAL_Y, ny)
            core.writeSmallInteger(base + U_DEST_X, nx)
            core.writeSmallInteger(base + U_DEST_Y, ny)
            core.writeInteger(base + U_GOAL_TILE, tile)
          end
          return
        end
      end
    end
  end
end

---------------------------------------------------------------------------------------
-- Siege towers against diagonal walls
---------------------------------------------------------------------------------------

-- A 3x3 siege tower docks with its corner against a diagonal wall: for the wall tile (wx, wy)
-- and a diagonal d, the wall has to run across d ((wx+dx, wy-dy) and (wx-dx, wy+dy) are wall),
-- the tower stands at (wx+2dx, wy+2dy), its 3x3 must be clear by the game's own rules, and the
-- unit must be able to get there. The nearest such spot wins.
local DIAGONALS = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }

local function makeDiagonalDock(m)
  local navigate = core.exposeCode(m.navigate, 5, 1)
  local tms = m.tms

  local function tileAt(x, y)
    if x < 0 or y < 0 or x >= MAP_SIZE or y >= MAP_SIZE then return nil end
    if byte(m.valid + y * MAP_SIZE + x) == 0 then return nil end
    return core.readInteger(m.rows + 12 * y) + x
  end

  local function isWall(x, y)
    local tile = tileAt(x, y)
    if tile == nil then return false end
    local flags = core.readInteger(tms + TMS_FLAGS + 4 * tile)
    return flags & F_WALL ~= 0 and flags & F_STOCKPILE == 0
  end

  local function clear(x, y)
    local tile = tileAt(x, y)
    if tile == nil then return false end
    local flags = core.readInteger(tms + TMS_FLAGS + 4 * tile)
    if flags & F_WALL ~= 0 or flags & SIEGE_BLOCKED ~= 0 then return false end
    local building = word(tms + TMS_BUILDINGS + 2 * tile)
    return building == 0 or word(m.buildingTypes + building * 0x32C) == 0x43
  end

  return function()
    local unit = core.readInteger(m.data + D_DOCK_UNIT)
    local wall = core.readInteger(m.data + D_DOCK_WALL)
    if wall <= 0 or wall >= TILES or unit <= 0 then return end
    local wy = word(m.tileY + 2 * wall)
    if wy >= MAP_SIZE then return end
    local wx = wall - core.readInteger(m.rows + 12 * wy)
    if wx < 0 or wx >= MAP_SIZE then return end
    local base = m.units + unit * UNIT_SIZE
    local owner = signedWord(base + U_OWNER)
    local from = signedWord(tms + TMS_AREAS + 2 * core.readInteger(base + U_TILE))
    local ux, uy = signedWord(base + U_X), signedWord(base + U_Y)
    local best, bestDistance
    for _, d in ipairs(DIAGONALS) do
      local dx, dy = d[1], d[2]
      if isWall(wx + dx, wy - dy) and isWall(wx - dx, wy + dy) then
        local cx, cy = wx + 2 * dx, wy + 2 * dy
        local ok = true
        for oy = -1, 1 do
          for ox = -1, 1 do
            if ok and not clear(cx + ox, cy + oy) then ok = false end
          end
        end
        local centre = ok and tileAt(cx, cy) or nil
        if centre ~= nil then
          local to = signedWord(tms + TMS_AREAS + 2 * centre)
          if navigate(m.pathFinding, owner, from, to, 0) ~= 0 then
            local distance = (cx - ux) * (cx - ux) + (cy - uy) * (cy - uy)
            if best == nil or distance < bestDistance then
              best, bestDistance = centre, distance
            end
          end
        end
      end
    end
    if best ~= nil then
      core.writeInteger(m.data + D_DOCK_RESULT, best)
    end
  end
end

---------------------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------------------

local function enable(self, config)
  local options = {}
  for name in pairs(DEFAULTS) do
    options[name] = setting(config, name)
  end
  options.ladderWait = number(config, "ladderWait", 1, 60)
  local routing = options.anyAngle or options.flow
  local restoring = options.stairs or options.crenellations
  if not routing and not restoring and not options.walkableCrenellations
      and not options.diagonalSiege and not options.crenellationHeights then return end

  local starts = {}
  for name, f in pairs(FUNCTIONS) do
    starts[name] = scan(f.aob, "the wall drag code (" .. name .. ")")
  end
  local validate, place = starts.validate, starts.place

  local data = core.allocate(DATA_SIZE, true)
  local record = core.allocate(TILES + 16, true)
  local m = {
    data = data,
    record = record,
    valid = readOperand(validate, VALIDATE_VALID, "the map's valid tiles"),
    rows = readOperand(validate, VALIDATE_ROWS, "the map rows"),
    treeTypes = readOperand(validate, VALIDATE_TREES, "the tree types"),
  }
  expectBytes(validate + VALIDATE_ENCLOSED, { 0xE8 }, "the crenellation test")
  m.enclosed = validate + VALIDATE_ENCLOSED + 5 + core.readInteger(validate + VALIDATE_ENCLOSED + 1)
  -- isTileEnclosedByWalls: mov eax, [esp+8] / push esi / shl eax, 5
  expectBytes(m.enclosed, { 0x8B, 0x44, 0x24, 0x08, 0x56, 0xC1, 0xE0, 0x05 }, "the crenellation test")

  m.tms = core.readInteger(scan(AOB_TILE_FLAGS, "the tile flags") + TILE_FLAGS_OPERAND) - TMS_FLAGS

  -- 5. The raised part of a crenellation can be walked over, but not stood on.
  if options.walkableCrenellations then
    local linkSelf = scan(AOB_LINK_SELF, "the path link test for crenellations")
    local neighbour = scan(AOB_LINK_NEIGHBOUR, "the path link test for crenellations")
    core.writeCode(linkSelf + LINK_SELF_IMM, { 0, 0, 0, 0 })
    core.writeCode(neighbour + LINK_NEIGHBOUR_IMM, { 0, 0, 0, 0 })
    -- a group spreading out on a wall is never given one as its place
    local spreadWall = scan(AOB_SPREAD_WALL, "where a group spreads out on a wall")
    local spreadAny = scan(AOB_SPREAD_ANY, "where a group spreads out")
    jumpTo(spreadWall, assemble(templates.spreadWall, {
      FLAGS = m.tms + TMS_FLAGS, RESUME = spreadWall + SPREAD_WALL_SIZE,
    }), SPREAD_WALL_SIZE)
    jumpTo(spreadAny, assemble(templates.spreadAny, {
      FLAGS = m.tms + TMS_FLAGS, TAKE = spreadAny + SPREAD_ANY_SIZE + 0x1E,
      NEXT = spreadAny + SPREAD_ANY_SIZE,
    }), SPREAD_ANY_SIZE)
    -- ladders and siege towers may set up against them too
    core.writeCode(scan(AOB_LADDER_WALL, "where a ladder is leant against a wall") + LADDER_WALL_IMM,
      { 0x02, 0, 0, 0 })
    core.writeCode(scan(AOB_WALL_PAIR, "where troops are sent to a wall") + WALL_PAIR_IMM, { 0, 0, 0, 0 })

    m.setPosition = scan(AOB_SET_POSITION, "where a unit is put down")
    m.setDestination = scan(AOB_SET_DESTINATION, "the unit route search") - SET_DESTINATION_START
    local tick = scan(AOB_UNIT_TICK, "the unit update loop")
    local pushOff = luaFunction("moving a unit off a crenellation", makePushOff(m))
    local counts = core.allocate(MAX_UNITS * 5, true)
    local long = math.min(255, math.max(1,
      (options.ladderWait * TICKS_PER_SECOND + CHECK_TICKS - 1) // CHECK_TICKS))
    jumpTo(tick, assemble(templates.unitTick, {
      STATE = data, TICKS = core.readInteger(scan(AOB_TICKS, "the tick counter") + TICKS_OPERAND),
      UNITS_OFF = UNITS_FROM_STATE, TILES = TILES, FLAGS = m.tms + TMS_FLAGS, PUSH_OFF = pushOff,
      MAX_UNITS = MAX_UNITS, COUNTS = counts, LAST = counts + MAX_UNITS, LONG = long,
      RESUME = tick + UNIT_TICK_SIZE,
    }), UNIT_TICK_SIZE)
  end

  -- 6. Ladders and siege towers take on diagonal walls.
  if options.diagonalSiege then
    local tableStart = scan(AOB_PAIR_TABLE, "the directions troops look for a wall in")
    local tableEnd = scan(AOB_PAIR_TABLE_END, "the directions troops look for a wall in")
    local directions = core.allocate(8 * #PAIR_DIRECTIONS, true)
    for i, d in ipairs(PAIR_DIRECTIONS) do
      core.writeInteger(directions + 8 * (i - 1), d[1])
      core.writeInteger(directions + 8 * (i - 1) + 4, d[2])
    end
    core.writeCode(tableStart + 1, { core.itob(directions) })
    core.writeCode(tableEnd + 2, { core.itob(directions + 8 * #PAIR_DIRECTIONS) })

    local search = scan(AOB_FREE_TILE, "where a siege tower docks")
    expectBytes(search + FREE_TILE_UNITS[1], FREE_TILE_UNITS[2], "where a siege tower docks")
    m.units = core.readInteger(search + FREE_TILE_UNITS[1] + 2) - U_TILE
    m.tileY = readOperand(search, FREE_TILE_Y, "the tile rows")
    m.pathFinding = readOperand(search, FREE_TILE_PF, "the path finder")
    expectBytes(search + FREE_TILE_NAVIGATE, { 0xE8 }, "the area test")
    m.navigate = search + FREE_TILE_NAVIGATE + 5 + core.readInteger(search + FREE_TILE_NAVIGATE + 1)
    m.buildingTypes = readOperand(search, FREE_TILE_TYPES, "the building types")
    local diagonal = luaFunction("docking a siege tower on a diagonal wall", makeDiagonalDock(m))
    local game = assemble(templates.freeTileGame, { RESUME = search + FREE_TILE_SIZE })
    jumpTo(search, assemble(templates.freeTile, {
      STATE = data, GAME_SEARCH = game, DIAGONAL = diagonal,
    }), FREE_TILE_SIZE)
  end

  -- 7. Assassins climb onto a crenellation's raised part.
  if options.walkableCrenellations then
    local search = scan(AOB_ASSASSIN_SEARCH, "the assassins' route search")
    for _, at in ipairs(ASSASSIN_TARGET) do
      expectBytes(search + at, ASSASSIN_TARGET_BYTES, "the assassins' climb test")
    end
    for _, at in ipairs(ASSASSIN_TARGET) do
      core.writeCode(search + at + 2, { core.itob(SIEGE_BLOCKED & ~F_RAISED) })
    end
  end

  -- 8. A new crenellation is as tall as the wall (or stairs) it is attached to.
  if options.crenellationHeights then
    local site = checked(place, PLACE_CRENEL_CALL, "the crenellation height test")
    local towersOnly = site + 5 + core.readInteger(site + 1)
    expectBytes(towersOnly, { 0x8B, 0x44, 0x24, 0x08, 0xC1, 0xE0, 0x05 }, "the crenellation height test")
    local rule = makeCrenelHeight(m)
    local height = luaFunction("working out a crenellation's height", function()
      local h, low = rule(core.readInteger(m.data + D_CREN_TMS), core.readInteger(m.data + D_CREN_X),
        core.readInteger(m.data + D_CREN_Y))
      if h ~= nil and h > 0 then
        core.writeInteger(m.data + D_CREN_HEIGHT, h)
        core.writeInteger(m.data + D_CREN_LOW, low and 1 or 0)
      end
    end)
    jumpTo(site, assemble(templates.crenelHeight, {
      STATE = data, HEIGHT = height, LIVE_OFF = TMS_LIVE, TOWERS_ONLY = towersOnly,
      AFTER_CALL = checked(place, PLACE_CRENEL_AFTER, "the crenellation height test"),
      PARITY = checked(place, PLACE_CRENEL_PARITY, "the crenellation pattern"),
    }), 5)
  end

  -- 1 and 2. The route of a dragged wall.
  if routing then
    local route = luaFunction("working out a wall's route", makeRouter(m, options))
    local prepare = assemble(templates.prepare, { STATE = data, ROUTE = route, MAX_AGE = MAX_AGE })
    for name, f in pairs(FUNCTIONS) do
      local start = starts[name]
      local step = checked(start, { f.step, f.stepBytes }, "the step to the next wall tile")
      local loop = checked(start, { f.loop, f.loopBytes }, "the wall tile loop")
      local done = checked(start, { f.done, f.doneBytes }, "the end of the wall tile loop")
      jumpTo(step, assemble(templates[f.template], {
        STATE = data, ACTIVE = D_ON[name], IDX = D_IDX[name], COUNT = D_COUNT, PATH = D_PATH,
        ROWS = m.rows, TOP = loop, DONE = done, RESUME = step + f.stepSize,
      }), f.stepSize)
    end
    for name, f in pairs(FUNCTIONS) do
      local start = starts[name]
      local script = templates.entry:gsub("ORIGINAL", f.original)
      jumpTo(start, assemble(script, {
        STATE = data, ACTIVE = D_ON[name], IDX = D_IDX[name], FRESH = f.fresh, PREPARE = prepare,
        RESUME = start + f.size,
      }), f.size)
    end
  end

  -- 3 and 4. Damaged stairs and crenellations.
  if restoring then
    local site = checked(place, { PLACE_RESTORE.at, PLACE_RESTORE.bytes }, "the wall repair test")
    local restore = luaFunction("repairing stairs or crenellations", makeRestore(m, options))
    jumpTo(site, assemble(templates.restore, {
      STATE = data, REPAIR = restore, RECORD = record,
      FLAGS_OFF = TMS_FLAGS, LIVE_OFF = TMS_LIVE, DAMAGE_OFF = TMS_DAMAGE,
      UNDAMAGED = checked(place, PLACE_UNDAMAGED, "the wall repair test"),
      DAMAGED = checked(place, PLACE_DAMAGED, "the wall repair test"),
      STAIRS_BUILT = checked(place, PLACE_COUNTED, "the new wall tile code"),
      SKIP = place + FUNCTIONS.place.step,
      FREE_BUILT = checked(place, PLACE_FREE, "the wall path update"),
    }), PLACE_RESTORE.size)

    if not routing then
      local f = FUNCTIONS.place
      jumpTo(place, assemble(templates.placeEntry:gsub("ORIGINAL", f.original), {
        STATE = data, RESUME = place + f.size,
      }), f.size)
    end

    if options.stairs then
      local recordSite = scan(AOB_DAMAGE_RECORD, "the wall damage code")
      jumpTo(recordSite, assemble(templates.record, {
        RECORD = record, FLAGS_OFF = TMS_FLAGS, LIVE_OFF = TMS_LIVE, DAMAGE_OFF = TMS_DAMAGE,
        SCRATCH = core.readInteger(recordSite + 2), RESUME = recordSite + DAMAGE_RECORD_SIZE,
      }), DAMAGE_RECORD_SIZE)
      local forgetSite = scan(AOB_DAMAGE_FORGET, "the wall removal code")
      jumpTo(forgetSite, assemble(templates.forget, {
        RECORD = record, FLAGS_OFF = TMS_FLAGS, RESUME = forgetSite + DAMAGE_FORGET_SIZE,
      }), DAMAGE_FORGET_SIZE)
    end
  end
end

return {
  enable = enable,
  disable = function(self, config) end,
}

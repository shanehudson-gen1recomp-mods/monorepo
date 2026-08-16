-- Resident ghost rows against the voxel families' capture contract.
-- The Dramatic Shape family's posesOf reads, for every ow.ghosts row,
-- g.npc:pose() plus g.npc.py and g.npc.cellX/cellY (the neighbour-map
-- ground lookup) ON THE FRAME THE ROW APPEARS -- before the engine's
-- ghost update loop has ever touched it -- and their pipelines latch
-- to 2D on the first failed frame.  The engine's own ghost rows are
-- built from live npcs, which always carry cell coordinates, so ours
-- must too from birth.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local function mkmap(id)
  return {
    id = id, def = { tileset = "OVERWORLD" },
    widthCells = 30, heightCells = 30,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 30 and y < 30
    end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
    cellTile = function() return 0 end,
  }
end
local route1, route2 = mkmap("ROUTE_1"), mkmap("ROUTE_2")
local ow = {
  entities = {}, npcs = {}, ghosts = {}, neighbors = {},
  camera = { x = 0, y = 0 }, tod = "DAY",
  player = { cellX = 15, cellY = 15, px = 240, py = 240,
    facing = "up", moving = false },
  map = route1,
}
ow.neighbors = { { map = route2, ox = 480, oy = 0 } }
package.loaded["src.core.Game"] = {
  data = Data, overworld = ow, save = { party = {} },
  renderer = { worldViewSize = function() return 160, 144 end },
  input = { isDown = function() return false end,
    wasPressed = function() return false end },
  mods = { exports = {} },
}
local OC = { update = function() end, draw = function() end }
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = { field = function() return {} end }

Data.encounters.ROUTE_1 = { grass = { rate = 25, slots = {
  { species = "PIDGEY", level = 3 }, { species = "SPEAROW", level = 4 } } } }
Data.encounters.ROUTE_2 = Data.encounters.ROUTE_1

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.eq(#run.errors, 0, "loads clean")
run.loader.events:emit("game.ready")

-- deterministic spawn-friendly randomness, enough ticks for the
-- resident sync cadence (0.5s) to inject neighbour ghosts
local origRandom = love.math.random
love.math.random = function(a, b)
  if a and b then return a end
  if a then return a == 1000 and 2 or 1 end
  return 0.9
end
for _ = 1, 8 do OC.update(ow, 0.5) end
love.math.random = origRandom

T.check(#ow.ghosts > 0, "resident ghosts injected for the neighbour")

-- the capture, the way the voxel families run it, with NO ghost update
-- in between: pose plus the neighbour-map ground lookup off cellX/cellY
local allOk = true
for _, g in ipairs(ow.ghosts) do
  local ok = pcall(function()
    local sprite, vx, vy = g.npc:pose()
    assert(sprite ~= nil, "pose returned no sprite")
    assert((g.map or ow.map):inBounds(g.npc.cellX, g.npc.cellY) ~= nil)
    local _ = (g.npc.py + g.oy) + (vx + g.ox) + (g.npc.py - vy)
  end)
  allOk = allOk and ok
end
T.check(allOk,
  "every ghost row survives the voxel capture on its injection frame")

for _, g in ipairs(ow.ghosts) do
  T.check(type(g.npc.cellX) == "number" and type(g.npc.cellY) == "number",
    "ghost carries cell coordinates from birth")
  break
end

run.release()
T.finish("wild_skies_voxel_ghost")

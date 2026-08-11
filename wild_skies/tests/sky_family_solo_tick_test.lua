-- The shipped Free Fly + Wild Skies pair must share one update dispatcher
-- without suppressing Wild Skies' local (non-networked) spawn simulation.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local ow = {
  entities = {}, npcs = {}, ghosts = {}, neighbors = {},
  camera = { x = 0, y = 0 }, tod = "DAY",
  player = { cellX = 15, cellY = 15, px = 240, py = 240,
    facing = "up", moving = false },
  map = {
    id = "ROUTE_1", def = { tileset = "OVERWORLD" },
    widthCells = 30, heightCells = 30,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 30 and y < 30
    end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
  },
}
local Game = {
  data = Data, overworld = ow, save = { party = {} },
  renderer = { worldViewSize = function() return 160, 144 end },
  input = { isDown = function() return false end,
    wasPressed = function() return false end },
  mods = { exports = {} },
}
package.loaded["src.core.Game"] = Game
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local sourceMap = ow.map
local neighborMap = {
  id = "ROUTE_2", def = { tileset = "OVERWORLD" },
  widthCells = 30, heightCells = 30,
  inBounds = sourceMap.inBounds,
  isWalkableCell = sourceMap.isWalkableCell,
  isWaterCell = sourceMap.isWaterCell,
}
ow.neighbors = { { map = neighborMap, ox = 480, oy = 0 } }

local emitMapExit = function() end
local OC = { update = function() end, draw = function() end,
  crossConnection = function(self, _, conn)
    emitMapExit()
    self.map = conn.map
    self.neighbors = conn.neighbors or {}
    self.entities = {}
    return true
  end }
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = { field = function() return {} end }

local wsDir = os.getenv("MOD_DIR") or "mods/wild_skies"
local ffDir = wsDir:gsub("wild_skies", "free_fly")
local wildsDir = os.getenv("WILDS_MOD_DIR")
  or "mods/overworld_wild_spawns_integration"
local run = T.sdk.loadMods({ wildsDir, ffDir, wsDir }, { data = Data })
T.eq(#run.errors, 0, "Wilds and both sky-family mods load cleanly")
emitMapExit = function()
  run.loader.events:emit("map.exited", { mapId = ow.map and ow.map.id })
end
run.loader.events:emit("game.ready")

T.check(OC.__freeFlyTick ~= nil and OC.__wildSkiesTick ~= nil,
  "both per-frame ticks are registered")
T.check(OC.update == OC.__skyUpdateWrap,
  "both mods share the installed dispatcher")

local origRandom = love.math.random
love.math.random = function(a, b)
  if a and b then return a end
  if a then return a == 1000 and 2 or 1 end
  return 0.9
end
OC.update(ow, 5)
love.math.random = origRandom

T.check(#ow.entities >= 1,
  "the combined dispatcher advances solo Wild Skies spawning")
local spawned = ow.entities[#ow.entities]
local spawnedX, spawnedY = spawned.px, spawned.py
OC.update(ow, 1 / 60)
T.check(#ow.entities >= 1 and ow.entities[#ow.entities] == spawned,
  "a solo flyer survives the frame after it spawns")
T.check(spawned.px ~= spawnedX or spawned.py ~= spawnedY
    or spawned.mode == "ground",
  "the surviving solo flyer advances its presentation state")
T.check(#ow.ghosts > 0 and ow.ghosts[1].wildSkiesResidentGhost == true,
  "solo play pre-seeds visible neighbor skies on the ghost surface")
local destinationGhost = ow.ghosts[1].npc
local ghostStartX, ghostStartY = destinationGhost.px, destinationGhost.py
OC.__wildSkiesTick(ow, 1 / 120)
destinationGhost:update()
T.check(destinationGhost.px ~= ghostStartX or destinationGhost.py ~= ghostStartY
    or destinationGhost.mode == "ground",
  "a resident neighbor flyer advances at the live simulation cadence")
local destinationX, destinationY = destinationGhost.px, destinationGhost.py
T.check(OC.crossConnection(ow, "north", { map = neighborMap,
  neighbors = { { map = sourceMap, ox = -480, oy = 0 } } }),
  "the solo player crosses into the pre-seeded neighbor")
local destinationFlyer
for _, entity in ipairs(ow.entities) do
  if entity.wildSkiesFlyer then destinationFlyer = entity; break end
end
T.check(destinationFlyer ~= nil,
  "the visible neighbor population becomes the current solo field")
T.eq(destinationFlyer.px, destinationX,
  "solo ghost-to-current handoff preserves displayed x")
T.eq(destinationFlyer.py, destinationY,
  "solo ghost-to-current handoff preserves displayed y")
T.check(#ow.ghosts > 0,
  "the area left behind remains populated on the neighbor ghost surface")

emitMapExit()
local liveFlyers = 0
for _, entity in ipairs(ow.entities) do
  if entity.wildSkiesFlyer then liveFlyers = liveFlyers + 1 end
end
T.eq(liveFlyers, 0, "a hard map exit clears the current resident sky")
for _, ghost in ipairs(ow.ghosts) do
  T.check(not ghost.wildSkiesResidentGhost,
    "a hard map exit clears resident neighbor presentations")
end

run.release()
T.finish("sky_family_solo_tick")

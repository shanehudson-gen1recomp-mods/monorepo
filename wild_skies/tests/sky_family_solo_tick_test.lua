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

local OC = { update = function() end, draw = function() end }
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = { field = function() return {} end }

local wsDir = os.getenv("MOD_DIR") or "mods/wild_skies"
local ffDir = wsDir:gsub("wild_skies", "free_fly")
local wildsDir = os.getenv("WILDS_MOD_DIR")
  or "mods/overworld_wild_spawns_integration"
local run = T.sdk.loadMods({ wildsDir, ffDir, wsDir }, { data = Data })
T.eq(#run.errors, 0, "Wilds and both sky-family mods load cleanly")
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

run.release()
T.finish("sky_family_solo_tick")

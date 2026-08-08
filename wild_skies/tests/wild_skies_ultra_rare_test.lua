-- The ultra-rare roll: one spawn in a thousand under an open outdoor
-- sky is a legendary bird instead of the map's own pick.  It arrives
-- bold and alone; peaceful town air never rolls it (a shy legend would
-- be an uncatchable tease).
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local ow = {
  entities = {},
  camera = { x = 0, y = 0 },
  player = { cellX = 15, cellY = 15, px = 240, py = 240 },
  tod = "DAY",
  map = {
    id = "ROUTE_1",
    def = { tileset = "OVERWORLD" },
    widthCells = 30, heightCells = 30,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 30 and y < 30
    end,
    isWalkableCell = function() return true end,
  },
}
package.loaded["src.core.Game"] = {
  data = Data,
  overworld = ow,
  renderer = { worldViewSize = function() return 160, 144 end },
}
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

-- the spawner arms itself on game.ready; give it stub world modules
local OC = {}
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = { field = function() return {} end }
run.loader.events:emit("game.ready")
T.check(OC.__wildSkiesTick ~= nil, "ambient spawner armed")

local ULTRA = { ARTICUNO = true, ZAPDOS = true, MOLTRES = true }

-- a deterministic random: the 1-in-ULTRA_ODDS roll is the only
-- single-argument call with n = 1000, so it alone is steerable; every
-- other range call takes its low end and bare calls stay high enough
-- to skip the perch, flock and low-pass branches
local forced = 1
local origRandom = love.math.random
love.math.random = function(a, b)
  if a and b then return a end
  if a then return a == 1000 and forced or 1 end
  return 0.9
end

local function freshSky(mapId)
  run.loader.events:emit("map.exited")
  ow.map.id = mapId or ow.map.id
end

-- the roll hits: a legend crosses the route, bold and alone
forced = 1
OC.__wildSkiesTick(ow, 5)
T.eq(#ow.entities, 1, "one bird spawned, no flock")
local legend = ow.entities[1]
T.check(legend and ULTRA[legend.species], "and it is a legendary bird")
T.check(legend.level >= 48 and legend.level <= 52,
  "at its legendary level band")
T.eq(legend.bold, true, "a legend is always bold")

-- the other 999: the sky belongs to the map's own slots
freshSky()
forced = 2
OC.__wildSkiesTick(ow, 5)
T.check(#ow.entities >= 1, "an ordinary bird spawned")
T.eq(ULTRA[ow.entities[1].species], nil, "and it is no legend")

-- peaceful town air never rolls a legend, even when the odds would hit
freshSky("PALLET_TOWN")
forced = 1
OC.__wildSkiesTick(ow, 5)
T.check(#ow.entities >= 1, "town scenery spawned")
T.eq(ULTRA[ow.entities[1].species], nil, "no legend over a town")
T.eq(ow.entities[1].bold, false, "town birds stay shy")

love.math.random = origRandom
run.release()
T.finish("wild_skies_ultra_rare")

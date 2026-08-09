-- The flock seam: takeFlockmate hands over a bird while the ordinary
-- consumers rest, never hands over a legendary, and a sky-sourced
-- partner that survives an undecided battle returns to the air.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local ow = {
  entities = {},
  camera = { x = 0, y = 0 },
  player = { cellX = 15, cellY = 15, px = 240, py = 240 },
  map = {
    id = "ROUTE_1",
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

local api = run.loader.exports.wild_skies
T.eq(type(api.takeFlockmate), "function", "takeFlockmate exported")

local function spawnAt(species, level, cellX, cellY)
  for _ = 1, 8 do
    if api.spawnFlyer(species, level) then break end
  end
  local f = ow.entities[#ow.entities]
  T.check(f and f.species == species, species .. " spawned")
  f.cellX, f.cellY = cellX, cellY
  f.px, f.py = cellX * 16, cellY * 16
  f.t = 1
  return f
end

-- an empty sky has no flockmate
T.eq(api.takeFlockmate(15, 15, 8), nil, "empty sky: nil")

-- one bird up: taking a flyer starts the rest, the flockmate still
-- answers through it
local a = spawnAt("PIDGEOTTO", 18, 15, 14)
local b = spawnAt("FEAROW", 22, 16, 15)
local took = api.takeFlyer(15, 14, 1)
T.check(took and took.species == "PIDGEOTTO", "ordinary take works")
T.eq(api.flyerAt(16, 15, 8), nil, "the rest silences flyerAt")
local mate = api.takeFlockmate(15, 15, 8)
T.check(mate and mate.species == "FEAROW",
  "the flockmate answers through the rest")
T.eq(api.takeFlockmate(15, 15, 8), nil, "and the sky is empty again")

-- a legendary is never a flockmate
local u = spawnAt("ARTICUNO", 50, 15, 14)
u.bold = true
T.eq(api.takeFlockmate(15, 15, 8), nil, "the legendary is skipped")

-- ------- a surviving sky partner returns to the air

local before = #ow.entities
local fakeBattle = {
  enemy = { mon = { species = "RATTATA", hp = 0, level = 5 } },
  enemy2 = { mon = { species = "SPEAROW", hp = 7, level = 9 } },
}
run.loader.events:emit("mod.double_battles.double_started", {
  battle = fakeBattle, recruited = true, format = "1v2",
})
run.loader.events:emit("battle.ended", {
  battle = fakeBattle, result = "run",
})
local respawned
for i = before + 1, #ow.entities do
  local f = ow.entities[i]
  if f and f.species == "SPEAROW" then respawned = f end
end
T.check(respawned ~= nil, "the surviving bird is back in the sky")

-- a decided battle returns nobody
local beforeWin = #ow.entities
local fakeWin = {
  enemy = { mon = { species = "RATTATA", hp = 0, level = 5 } },
  enemy2 = { mon = { species = "SPEAROW", hp = 7, level = 9 } },
}
run.loader.events:emit("mod.double_battles.double_started", {
  battle = fakeWin, recruited = true, format = "1v2",
})
run.loader.events:emit("battle.ended", {
  battle = fakeWin, result = "win",
})
T.eq(#ow.entities, beforeWin, "a won battle respawns nothing")

run.release()
T.finish("wild_skies_flock")

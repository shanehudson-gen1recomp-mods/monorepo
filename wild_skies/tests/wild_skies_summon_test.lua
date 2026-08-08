-- The summon seam: a bold bird flies to the cell and is consumed with
-- flyer_summoned; every other ending emits summon_failed exactly once.
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
local summoned, failed
run.loader.events:on("mod.wild_skies.flyer_summoned",
  function(ev) summoned = ev end)
run.loader.events:on("mod.wild_skies.summon_failed",
  function(ev) failed = ev end)

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

-- an empty sky has nobody to call
local sid, why = api.summonFlyer(15, 15, { radius = 99 })
T.eq(sid, nil, "empty sky refuses")
T.eq(why, "nobody near", "and says why")

-- shy birds are never summonable
local shy = spawnAt("PIDGEY", 5, 16, 16)
shy.bold = false
sid, why = api.summonFlyer(15, 15, { radius = 99 })
T.eq(sid, nil, "shy bird not summonable")
shy.dead = true
table.remove(ow.entities, #ow.entities)

-- a summon that runs out of time reports too slow and releases the bird
local slow = spawnAt("PIDGEY", 5, 5, 5)
slow.bold = true
sid = api.summonFlyer(25, 25, { radius = 99 })
T.check(sid ~= nil, "summon accepted")
slow.summonBy = 0
slow:tick(ow, 0.1)
T.check(failed ~= nil and failed.summonId == sid, "too-slow reported")
T.eq(failed.reason, "too slow", "with the reason")
T.eq(slow.summonId, nil, "bird released")
T.eq(slow.mode, "roam", "and roams again")
slow.dead = true
table.remove(ow.entities, #ow.entities)

-- arrival consumes the bird and reports its identity
failed = nil
local bird = spawnAt("SPEAROW", 9, 16, 16)
bird.bold = true
sid = api.summonFlyer(16, 16, { radius = 2 })
T.check(sid ~= nil, "summon accepted at the destination")
bird:tick(ow, 0.1)
T.check(summoned ~= nil and summoned.summonId == sid, "arrival reported")
T.eq(summoned.species, "SPEAROW", "with the species")
T.eq(summoned.level, 9, "and the level")
T.check(bird.dead, "the bird left the sky")
T.eq(failed, nil, "no failure alongside the arrival")

-- the after-battle rest gates fresh summons like every battle seam
sid, why = api.summonFlyer(15, 15, { radius = 99 })
T.eq(why, "resting", "summons rest after a consumption")

run.release()
T.finish("wild_skies_summon")

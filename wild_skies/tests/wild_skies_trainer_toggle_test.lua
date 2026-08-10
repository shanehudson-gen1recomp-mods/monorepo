-- SKY TRAINERS is opt-in and airtight: OFF spawns nothing ever and
-- leaves the bird seams untouched; a spawned trainer lives in its own
-- list and is invisible to every flyer export.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local OC = {}
OC.update = function() end
OC.draw = function() end
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = {
  field = function() return {} end }

local ow = {
  entities = {},
  camera = { x = 0, y = 0 },
  tod = "DAY",
  player = { cellX = 25, cellY = 25, px = 400, py = 400 },
  map = {
    id = "ROUTE_13",
    def = { tileset = "PLAINS" },
    widthCells = 40, heightCells = 40,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 40 and y < 40
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
Data.sprites.SPRITE_COOLTRAINER_M = Data.sprites.SPRITE_COOLTRAINER_M
  or { image = "fixture_trainer.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")
run.loader.events:emit("game.ready")

local api = run.loader.exports.wild_skies
local dbg = api.__skyTrainerDebug
T.check(type(dbg.spawn) == "function" and type(dbg.list) == "function",
  "debug seam carries spawn and list")

-- both options exist with the safe defaults
local optionRows = {}
for _, row in ipairs(run.loader.optionSchemas.wild_skies or {}) do
  optionRows[row.key] = row
end
T.check(optionRows.trainers ~= nil
  and optionRows.trainers.default == false,
  "SKY TRAINERS option defined, default OFF")
T.check(optionRows.rematches ~= nil
  and optionRows.rematches.default == false,
  "REMATCHES option defined, default OFF")

-- OFF: the ambient roll never produces a trainer, however long we wait
for _ = 1, 500 do OC.__wildSkiesTick(ow, 0.5) end
T.eq(#dbg.list(), 0, "OFF: no trainer after 500 ticks")

-- and the bird seams behave exactly as always
for _ = 1, 8 do
  if api.spawnFlyer("PIDGEY", 5) then break end
end
local bird = ow.entities[#ow.entities]
T.check(bird and bird.species == "PIDGEY", "bird still spawns")
bird.cellX, bird.cellY, bird.t = 10, 10, 1
bird.px, bird.py = 160, 160
local seen = api.flyerAt(10, 10, 1)
T.check(seen and seen.species == "PIDGEY", "flyerAt still sees birds")
bird.dead = true
OC.__wildSkiesTick(ow, 0.05)

-- the debug seam spawns regardless of the option (tests and scenario
-- work), placing the trainer and its rider ghost
local before = #ow.entities
local tr = dbg.spawn(1)
T.check(tr ~= nil, "debug spawn returns the trainer")
T.eq(#dbg.list(), 1, "trainer in its own list")
T.eq(#ow.entities - before, 2, "mount and rider both attached")
T.check(tr.rider ~= nil, "rider ghost exists")
local rSprite, _, rY = tr.rider:pose()
local _, _, mY = tr:pose()
T.check(rSprite ~= nil, "rider has a sprite")
T.eq(rY, mY - 6, "rider seated 6px above the mount")
T.eq(tr.donor.class, "OPP_BIRD_KEEPER", "carries its donor class")
T.check(type(tr.donor.party) == "number", "and party index")
T.check(tr.mount and tr.mount.species ~= nil, "rides a mount")
T.check(tr.hailer == true or tr.hailer == false, "hailer rolled")
local found = false
for _, e in ipairs(ow.entities) do
  if e == tr then found = true end
end
T.check(found, "trainer entity attached to the overworld")

-- flyer seams never see a trainer
tr.cellX, tr.cellY = 12, 12
tr.px, tr.py = 192, 192
tr.alt = 10
T.eq(api.flyerAt(12, 12, 2), nil, "flyerAt blind to trainers")
T.eq(api.takeFlyer(12, 12, 2), nil, "takeFlyer blind to trainers")
T.eq(api.takeFlockmate(12, 12, 3), nil, "takeFlockmate blind to trainers")
local sid, why = api.summonFlyer(12, 12, { radius = 3 })
T.eq(sid, nil, "summonFlyer blind to trainers")
T.eq(why, "nobody near", "with the empty-sky reason")

-- a dead trainer takes its rider with it
tr.dead = true
OC.__wildSkiesTick(ow, 0.05)
T.eq(#dbg.list(), 0, "dead trainer left the list")
for _, e in ipairs(ow.entities) do
  T.check(e ~= tr and e ~= tr.rider, "neither mount nor rider lingers")
end

run.release()
T.finish("wild_skies_trainer_toggle")

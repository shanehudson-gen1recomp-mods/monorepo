-- Sky trainer sight: a forward cone checked only while hovering or
-- perched, altitude-banded against WHATEVER flight system the player
-- uses (capability probe, never a mod id), grounded players visible
-- only to perched or low trainers, and never while the overworld is
-- busy engaging.
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
  player = { cellX = 13, cellY = 10, px = 208, py = 160 },
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
local flying, playerAlt = false, 0
local Game = {
  data = Data,
  overworld = ow,
  renderer = { worldViewSize = function() return 160, 144 end },
  stack = { top = function() return ow end },
  mods = { exports = { some_flight_mod = {
    isFlying = function() return flying end,
    altitude = function() return playerAlt end,
  } } },
}
package.loaded["src.core.Game"] = Game
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

local spotted
run.loader.events:on("mod.wild_skies.trainer_spotted",
  function(ev) spotted = ev end)

local function hoveringTrainer()
  local tr = dbg.spawn(1)
  T.check(tr ~= nil, "trainer spawned")
  tr.px, tr.py = 160, 160
  tr.cellX, tr.cellY = 10, 10
  tr.facing = "right"
  tr.mode = "commute"
  tr.hoverT = 5
  tr.alt = 40
  return tr
end

-- each case scans from a clean slate: spotting now launches the
-- engage (freeze + emote + await), so the harness clears those side
-- effects and holds the wanted mode; busy = the overworld is engaged
-- by someone else for the whole scan
local function scanFor(tr, seconds, mode, busy)
  spotted = nil
  tr.spotted = nil
  tr.cooldownT = 0
  ow.engaging = busy and true or nil
  ow.emote = nil
  mode = mode or "commute"
  for _ = 1, math.ceil(seconds / 0.1) do
    if not tr.spotted then
      tr.mode = mode
      if mode == "commute" then tr.hoverT = 5 end
    end
    OC.__wildSkiesTick(ow, 0.1)
  end
  return spotted
end

-- airborne player in the cone at matching altitude: spotted
local tr = hoveringTrainer()
flying, playerAlt = true, 40
local ev = scanFor(tr, 1)
T.check(ev ~= nil, "same-band airborne player in the cone is spotted")
T.eq(ev.oppClass, "OPP_BIRD_KEEPER", "payload carries the donor class")
T.check(type(ev.partyIndex) == "number", "and the party index")

-- one band up: invisible
flying, playerAlt = true, 80
T.eq(scanFor(tr, 1), nil, "a 40px altitude gap hides the flyer")

-- behind the trainer: invisible
flying, playerAlt = true, 40
ow.player.cellX, ow.player.px = 7, 112
T.eq(scanFor(tr, 1), nil, "no eyes in the back of the head")
ow.player.cellX, ow.player.px = 13, 208

-- grounded player vs a cruising trainer: invisible
flying, playerAlt = false, 0
T.eq(scanFor(tr, 1), nil, "walkers are safe from high patrols")

-- grounded player vs a perched trainer: spotted
tr.alt, tr.perchAlt = 0, 0
T.check(scanFor(tr, 1, "perch") ~= nil,
  "a perched trainer spots the walker")

-- a busy overworld suppresses every scan
T.eq(scanFor(tr, 1, "perch", true), nil,
  "no sighting while the overworld engages")
ow.engaging = nil

-- while moving (no hover), the cone never runs
tr.mode = "commute"
tr.alt = 40
flying, playerAlt = true, 40
spotted, tr.spotted = nil, nil
tr.cooldownT = 0
ow.engaging, ow.emote = nil, nil
tr.hoverT = 0
tr.hoverIn = 60
OC.__wildSkiesTick(ow, 0.1)
T.eq(spotted, nil, "no scanning mid-flap")

-- the trainer code never names a flight mod: capability probe only
local src = assert(io.open((os.getenv("MOD_DIR") or "mods/wild_skies")
  .. "/main.lua")):read("*a")
local trainerCode = src:match("%-%- %-%-%-%-%-%-%- sky trainers.-mod%.exports%.spawnFlyer")
T.check(trainerCode ~= nil, "trainer section located")
T.eq(trainerCode:find("free_fly", 1, true), nil,
  "no free_fly reference in trainer code")
T.eq(trainerCode:find("DRAMATIC", 1, true), nil,
  "no Dramatic Sky Ride reference in trainer code")

run.release()
T.finish("wild_skies_trainer_sight")

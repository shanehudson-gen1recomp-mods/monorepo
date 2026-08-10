-- The Pidgeot bench fallback: a rosterless rider's Pidgeot joins the
-- enemy party through the trainer.party hook, ONLY for battles this
-- mod queued, never for vanilla encounters with the same class.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
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
  isOverworld = true,
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
  runner = {
    isRunning = function() return false end,
    run = function() end,
  },
}
local Game = {
  data = Data,
  save = { flags = {} },
  overworld = ow,
  renderer = { worldViewSize = function() return 160, 144 end },
  stack = { top = function() return ow end },
  mods = { exports = { some_flight_mod = {
    isFlying = function() return true end,
    altitude = function() return 40 end,
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

local dbg = run.loader.exports.wild_skies.__skyTrainerDebug

local function standoffWith(mount)
  local tr = dbg.spawn(1)
  T.check(tr ~= nil, "trainer spawned")
  tr.px, tr.py = 160, 160
  tr.cellX, tr.cellY = 10, 10
  tr.facing = "right"
  tr.mode = "commute"
  tr.hoverT = 5
  tr.alt = 40
  if mount then tr.mount = mount end
  for _ = 1, 8 do
    OC.__wildSkiesTick(ow, 0.1)
    if tr.spotted then break end
    tr.hoverT = 5
  end
  T.check(tr.spotted, "spotted")
  local done = ow.emote.onDone
  ow.emote = nil
  done()
  for _ = 1, 300 do
    OC.__wildSkiesTick(ow, 0.05)
    if tr.mode ~= "swoop" then break end
  end
  T.eq(tr.mode, "standoff", "standoff reached")
  return tr
end

local function callHook(class, party)
  local roster = Data.trainers[class].parties[party]
  return Runtime.call("trainer.party", function(_, _, p) return p end,
    class, party, roster) or roster
end

-- stamped battle with a fallback mount: the Pidgeot joins the bench
local tr = standoffWith({ species = "PIDGEOT", level = 26,
                          fallback = true })
local before = #Data.trainers.OPP_BIRD_KEEPER.parties[tr.donor.party]
local party = callHook("OPP_BIRD_KEEPER", tr.donor.party)
T.eq(#party, before + 1, "bench grew by one")
T.eq(party[#party].species, "PIDGEOT", "and it is the Pidgeot")
T.eq(party[#party].level, 26, "at the fitted level")
T.eq(#Data.trainers.OPP_BIRD_KEEPER.parties[tr.donor.party], before,
  "the shared roster table was never mutated")
run.loader.events:emit("battle.started", {})
run.loader.events:emit("battle.ended", { result = "run" })
tr.dead = true
OC.__wildSkiesTick(ow, 0.05)

-- the same class unstamped (a vanilla encounter): untouched
local party2 = callHook("OPP_BIRD_KEEPER", tr.donor.party)
T.eq(#party2, before, "vanilla battles gain nothing")

-- a stamped battle whose mount is a real roster mon: untouched
ow.engaging = nil
local tr2 = standoffWith(nil)
T.check(tr2.mount.fallback ~= true, "donor 1 rides its own bird")
local party3 = callHook("OPP_BIRD_KEEPER", tr2.donor.party)
T.eq(#party3, before, "a real mount adds no bench")
run.loader.events:emit("battle.started", {})
run.loader.events:emit("battle.ended", { result = "run" })

run.release()
T.finish("wild_skies_trainer_party")

-- The engage choreography: spot -> freeze + "!" -> swoop to the player
-- -> standoff that queues the donor's challenge and battle (or just a
-- hail), with the watchdog guaranteeing ow.engaging can never stick.
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

local queued = {}
local runnerBusy = false
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
    isRunning = function() return runnerBusy end,
    run = function(_, rows) queued[#queued + 1] = rows end,
  },
}
local flying, playerAlt = true, 40
local Game = {
  data = Data,
  save = { flags = {} },
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

local dbg = run.loader.exports.wild_skies.__skyTrainerDebug
local engaged
run.loader.events:on("mod.wild_skies.trainer_engaged",
  function(ev) engaged = ev end)

local function freshTrainer(hailer)
  local tr = dbg.spawn(1)
  T.check(tr ~= nil, "trainer spawned")
  tr.px, tr.py = 160, 160
  tr.cellX, tr.cellY = 10, 10
  tr.facing = "right"
  tr.mode = "commute"
  tr.hoverT = 5
  tr.alt = 40
  tr.hailer = hailer
  return tr
end

local function driveToStandoff(tr)
  for _ = 1, 8 do
    OC.__wildSkiesTick(ow, 0.1)
    if tr.spotted then break end
    tr.hoverT = 5
  end
  T.check(tr.spotted, "player spotted")
  T.eq(ow.engaging, true, "overworld frozen for the challenge")
  T.check(ow.emote ~= nil and ow.emote.npc == tr, "the ! bubble is ours")
  T.eq(tr.mode, "await", "holding under the bubble")
  local done = ow.emote.onDone
  ow.emote = nil
  done()
  T.eq(tr.mode, "swoop", "bubble over: swooping in")
  for _ = 1, 300 do
    OC.__wildSkiesTick(ow, 0.05)
    if tr.mode ~= "swoop" then break end
  end
end

-- fighter path: challenge text then the donor's own battle
local tr = freshTrainer(false)
driveToStandoff(tr)
T.eq(tr.mode, "standoff", "standoff reached")
T.check(engaged ~= nil and engaged.oppClass == "OPP_BIRD_KEEPER",
  "trainer_engaged emitted with the donor")
local rows = queued[#queued]
T.check(rows ~= nil, "a script was queued")
local last = rows[#rows]
T.eq(last[1], "start_battle", "battle row queued")
T.eq(last[2], "trainer", "as a trainer battle")
T.eq(last[3], "OPP_BIRD_KEEPER", "the donor class")
T.check(type(last[4]) == "number", "and the donor party")
T.eq(rows[1][1], "show_text", "the challenge line leads")

-- the battle starting hands the stack over and releases the freeze
run.loader.events:emit("battle.started", {})
T.eq(ow.engaging, false, "engaging released on battle start")
T.eq(tr.mode, "standby", "trainer waits out the battle")
tr.dead = true
OC.__wildSkiesTick(ow, 0.05)

-- refused queue: the freeze must not stick
runnerBusy = true
engaged = nil
local tr2 = freshTrainer(false)
driveToStandoff(tr2)
OC.__wildSkiesTick(ow, 0.05)
T.eq(ow.engaging, false, "refused battle releases the freeze")
T.check(tr2.mode ~= "standoff", "and the standoff broke off")
T.check((tr2.cooldownT or 0) > 0, "with a personal cooldown")
runnerBusy = false
tr2.dead = true
OC.__wildSkiesTick(ow, 0.05)

-- the watchdog: a queued battle that never starts times out
engaged = nil
queued = {}
local tr3 = freshTrainer(false)
driveToStandoff(tr3)
T.eq(tr3.mode, "standoff", "standoff reached again")
for _ = 1, 100 do OC.__wildSkiesTick(ow, 0.05) end
T.eq(ow.engaging, false, "watchdog released the freeze")
T.check(tr3.mode ~= "standoff", "and broke the standoff")
tr3.dead = true
OC.__wildSkiesTick(ow, 0.05)

-- hailer path: a chat, no battle, no lingering freeze
engaged = nil
queued = {}
local tr4 = freshTrainer(true)
driveToStandoff(tr4)
T.check(engaged ~= nil, "hailer still announces itself")
local hailRows = queued[#queued]
T.check(hailRows ~= nil and #hailRows >= 1, "hail text queued")
for _, row in ipairs(hailRows) do
  T.check(row[1] ~= "start_battle", "hailers never battle")
end
T.eq(ow.engaging, false, "hailer releases the freeze at once")
T.eq(tr4.mode, "leave", "and takes its leave")

-- ------- outcomes and the REMATCHES setting

local defeated
run.loader.events:on("mod.wild_skies.trainer_defeated",
  function(ev) defeated = ev end)

-- a win under REMATCHES OFF stamps the save flag, demotes the trainer
-- and retires the donor's fighter role for the save
queued = {}
local tr5 = freshTrainer(false)
driveToStandoff(tr5)
T.eq(tr5.mode, "standoff", "standoff for the win case")
run.loader.events:emit("battle.started", {})
T.eq(tr5.mode, "standby", "waiting out its battle")
run.loader.events:emit("battle.ended", { result = "win" })
T.check(defeated ~= nil and defeated.oppClass == "OPP_BIRD_KEEPER",
  "trainer_defeated emitted")
local flagName = "WILD_SKIES_SKY_TRAINER_OPP_BIRD_KEEPER_"
  .. tr5.donor.party
T.eq(Game.save.flags[flagName], true, "defeat flag stamped")
T.eq(dbg.donorAllowed(1, true), false, "donor fields no more fighters")
T.eq(dbg.donorAllowed(1, false), true, "but may still hail")
T.eq(tr5.hailer, true, "the beaten trainer is a hailer now")
T.check(tr5.mode ~= "standby", "and moved on")
tr5.dead = true
OC.__wildSkiesTick(ow, 0.05)

-- a run leaves no mark beyond the personal cooldown
Game.save.flags = {}
defeated = nil
queued = {}
local tr6 = freshTrainer(false)
driveToStandoff(tr6)
run.loader.events:emit("battle.started", {})
run.loader.events:emit("battle.ended", { result = "run" })
T.eq(defeated, nil, "no defeat on a run")
T.eq(next(Game.save.flags), nil, "no flag on a run")
T.eq(dbg.donorAllowed(1, true), true, "donor still fields fighters")
T.check((tr6.cooldownT or 0) > 0, "cooldown after the run")
T.eq(tr6.hailer, false, "still a fighter")
tr6.dead = true
OC.__wildSkiesTick(ow, 0.05)

-- REMATCHES ON: session memory only, the save stays clean
run.loader.modOptions = run.loader.modOptions or {}
run.loader.modOptions.wild_skies = { rematches = true }
defeated = nil
queued = {}
local tr7 = freshTrainer(false)
driveToStandoff(tr7)
run.loader.events:emit("battle.started", {})
run.loader.events:emit("battle.ended", { result = "win" })
T.check(defeated ~= nil, "defeat reported under rematches too")
T.eq(next(Game.save.flags), nil, "no save flag under REMATCHES")
T.eq(dbg.donorAllowed(1, true), false,
  "session memory retires the fighter for now")
tr7.dead = true
OC.__wildSkiesTick(ow, 0.05)

run.release()
T.finish("wild_skies_trainer_engage")

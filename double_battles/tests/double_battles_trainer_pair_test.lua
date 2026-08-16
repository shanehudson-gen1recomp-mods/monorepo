-- Adjacent trainer pairs, headless: an unfought trainer standing
-- within one cell of the engaged one joins the battle as a real pair
-- (no pair source needed), story battles and vetoes keep theirs
-- single, a pair win beats both trainers, and the side-B build is
-- announced through buildingPairSide() so trainer mods tracking "the
-- battle about to start" can stand down for the filler build.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local fakeOw = { pushBattle = function() end,
                 map = { id = "ROUTE_3", def = { label = "Route3" } } }
local fakeGame = {
  data = Data,
  overworld = fakeOw,
  save = {
    party = {}, options = {}, inventory = {},
    pokedex = { seen = {}, owned = {} },
    player = { name = "TEST" },
    defeatedTrainers = {}, flags = {},
  },
}
package.loaded["src.core.Game"] = fakeGame

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/double_battles",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")
fakeGame.mods = run.loader

local Pokemon = require("src.pokemon.Pokemon")
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 20)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 20)

local BattleState = require("src.battle.BattleState")
local OC = require("src.world.OverworldController")
local api = run.loader.exports.double_battles
local decorateHook = OC.__doubleBattlesDecorate

local CLASS_A = "OPP_BIRD_KEEPER"
local CLASS_B = "OPP_SUPER_NERD"

local function trainerNpc(id, class, index, cx, cy)
  return { id = id, cellX = cx, cellY = cy,
           def = { trainerClass = class, trainerParty = 1, index = index } }
end

local function freshTrainer(class, npcs)
  local b = BattleState.newTrainer(fakeGame, class, 1)
  T.check(b and not b.dead, "trainer battle built")
  b.checkpointOrigin = { kind = "trainer_encounter", map = fakeOw.map.id,
    npcId = "t1", trainerClass = class, partyIndex = 1 }
  fakeOw.npcs = npcs
  return b
end

-- ------- the pair forms

local engaged = trainerNpc("t1", CLASS_A, 1, 5, 5)
local buddy = trainerNpc("t2", CLASS_B, 2, 6, 5)
local seenSideBuild = false
local origNewTrainer = BattleState.newTrainer
BattleState.newTrainer = function(...)
  if api.buildingPairSide() then seenSideBuild = true end
  return origNewTrainer(...)
end
local b = freshTrainer(CLASS_A, { engaged, buddy })
decorateHook(fakeOw, b)
BattleState.newTrainer = origNewTrainer
T.check(b.__double, "the battle doubled")
local info = api.pairInfo(b)
T.check(info ~= nil, "and it is a trainer PAIR, not a 2v2")
T.eq(info.classA, CLASS_A, "pairInfo names the engaged class")
T.eq(info.classB, CLASS_B, "and the adjacent partner's class")
T.eq(info.takenOver, false, "trainer A holds the lead slot")
T.check(seenSideBuild,
  "buildingPairSide() was truthy during the side-B party build")
T.check(not api.buildingPairSide(), "and false outside it")
T.eq(b.oppClass, CLASS_A, "battle.oppClass stays the engaged class")

-- a pair win beats BOTH trainers
b.onFinish("win")
T.check(fakeGame.save.defeatedTrainers.t2 == true,
  "the partner is marked defeated on a win")

-- ------- guards keep battles single (they fall back to plain 2v2)

fakeGame.save.defeatedTrainers = {}
local far = trainerNpc("t2", CLASS_B, 2, 9, 5)
local b2 = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5), far })
decorateHook(fakeOw, b2)
T.check(api.pairInfo(b2) == nil,
  "a trainer four cells away never joins at TOUCHING reach")

-- PAIR DISTANCE widens the reach
run.loader.modOptions.double_battles = { pair_distance = 3 }
local near3 = trainerNpc("t2", CLASS_B, 2, 8, 5)
local b2b = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5), near3 })
decorateHook(fakeOw, b2b)
T.check(api.pairInfo(b2b) ~= nil, "3 CELLS reach pairs a trainer 3 away")
local b2c = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5),
                                    trainerNpc("t2", CLASS_B, 2, 9, 5) })
decorateHook(fakeOw, b2c)
T.check(api.pairInfo(b2c) == nil, "but never one 4 away")
run.loader.modOptions.double_battles = {}

local beaten = trainerNpc("t2", CLASS_B, 2, 6, 5)
fakeGame.save.defeatedTrainers.t2 = true
local b3 = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5), beaten })
decorateHook(fakeOw, b3)
T.check(api.pairInfo(b3) == nil, "a beaten trainer never rejoins")
fakeGame.save.defeatedTrainers = {}

-- story battles: anything with a scripted victory reward stays solo
local gymBuddy = trainerNpc("t2", "OPP_BROCK", 1, 6, 5)
local b4 = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5), gymBuddy })
decorateHook(fakeOw, b4)
T.check(api.pairInfo(b4) == nil, "a badge trainer never joins as a partner")

local b5 = BattleState.newTrainer(fakeGame, "OPP_BROCK", 1)
b5.checkpointOrigin = { kind = "trainer_encounter", map = fakeOw.map.id,
  npcId = "t1", trainerClass = "OPP_BROCK", partyIndex = 1 }
fakeOw.npcs = { trainerNpc("t1", "OPP_BROCK", 1, 5, 5),
                trainerNpc("t2", CLASS_B, 2, 6, 5) }
decorateHook(fakeOw, b5)
T.check(api.pairInfo(b5) == nil, "a badge battle never gains a partner")

-- another mod's AUTHORED trainer classes (AI Rivals' walkers) are
-- theirs: never conscripted as partners, and their own duels stay 1v1
-- unless that mod opts in through a pair source
local reg = run.loader.content and run.loader.content.trainers
T.check(reg ~= nil, "trainers registry reachable")
reg.ops["OPP_TEST_RIVAL"] = { { op = "register",
  value = { name = "RIVAL" }, owner = "ai_rivals" } }
Data.trainers.OPP_TEST_RIVAL = {
  parties = { { { species = "PIDGEY", level = 9 } } },
  baseMoney = 50,
}
local rivalNpc = trainerNpc("t2", "OPP_TEST_RIVAL", 2, 6, 5)
local b8 = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5),
                                   rivalNpc })
decorateHook(fakeOw, b8)
T.check(api.pairInfo(b8) == nil,
  "a mod-authored trainer is never conscripted as a partner")

local b9 = BattleState.newTrainer(fakeGame, "OPP_TEST_RIVAL", 1)
b9.checkpointOrigin = { kind = "trainer_encounter", map = fakeOw.map.id,
  npcId = "t1", trainerClass = "OPP_TEST_RIVAL", partyIndex = 1 }
fakeOw.npcs = { trainerNpc("t1", "OPP_TEST_RIVAL", 1, 5, 5),
                trainerNpc("t2", CLASS_B, 2, 6, 5) }
decorateHook(fakeOw, b9)
T.check(api.pairInfo(b9) == nil,
  "a mod-authored duel never gains a local partner")
reg.ops["OPP_TEST_RIVAL"] = nil
Data.trainers.OPP_TEST_RIVAL = nil

-- vetoes cover the auto-pair the way they cover wild doubles
T.eq(api.registerDoubleVeto({
  id = "test_no_pairs",
  veto = function(_, battle) return battle.kind == "trainer" end,
}), true, "veto registers")
local b6 = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5),
                                   trainerNpc("t2", CLASS_B, 2, 6, 5) })
decorateHook(fakeOw, b6)
T.check(api.pairInfo(b6) == nil, "a vetoed trainer battle stays unpaired")
T.eq(api.unregisterDoubleVeto("test_no_pairs"), true, "veto unregisters")

-- the option turns the whole convention off
run.loader.modOptions.double_battles = { trainer_pairs = false }
local b7 = freshTrainer(CLASS_A, { trainerNpc("t1", CLASS_A, 1, 5, 5),
                                   trainerNpc("t2", CLASS_B, 2, 6, 5) })
decorateHook(fakeOw, b7)
T.check(api.pairInfo(b7) == nil, "TRAINER PAIRS off keeps battles single")

run.release()
T.finish("double_battles_trainer_pair")

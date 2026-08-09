-- Vetoes and ally sources, headless: a registered veto keeps organic
-- wild encounters strictly 1v1 (wild_skies uses it for legendaries),
-- and an ally source picks WHICH party mon fights beside your lead
-- (free_fly puts the mount there), falling back to bench order for
-- anything that is not a healthy non-lead party member.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local fakeOw = { pushBattle = function() end }
local fakeGame = {
  data = Data,
  overworld = fakeOw,
  save = {
    party = {},
    options = {},
    inventory = {},
    pokedex = { seen = {}, owned = {} },
    player = { name = "TEST" },
  },
}
package.loaded["src.core.Game"] = fakeGame

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/double_battles",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

run.loader.modOptions.double_battles = { wild_doubles = "always" }

local Pokemon = require("src.pokemon.Pokemon")
local party = fakeGame.save.party
party[1] = Pokemon.new(Data, "PIDGEY", 12)
party[2] = Pokemon.new(Data, "RATTATA", 12)
party[3] = Pokemon.new(Data, "PIKACHU", 12)

local BattleState = require("src.battle.BattleState")
local OC = require("src.world.OverworldController")
local api = run.loader.exports.double_battles
local decorateHook = OC.__doubleBattlesDecorate

local function freshWild(species, level)
  local b = BattleState.newWild(fakeGame, species or "PIDGEY", level or 7)
  T.check(b and not b.dead, "wild battle built")
  return b
end

-- ------- vetoes

T.eq(select(1, api.registerDoubleVeto("nope")), false,
  "veto needs a table")
T.eq(select(1, api.registerDoubleVeto({ id = "x" })), false,
  "veto needs a veto function")

T.eq(api.registerDoubleVeto({
  id = "test_legendary",
  veto = function(game, battle)
    return battle.enemy.mon.species == "ARTICUNO"
  end,
}), true, "veto registers")

local b1 = freshWild("ARTICUNO", 50)
decorateHook(fakeOw, b1)
T.check(not b1.__double, "vetoed encounter stays 1v1")

local b2 = freshWild("PIDGEY", 7)
decorateHook(fakeOw, b2)
T.check(b2.__double, "other encounters still double")

T.eq(api.unregisterDoubleVeto("test_legendary"), true, "veto unregisters")
local b3 = freshWild("ARTICUNO", 50)
decorateHook(fakeOw, b3)
T.check(b3.__double, "without the veto the legendary doubles again")

-- ------- ally sources

T.eq(api.registerAllySource({
  id = "test_mount", priority = 10,
  provide = function() return party[3] end,
}), true, "ally source registers")
local b4 = freshWild()
decorateHook(fakeOw, b4)
T.check(b4.player2 ~= nil, "your side pairs up")
T.eq(b4.player2.mon, party[3], "the source's pick fights beside you")
api.unregisterAllySource("test_mount")

-- a pick that is not a party member falls back to bench order
local stray = Pokemon.new(Data, "MEW", 30)
T.eq(api.registerAllySource({
  id = "test_stray", priority = 10,
  provide = function() return stray end,
}), true, "stray source registered")
local b5 = freshWild()
decorateHook(fakeOw, b5)
T.eq(b5.player2.mon, party[2], "a non-party pick falls back to the bench")
api.unregisterAllySource("test_stray")

-- picking the lead itself falls through too
T.eq(api.registerAllySource({
  id = "test_lead", priority = 10,
  provide = function(game, battle) return battle.player.mon end,
}), true, "lead source registered")
local b6 = freshWild()
decorateHook(fakeOw, b6)
T.eq(b6.player2.mon, party[2], "the lead cannot be its own partner")
api.unregisterAllySource("test_lead")

-- ------- trainer pair sources

T.eq(select(1, api.registerTrainerPairSource({ id = "x" })), false,
  "pair source needs provide")
T.eq(api.registerTrainerPairSource({
  id = "test_ambush", priority = 10,
  provide = function() return "OPP_LASS", 1 end,
}), true, "pair source registers")
local tb = BattleState.newTrainer(fakeGame, "OPP_BUG_CATCHER", 1)
T.check(tb and not tb.dead, "trainer battle built")
decorateHook(fakeOw, tb)
T.check(tb.__double, "the organic trainer battle became a pair")
T.check(tb.__dbSideB ~= nil, "with a second trainer backing slot 2")
api.unregisterTrainerPairSource("test_ambush")

-- a refused class falls back to the ordinary trainer double
T.eq(api.registerTrainerPairSource({
  id = "test_broken", priority = 10,
  provide = function() return "OPP_NOBODY", 1 end,
}), true, "broken pair source registered")
local tb2 = BattleState.newTrainer(fakeGame, "OPP_BUG_CATCHER", 1)
T.check(tb2 and not tb2.dead, "second trainer battle built")
decorateHook(fakeOw, tb2)
T.check(tb2.__dbSideB == nil, "a refused class adds no phantom trainer")

run.release()
T.finish("double_battles_sources")

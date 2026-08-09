-- WILD DOUBLES on ALWAYS means a partner always joins.  The organic
-- seam (the decorate hook on OverworldController.pushBattle) is driven
-- directly: a healthy source supplies the partner, a broken source
-- falls back to the stand-in RATTATA, and a slotless map still sends
-- the lead foe's twin before the fallback is ever needed.
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
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)

local BattleState = require("src.battle.BattleState")
local OC = require("src.world.OverworldController")
local api = run.loader.exports.double_battles
local decorateHook = OC.__doubleBattlesDecorate
T.eq(type(decorateHook), "function", "organic decorate hook installed")

local function freshWild()
  local b = BattleState.newWild(fakeGame, "PIDGEY", 7)
  T.check(b and not b.dead, "wild battle built")
  return b
end

-- no sources, no map slots: the lead foe's twin still joins
local b1 = freshWild()
decorateHook(fakeOw, b1)
T.check(b1.__double, "slotless map still doubles")
T.eq(b1.enemy2.mon.species, "PIDGEY", "the twin fills the second slot")

-- a healthy registered source wins
T.eq(api.registerPartnerSource({
  id = "test_good", priority = 10,
  provide = function() return "ZUBAT", 9 end,
}), true, "healthy source registered")
local b2 = freshWild()
decorateHook(fakeOw, b2)
T.check(b2.__double, "sourced battle doubles")
T.eq(b2.enemy2.mon.species, "ZUBAT", "the source's species joins")
api.unregisterPartnerSource("test_good")

-- a source handing back garbage cannot cancel the double: the
-- stand-in RATTATA joins instead
T.eq(api.registerPartnerSource({
  id = "test_bad", priority = 10,
  provide = function() return "NOT_A_MON", 9 end,
}), true, "broken source registered")
local b3 = freshWild()
decorateHook(fakeOw, b3)
T.check(b3.__double, "refused species still doubles")
T.eq(b3.enemy2.mon.species, "RATTATA", "the stand-in RATTATA joins")
T.check((b3.enemy2.mon.level or 0) >= 2, "at a sane level")

-- airborne (any mod exporting isFlying: free_fly, Dramatic Sky Ride)
-- the stand-in is a PIDGEY: a rat cannot join a fight in the sky
fakeGame.mods = { exports = {
  DRAMATIC_SKY_RIDE = { isFlying = function() return true end },
} }
local b4 = freshWild()
decorateHook(fakeOw, b4)
T.check(b4.__double, "airborne battle still doubles")
T.eq(b4.enemy2.mon.species, "PIDGEY", "the sky stand-in is a PIDGEY")

-- grounded again: back to the rat
fakeGame.mods.exports.DRAMATIC_SKY_RIDE.isFlying = function()
  return false
end
local b5 = freshWild()
decorateHook(fakeOw, b5)
T.eq(b5.enemy2.mon.species, "RATTATA", "grounded stand-in stays RATTATA")
fakeGame.mods = nil
api.unregisterPartnerSource("test_bad")

run.release()
T.finish("double_battles_partner_fallback")

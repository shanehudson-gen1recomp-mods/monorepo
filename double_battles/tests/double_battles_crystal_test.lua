-- Crystal 251 compatibility, headless: the engine only announces lead
-- battlers over battle.battler_switched, but Crystal attaches its Gen 2
-- stat model per battler off that event, so double_battles announces
-- the second slots the moment the pair forms.  And the legendaries an
-- overhaul stages on its own terms (Crystal's roamers and sanctuary
-- catches) stay strictly 1v1 through a built-in veto.
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

-- the attach pattern Crystal 251 uses: every announced battler gets
-- its stat model; here we just remember who was announced
local announced = {}
run.loader.events:on("battle.battler_switched", function(ev)
  if ev and ev.battler then announced[#announced + 1] = ev.battler end
end)

local BattleState = require("src.battle.BattleState")
local OC = require("src.world.OverworldController")
local decorateHook = OC.__doubleBattlesDecorate

-- a wild double forms: both second slots are announced, sides attached
local b = BattleState.newWild(fakeGame, "PIDGEY", 7)
T.check(b and not b.dead, "wild battle built")
decorateHook(fakeOw, b)
T.check(b.__double, "the encounter doubled")
T.check(b.enemy2 ~= nil and b.player2 ~= nil, "both second slots filled")
local sawEnemy2, sawPlayer2 = false, false
for _, battler in ipairs(announced) do
  if battler == b.enemy2 then sawEnemy2 = true end
  if battler == b.player2 then sawPlayer2 = true end
end
T.check(sawEnemy2, "the second foe was announced to listeners")
T.check(sawPlayer2, "and so was your partner")

-- a Crystal roamer arrives: Raikou exists only once the overhaul
-- registers it, and it flees on Crystal's own class chain, so the
-- built-in veto keeps it 1v1
Data.pokemon.RAIKOU = (function()
  local src = Data.pokemon.PIKACHU
  local copy = {}
  for k, v in pairs(src) do copy[k] = v end
  copy.id, copy.name, copy.dex = "RAIKOU", "RAIKOU", 243
  return copy
end)()

local roamer = BattleState.newWild(fakeGame, "RAIKOU", 40)
T.check(roamer and not roamer.dead, "roamer battle built")
decorateHook(fakeOw, roamer)
T.check(not roamer.__double, "the roaming legend stays 1v1")

-- an ordinary Gen 2 wild still doubles (the veto is species-keyed)
Data.pokemon.HOOTHOOT = (function()
  local src = Data.pokemon.PIDGEY
  local copy = {}
  for k, v in pairs(src) do copy[k] = v end
  copy.id, copy.name, copy.dex = "HOOTHOOT", "HOOTHOOT", 163
  return copy
end)()
local owl = BattleState.newWild(fakeGame, "HOOTHOOT", 7)
T.check(owl and not owl.dead, "Gen 2 wild battle built")
decorateHook(fakeOw, owl)
T.check(owl.__double, "an ordinary Gen 2 species doubles fine")
T.check(owl.enemy2 ~= nil, "with a second foe on the field")

Data.pokemon.RAIKOU = nil
Data.pokemon.HOOTHOOT = nil
run.release()
T.finish("double_battles_crystal")

-- A decorated 2v2 turn, headless: real BattleState, real damage, four
-- real battlers, driven through the two-pass action flow with the queue
-- executed by hand.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local pushed
local fakeOw = { pushBattle = function(_, b) pushed = b end }
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

-- a two-mon party, built by the real constructor
local Pokemon = require("src.pokemon.Pokemon")
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 12)

local api = run.loader.exports.double_battles
local ok = api.startWildDouble("SPEAROW", 8, "ZUBAT", 8)
T.eq(ok, true, "double built and pushed")
T.check(pushed ~= nil and pushed.__double, "captured a decorated battle")

local b = pushed
T.eq(b.enemy2.mon.species, "ZUBAT", "second foe is the requested species")
T.check(b.player2 ~= nil, "the party pair fights together")
T.eq(b.player2.mon.species, "RATTATA", "partner is the second party mon")
T.eq(#b.sides[1].battlers, 2, "your side lists both battlers")
T.eq(#b.sides[2].battlers, 2, "their side lists both battlers")

-- pass A: picking a move with both foes up asks for a target
local moveA = { id = b.player.curMoves[1].id }
b:resolveTurn(moveA)
T.eq(b.phase, "db_target", "target prompt opens for the lead")

-- aim at the second foe and lock in: pass B begins on the partner
b.__dbTarget = b.enemy2
b:resolveTurn(moveA)
T.eq(b.phase, "menu", "the menu returns for the partner's pick")
T.check(b.__dbSwapped, "slots swapped so the menu belongs to the partner")

-- the partner picks; the whole turn resolves into the queue
local moveB = { id = b.player.curMoves[1].id }
b:resolveTurn(moveB)
T.eq(b.phase, "db_target", "the partner also aims")
b.__dbTarget = b.enemy
b:resolveTurn(moveB)
T.eq(b.phase, "messages", "four actions queued")
T.eq(b.turnCount, 1, "one turn counted")
T.check(not b.__dbSwapped, "slots swapped back before execution")

-- run every queued function by hand (text and anim rows just display)
local hpBefore = b.player.mon.hp + b.player2.mon.hp
  + b.enemy.mon.hp + b.enemy2.mon.hp
local i, guard = 1, 0
while i <= #b.queue and guard < 200 do
  local row = b.queue[i]
  b.nextInsert = i
  if type(row.fn) == "function" then pcall(row.fn) end
  i = i + 1
  guard = guard + 1
end
local hpAfter = b.player.mon.hp + b.player2.mon.hp
  + b.enemy.mon.hp + b.enemy2.mon.hp
T.check(hpAfter < hpBefore, "the turn drew blood somewhere")

run.release()
T.finish("double_battles_turn")

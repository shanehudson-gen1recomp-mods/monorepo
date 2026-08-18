-- Lead-choice mods, headless: "Trainers Let You Choose Lead Pokemon"
-- (and any mod using the same seam) inserts a party picker before the
-- intro's send-out wait and, when the player picks a different lead,
-- replaces battle.player with a freshly built battler mid-queue.  That
-- swap happens under our decoration, with no battler_switched (an
-- initial send-out is not a switch), so the pair state must re-anchor
-- itself when battle.player stops being the body we fielded.  The
-- stand-in below performs exactly that seam: find the Go! row, insert
-- a ui row before the send-out wait, then makeBattler + syncSides +
-- markParticipant on the pick.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local fakeOw = { pushBattle = function() end }
local fakeGame = {
  data = Data,
  overworld = fakeOw,
  input = { wasPressed = function() return false end },
  save = {
    party = {}, options = {}, inventory = {},
    pokedex = { seen = {}, owned = {} },
    player = { name = "TEST" },
    defeatedTrainers = {}, flags = {},
  },
  stack = { push = function() end, pop = function() end },
}
package.loaded["src.core.Game"] = fakeGame

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/double_battles",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local Pokemon = require("src.pokemon.Pokemon")
local party = fakeGame.save.party
party[1] = Pokemon.new(Data, "PIDGEY", 12)
party[2] = Pokemon.new(Data, "RATTATA", 12)
party[3] = Pokemon.new(Data, "PIKACHU", 12)

local BattleState = require("src.battle.BattleState")
local Timing = require("src.core.Timing")
local OC = require("src.world.OverworldController")

-- a decorated trainer 2v2 whose intro queue is really built (enter()
-- is what emits battle.started, the event lead-choice mods ride)
local function stagedTrainer()
  local b = BattleState.newTrainer(fakeGame, "OPP_BIRD_KEEPER", 1)
  T.check(b and not b.dead, "trainer battle built")
  OC.__doubleBattlesDecorate(fakeOw, b)
  T.check(b.__double and b.player2, "decorated to a 2v2")
  T.check(pcall(b.enter, b), "intro queue built")
  return b
end

-- the lead mod's Gen 1 seam, verbatim: reverse-find the native Go!
-- row, insert a picker ui row before the nearest send-out wait, and
-- on the pick rebuild battle.player from the chosen party mon
local function installLeadChoice(b)
  local goText = b:sendOutText(b.player.name)
  local goIndex
  for i = #b.queue, 1, -1 do
    if b.queue[i].text == goText then goIndex = i break end
  end
  T.check(goIndex ~= nil, "the native Go! row is in the queue")
  local goRow = b.queue[goIndex]
  local insertAt = goIndex
  for i = goIndex - 1, 1, -1 do
    if b.queue[i].wait == Timing.BATTLE_START_SENDOUT then
      insertAt = i
      break
    end
  end
  local pick
  table.insert(b.queue, insertAt, { ui = function()
    local mon = pick
    if not mon or mon == b.player.mon then return end
    local replacement = b.makeBattler(b.data, mon, true, b.game.save)
    T.check(replacement ~= nil, "the lead mod built its replacement")
    if b.participants then b.participants[b.player.mon] = nil end
    b.player = replacement
    b:syncSides()
    b:markParticipant()
    goRow.text = b:sendOutText(b.player.name)
  end })
  return function(mon)
    pick = mon
    b.queue[insertAt].ui()
  end
end

-- ------- picking a free bench mon keeps the pair coherent

local b = stagedTrainer()
T.eq(b.player.mon, party[1], "vanilla lead is party slot 1")
T.eq(b.player2.mon, party[2], "the partner is the next healthy mon")
local choose = installLeadChoice(b)
choose(party[3])
T.eq(b.player.mon, party[3], "the picked mon leads")
T.eq(b.player.dbAnchor, 1, "the new lead carries the lead anchor")
T.check(b.player2 and b.player2.mon == party[2], "the partner survived")
T.eq(b.sides[1].battlers[1], b.player, "sides track the new lead")
T.eq(b.sides[1].battlers[2], b.player2, "and still hold the partner")
T.check(b.participants[party[3]], "the new lead is a participant")
T.check(b.participants[party[2]], "so is the partner")
T.check(not b.participants[party[1]], "the benched vanilla lead is not")

-- ------- picking the mon already fielded as the partner: the pair
-- swaps instead of dissolving (this dropped the partner slot before)

b = stagedTrainer()
local oldLead = b.player
choose = installLeadChoice(b)
choose(party[2])
T.eq(b.player.mon, party[2], "the picked mon leads")
T.check(b.player2 ~= nil, "the pair survives the duplicate pick")
T.eq(b.player2, oldLead, "the old lead stepped into the partner slot")
T.eq(b.player.dbAnchor, 1, "lead anchor restamped")
T.eq(b.player2 and b.player2.dbAnchor, 2, "partner anchor restamped")
T.eq(b.sides[1].battlers[2], b.player2, "sides carry both bodies")
T.check(b.participants[party[2]] and b.participants[party[1]],
  "both fielded mons share the exp bookkeeping")

-- ------- the battle still runs a full pair turn after the swap

b.phase = "menu"
b:resolveTurn({ id = b.player.curMoves[1].id })
T.eq(b.phase, "db_target", "the swapped-in lead aims like any lead")
b:__dbAimReset()
b.__dbTarget = b.enemy
b:resolveTurn({ id = b.player.curMoves[1].id })
T.check(b.__dbSwapped, "pass B reaches the adopted partner")
b:resolveTurn({ id = b.player.curMoves[1].id })
b.__dbTarget = b.enemy
b:resolveTurn({ id = b.player.curMoves[1].id })
T.eq(b.phase, "messages", "the turn queued with both slots deciding")
T.eq(b.player.mon, party[2], "slots restored: the chosen lead in front")
T.eq(b.player2.mon, party[1], "the adopted partner beside it")

run.release()
T.finish("double_battles_choose_lead")

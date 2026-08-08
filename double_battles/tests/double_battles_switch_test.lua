-- Switching with your pair up, headless: the party pick asks WHICH of
-- yours steps back (LEFT/RIGHT aim, A locks, B cancels), the recall
-- spends that slot's action, the other slot still acts, and the swap
-- resolves before any move lands.  Also covers the 1v2 case where the
-- vanilla switch flow used to let the second foe skip its turn.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local pushed
local fakeOw = { pushBattle = function(_, b) pushed = b end }
local pressed = {}
local fakeGame = {
  data = Data,
  overworld = fakeOw,
  input = { wasPressed = function(_, key) return pressed[key] == true end },
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

local Pokemon = require("src.pokemon.Pokemon")
local party = fakeGame.save.party
party[1] = Pokemon.new(Data, "PIDGEY", 12)
party[2] = Pokemon.new(Data, "RATTATA", 12)
party[3] = Pokemon.new(Data, "PIKACHU", 12)

local api = run.loader.exports.double_battles

local function freshBattle()
  T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double up")
  local b = pushed
  T.check(b and b.__double and b.player2, "2v2 staged")
  return b
end

local function press(b, key)
  pressed[key] = true
  b:update(0.016)
  pressed[key] = nil
end

local function drain(b)
  local i, guard = 1, 0
  while i <= #b.queue and guard < 400 do
    local row = b.queue[i]
    b.nextInsert = i
    if type(row.fn) == "function" then pcall(row.fn) end
    i = i + 1
    guard = guard + 1
  end
end

-- ------- pass A recalls the lead itself

local b = freshBattle()
local lead, partner = b.player, b.player2
b:resolveSwitch(party[3])
T.eq(b.phase, "db_switch_target", "party pick opens the aim prompt")
T.eq(b.__dbSwitchAim, lead, "aim starts on the picking slot")

press(b, "right")
T.eq(b.__dbSwitchAim, partner, "the cursor reaches the partner")
T.eq(b.player, partner, "the aimed mon holds the lead slot for HUDs")
press(b, "left")
T.eq(b.__dbSwitchAim, lead, "and comes back")
T.eq(b.player, lead, "slots restored with it")

press(b, "a")
T.eq(b.phase, "menu", "the recall banks and the partner still picks")
T.check(b.__dbSwapped, "menu belongs to the partner now")
local moveB = { id = b.player.curMoves[1].id }
b:resolveTurn(moveB)
T.eq(b.phase, "db_target", "the partner aims its move")
b.__dbTarget = b.enemy
b:resolveTurn(moveB)
T.eq(b.phase, "messages", "turn queued")
local hpOut = party[1].hp
drain(b)
T.eq(b.player.mon, party[3], "the bench mon took the lead slot")
T.eq(b.player2.mon, party[2], "the partner never moved")
T.eq(party[1].hp, hpOut, "the withdrawn mon was not hit as a ghost")
T.check(b.participants and b.participants[party[3]],
  "the incoming mon shares the exp bookkeeping")
b.onFinish = nil

-- ------- pass A recalls the PARTNER: no second menu pass

b = freshBattle()
T.eq(b.player.mon, party[1], "a fresh battle leads with party slot 1")
local bench = party[3]
b:resolveSwitch(bench)
T.eq(b.phase, "db_switch_target", "prompt opens")
press(b, "right")
press(b, "a")
T.check(b.__dbForcedB and b.__dbForcedB.mon == bench,
  "the partner's recall is banked ahead of its pass")
T.eq(b.phase, "menu", "the lead keeps choosing")
T.check(not b.__dbSwapped, "still pass A")
local moveA = { id = b.player.curMoves[1].id }
b:resolveTurn(moveA)
T.eq(b.phase, "db_target", "the lead aims as usual")
b.__dbTarget = b.enemy
b:resolveTurn(moveA)
T.eq(b.phase, "messages", "pass B was skipped: both slots decided")
drain(b)
T.eq(b.player2.mon, bench, "the partner slot holds the bench mon")
T.eq(b.player.mon, party[1], "the lead stayed put")
b.onFinish = nil

-- ------- pass B recalls the already-banked lead

b = freshBattle()
local pika = b.player.mon
b:resolveTurn({ id = b.player.curMoves[1].id })
b.__dbTarget = b.enemy
b:resolveTurn({ id = b.player.curMoves[1].id })
T.check(b.__dbSwapped, "pass B underway")
local benchB
for _, m in ipairs(party) do
  if m ~= b.player.mon and m ~= b.player2.mon and (m.hp or 0) > 0 then
    benchB = m
    break
  end
end
T.check(benchB ~= nil, "a bench mon is free")
b:resolveSwitch(benchB)
T.eq(b.phase, "db_switch_target", "prompt opens mid pass B")
press(b, "right")
press(b, "a")
T.check(b.__dbSlotA and b.__dbSlotA.action
  and b.__dbSlotA.action.dbSwitch == benchB,
  "the lead's banked pick became its recall")
T.eq(b.phase, "menu", "the partner keeps choosing")
T.check(b.__dbSwapped, "still pass B")
local moveP = { id = b.player.curMoves[1].id }
b:resolveTurn(moveP)
b.__dbTarget = b.enemy
b:resolveTurn(moveP)
T.eq(b.phase, "messages", "turn queued")
drain(b)
T.eq(b.player.mon, benchB, "the lead was replaced by the bench mon")
T.check(b.player.mon ~= pika, "the voided pick's mon left the field")
b.onFinish = nil

-- ------- cancel restores everything

b = freshBattle()
local freeMon
for _, m in ipairs(party) do
  if m ~= b.player.mon and m ~= b.player2.mon and (m.hp or 0) > 0 then
    freeMon = m
    break
  end
end
b:resolveSwitch(freeMon)
press(b, "right")
press(b, "b")
T.eq(b.phase, "menu", "B backs out")
T.check(not b.__dbSwitchSwapped, "no lingering slot swap")
T.eq(b.__dbSwitchMon, nil, "no pending recall")
b.onFinish = nil

-- ------- 1v2: the switch runs through the turn, both foes act

b = freshBattle()
b.player2 = nil
b:syncSides()
local acted = {}
local origExec = b.executeAction
b.executeAction = function(self, user, target, action)
  acted[#acted + 1] = user
  return origExec(self, user, target, action)
end
local soloBench
for _, m in ipairs(party) do
  if m ~= b.player.mon and (m.hp or 0) > 0 then
    soloBench = m
    break
  end
end
b:resolveSwitch(soloBench)
T.eq(b.phase, "messages", "no prompt with one of yours out")
drain(b)
T.eq(b.player.mon, soloBench, "the switch landed")
local foesActed = 0
for _, u in ipairs(acted) do
  if u == b.enemy or u == b.enemy2 then foesActed = foesActed + 1 end
end
T.eq(foesActed, 2, "both foes took their turn through the switch")

run.release()
T.finish("double_battles_switch")

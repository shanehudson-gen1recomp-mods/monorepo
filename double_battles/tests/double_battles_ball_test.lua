-- Aimed ball throws, headless: with two wild Pokémon up the throw
-- defers into the target prompt, the confirm commits the aim so the
-- vanilla catch pipeline reads the aimed foe, and backing out refunds
-- the ball the bag already consumed.
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
  input = {
    wasPressed = function(_, key) return pressed[key] == true end,
    isDown = function(_, key) return pressed[key] == true end,
  },
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
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 12)

local api = run.loader.exports.double_battles

local function press(b, key)
  pressed[key] = true
  b:update(0.016)
  pressed[key] = nil
end

-- the engine queues the whole throw (toss, roll, outcome) as rows
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

-- ------- the throw defers, the confirm hits the aimed foe

T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double up")
local b = pushed
local lead, partner = b.enemy, b.enemy2

local thrownAt
local wrappedCatch = b.catchAttempt
b.catchAttempt = function(self, ball, rate)
  thrownAt = self.enemy
  return wrappedCatch(self, ball, rate)
end

b:throwBall("POKE_BALL")
T.eq(b.phase, "db_target", "the throw opens the aim prompt")
T.eq(b.__dbPendingBall, "POKE_BALL", "the ball waits on the aim")
T.eq(thrownAt, nil, "nothing thrown yet")

press(b, "right")
T.eq(b.enemy, partner, "the aimed foe holds the lead slot")
press(b, "a")
T.eq(b.__dbPendingBall, nil, "the pending ball is consumed")
T.eq(b.enemy, partner, "the commit keeps the aimed foe in the slot")
T.check(#b.queue > 0, "the toss chain is queued")
T.eq(b.phase, "messages", "and plays as messages")
drain(b)
T.eq(thrownAt, partner, "the catch rolled against the aimed foe")
T.eq(b.__dbBallAimed, nil, "the aim bypass is one-shot")
b.onFinish = nil

-- ------- backing out refunds the ball

T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double up")
local c = pushed
c:throwBall("GREAT_BALL")
T.eq(c.phase, "db_target", "prompt opens")
press(c, "b")
T.eq(c.phase, "menu", "B backs out to the menu")
T.eq(c.__dbPendingBall, nil, "no pending ball")
T.eq(fakeGame.save.inventory["GREAT_BALL"], 1,
  "the consumed ball came back to the bag")
c.onFinish = nil

-- ------- direct catchAttempt keeps the refusal, collapse is vanilla

T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double up")
local d = pushed
local caught, shakes = d:catchAttempt("POKE_BALL")
T.eq(caught, false, "direct catch with two up still refuses")
T.eq(shakes, 0, "with zero shakes")

d.enemy2 = nil
d:syncSides()
local direct
local wrapped2 = d.catchAttempt
d.catchAttempt = function(self, ball, rate)
  direct = true
  return wrapped2(self, ball, rate)
end
d:throwBall("POKE_BALL")
T.eq(d.__dbPendingBall, nil, "no prompt when only one foe is up")
drain(d)
T.check(direct, "collapsed battles throw straight through")

-- ------- a catch no longer ends the double: the survivor fights on

T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double up")
local e = pushed
local eLead, ePartner = e.enemy, e.enemy2
local partySize = #fakeGame.save.party
local finished
e.onFinish = function(result) finished = result end
local origCA = e.catchAttempt
e.catchAttempt = function(self, ball, rate)
  origCA(self, ball, rate)
  return true, 3
end
e:throwBall("POKE_BALL")
press(e, "right")
press(e, "a")
drain(e)
T.eq(#fakeGame.save.party, partySize + 1,
  "the caught partner joined the party")
T.eq(fakeGame.save.party[partySize + 1].species, ePartner.mon.species,
  "and it is the aimed foe")
T.eq(finished, nil, "the battle did not finish")
T.check(e.result == nil, "no caught result latched")
T.eq(e.afterQueue, "menu", "play returns to the menu")
T.eq(e.enemy, eLead, "the surviving foe holds the lead slot")
T.eq(e.enemy2, nil, "alone")
T.eq(e.enemy.dbAnchor, 1, "in the vanilla spot for the 1v1 endgame")
T.eq(e.enemyHidden, false, "the survivor's pic is shown")
T.eq(e.lockedBall, nil, "the resting ball left with the caught mon")
e.onFinish = nil

run.release()
T.finish("double_battles_ball")

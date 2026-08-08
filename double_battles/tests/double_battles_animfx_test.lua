-- Attack effects follow the acting partner, headless: the engine
-- resolves pic effects (lunge, DIG's hide, the hit blink) from a side
-- flag that lands on the slot lead, so a partner's attack used to play
-- on the lead.  The wrap redirects that resolution to whichever battler
-- the action actually involves, for the exact lifetime of the action.
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

local Pokemon = require("src.pokemon.Pokemon")
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 12)

local api = run.loader.exports.double_battles
T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double pushed")
local b = pushed
T.check(b and b.__double, "captured a decorated battle")

-- the wrap, side by side: with no action in flight the leads resolve
b.animAttackerIsPlayer = true
T.eq(b:animFxBattler(false), b.player, "idle: attacker side is the lead")
T.eq(b:animFxBattler(true), b.enemy, "idle: far side is the lead foe")

-- your partner attacks the lead foe: its own side resolves to it
b.__dbActingUser = b.player2
b.__dbActingTarget = b.enemy
T.eq(b:animFxBattler(false), b.player2,
  "partner acting: attacker side is the partner")
T.eq(b:animFxBattler(true), b.enemy,
  "partner acting: far side stays the aimed foe")

-- the second foe attacks your partner: both ends leave the leads
b.animAttackerIsPlayer = false
b.__dbActingUser = b.enemy2
b.__dbActingTarget = b.player2
T.eq(b:animFxBattler(false), b.enemy2,
  "second foe acting: attacker side is the second foe")
T.eq(b:animFxBattler(true), b.player2,
  "second foe acting: far side is your partner")

-- flipped requests (CallWithTurnFlipped) mirror cleanly
T.eq(b:animFxBattler(true), b.player2, "flipped lands on the target")
b.__dbActingUser, b.__dbActingTarget = nil, nil
T.eq(b:animFxBattler(false), b.enemy, "cleared markers restore the leads")

-- the act closures own the marker lifetime: through a real turn, every
-- executeAction call sees its own user in the marker
local seen = {}
local origExec = b.executeAction
b.executeAction = function(self, user, target, action)
  seen[#seen + 1] = { user = user, marked = self.__dbActingUser }
  return origExec(self, user, target, action)
end

local moveA = { id = b.player.curMoves[1].id }
b:resolveTurn(moveA)
b.__dbTarget = b.enemy
b:resolveTurn(moveA)
local moveB = { id = b.player.curMoves[1].id }
b:resolveTurn(moveB)
b.__dbTarget = b.enemy2
b:resolveTurn(moveB)
T.eq(b.phase, "messages", "turn queued")

local i, guard = 1, 0
while i <= #b.queue and guard < 300 do
  local row = b.queue[i]
  b.nextInsert = i
  if type(row.fn) == "function" then pcall(row.fn) end
  i = i + 1
  guard = guard + 1
end

T.check(#seen >= 3, "several actions executed")
for _, s in ipairs(seen) do
  T.eq(s.marked, s.user, "the acting marker matches the acting user")
end
T.eq(b.__dbActingUser, nil, "marker cleared at end of turn")
T.eq(b.__dbActingTarget, nil, "target marker cleared at end of turn")

run.release()
T.finish("double_battles_animfx")

-- SPIKE, not shipping code: can Gold's battle core host a second wild
-- foe as a DECORATION, the way the Gen 1 mod does it?  Vanilla core
-- runs the 1v1, the second foe acts in an extra half-turn through the
-- parameterised damage path, aiming swaps the foes around the vanilla
-- turn, and a lead faint PROMOTES the partner so the endgame is the
-- vanilla 1v1 the engine knows best.  Every wrap is instance-level and
-- lives in this file; the verdict this proves or kills is recorded in
-- docs/gen2-migration.md.
--
-- Fixtures follow tests/gen2_battle_test.lua (the engine's own): pure
-- tables in the shapes the extractor writes.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
}
local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
}
local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}
local function species(id, index, hp, speed, attack)
  return {
    id = id, index = index, name = id,
    -- fat HP and soft foe attacks: the deterministic roller max-rolls
    -- every hit, and the spike needs multi-round battles where the
    -- player comfortably outlives two attackers
    baseStats = { hp = hp, attack = attack or 45, defense = 40,
      speed = speed,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } },
    evolutions = {},
  }
end
local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = species("CYNDAQUIL", 155, 230, 65),
  PIDGEY = species("PIDGEY", 16, 230, 56, 5),
  SENTRET = species("SENTRET", 161, 230, 20, 5),
}
local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = {},
}
local function zeroRandom() return 0 end
local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }

local function mon(id, level)
  local m = Mon.new(DATA, id, level, { dvs = perfect })
  m.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  return m
end

-- ---------------------------------------------------------------- the spike

local player = mon("CYNDAQUIL", 5)
local foe1 = mon("PIDGEY", 5)
local battle = Battle.new({ data = DATA, party = { player },
                            wild = foe1, random = zeroRandom })
local foe2 = mon("SENTRET", 5)

-- decoration: the second foe hangs off the battle; nothing in the
-- vanilla core reads it
battle.enemy2 = foe2
battle.__double = true

-- promotion: when the lead foe falls and a partner stands, award the
-- fallen one's experience and seat the partner BEFORE the vanilla
-- faint pass looks for a winner (resolveFaints is a public method the
-- vanilla turn calls through the instance, so this runs mid-round too)
local promoted = 0
local origFaints = battle.resolveFaints
battle.resolveFaints = function(self)
  if (self.enemy.hp or 0) <= 0 and self.enemy2
     and (self.enemy2.hp or 0) > 0 then
    self:awardExperience(self.enemy)
    self.enemy = self.enemy2
    self.enemy2 = nil
    self.enemyParty = { self.enemy }
    self.enemyIndex = 1
    self:syncSides()
    promoted = promoted + 1
  end
  return origFaints(self)
end

-- the round: vanilla 1v1 first (aim swaps the foes around it), then
-- the second foe's half-turn through the parameterised damage path
local origTake = battle.takeTurn
battle.takeTurn = function(self, action)
  local aimed = action and action.dbTarget == 2 and self.enemy2 ~= nil
  if aimed then
    self.enemy, self.enemy2 = self.enemy2, self.enemy
  end
  local events = origTake(self, action)
  if aimed and self.enemy2 then
    -- promotion may have consumed the swap; only unswap when both
    -- slots still stand
    self.enemy, self.enemy2 = self.enemy2, self.enemy
  end
  if not self.over and self.enemy2 and (self.enemy2.hp or 0) > 0
     and (self.player.hp or 0) > 0 then
    self:useMove(self.enemy2, self.player, "TACKLE")
    self:resolveFaints()
    for _, e in ipairs(self:takeEvents()) do events[#events + 1] = e end
  end
  return events
end

-- 1. aiming: the swap sends the player's hit to the partner through
--    the vanilla core, sparing the lead
local f1, f2, p = foe1.hp, foe2.hp, player.hp
battle:takeTurn({ kind = "move", move = "TACKLE", dbTarget = 2 })
T.check(foe2.hp < f2, "an aimed hit lands on the partner")
T.eq(foe1.hp, f1, "and spares the lead")
T.check(player.hp < p, "the player was hit back")
local twoFoeRound = p - player.hp

-- 2. a plain round targets the lead, and both foes strike back
f1, f2, p = foe1.hp, foe2.hp, player.hp
battle:takeTurn({ kind = "move", move = "TACKLE" })
T.check(foe1.hp < f1, "the plain round hits the lead")
T.eq(foe2.hp, f2, "and leaves the partner alone")
T.eq(p - player.hp, twoFoeRound,
     "two foes land the same two hits every round")

-- 3. promotion: the lead falls, the partner steps up mid-round, the
--    fallen foe pays its experience, and the battle continues
local expBefore = player.experience
foe1.hp = 1
battle:takeTurn({ kind = "move", move = "TACKLE" })
T.eq(promoted, 1, "the fallen lead promoted its partner")
T.check(not battle.over, "the battle continues past the first faint")
T.eq(battle.enemy, foe2, "the partner holds the lead slot")
T.check(player.experience > expBefore,
        "the fallen foe paid its experience")

-- 4. with one foe left, the round halves: the decoration's extra
--    half-turn was real, and now it is gone
p = player.hp
battle:takeTurn({ kind = "move", move = "TACKLE" })
T.check((p - player.hp) < twoFoeRound,
        "a lone survivor lands only one hit a round")

-- 5. the endgame is vanilla: the last foe falls and the engine itself
--    calls the win
expBefore = player.experience
foe2.hp = 1
battle:takeTurn({ kind = "move", move = "TACKLE" })
T.check(battle.over, "the battle ends when the last foe falls")
T.eq(battle.outcome, "win", "with the engine's own win outcome")
T.check(player.experience > expBefore, "and the second exp award")

-- 6. side integrity: the promoted foe still reads as the enemy side
T.eq(battle:sideOf(foe2), "enemy", "promotion keeps the side honest")

T.finish("double_battles_gold_spike")

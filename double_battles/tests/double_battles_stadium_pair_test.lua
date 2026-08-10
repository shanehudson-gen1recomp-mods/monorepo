-- The STADIUM pair tier, headless: a fork carrying the full Stadium
-- family (Stadium + StadiumMon + StadiumPack) gets the partner standing
-- as its own 3D model beside the lead's.  No real fork here; fake
-- module tables carry the verified contract (begin/update/draw/cast/
-- footprint on the module table, StadiumMon's setSpecies/matrix/build,
-- StadiumPack.keep), and the adapter is asserted against them: pair
-- wiring, cover delegation, the trainer-flag borrow that stands the
-- lead model down on the card tier, partner geometry, the battle taps,
-- and the faint that waits for the bar.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local pushed
local fakeOw = {
  pushBattle = function(_, b) pushed = b end,
  afterBattle = function() end,
}
local fakeGame = {
  data = Data,
  overworld = fakeOw,
  input = { wasPressed = function() return false end },
  save = {
    party = {},
    options = {},
    inventory = {},
    pokedex = { seen = {}, owned = {} },
    player = { name = "TEST" },
  },
}
package.loaded["src.core.Game"] = fakeGame

local modDir = os.getenv("MOD_DIR") or "mods/double_battles"
local run = T.sdk.loadMod(modDir, { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local chunk = assert(loadfile(modDir .. "/lib/dramatic_shape.lua"))
local function alive(b)
  return (b and b.mon and b.mon.hp > 0) and true or false
end
local adapter = chunk()({
  log = { warn = function() end, info = function() end },
  alive = alive,
})

-- ------- the fake Stadium family

local PACKS = {}          -- dex -> truthy when the species "has a pack"
local kept = {}

local FakeMon = {}
FakeMon.__index = FakeMon
function FakeMon.new(side)
  return setmetatable({ side = side, state = "idle", scale = 1 }, FakeMon)
end
function FakeMon:setSpecies(dex)
  if dex == self.species then return self.rig ~= nil end
  self.species = dex
  self.rig = nil
  if dex and PACKS[dex] then
    local mon = self
    self.rig = {
      draw = function() mon.drawn = (mon.drawn or 0) + 1 end,
      caster = function() mon.shadow = (mon.shadow or 0) + 1 end,
    }
  end
  return self.rig ~= nil
end
function FakeMon:release() self.rig, self.species = nil, nil end
function FakeMon:request(state) self.state = state end
function FakeMon:attack(index)
  self.attacked = index
  self.state = "attack"
  return true
end
function FakeMon:play(state) self.state = state end
function FakeMon:update(dt) end
function FakeMon:worldRadius() return 10 end
function FakeMon:matrix(x, y, z) self.at = { x, y, z }; return { x, y, z } end
function FakeMon:build() self.built = (self.built or 0) + 1 end
function FakeMon:finished() return self.animDone or false end

local stActive = false
local origCovers = { enemy = true, player = true }
local coverCalls = 0
local updSeen
local fakeSt = {
  covers = function(battle, side)
    coverCalls = coverCalls + 1
    return origCovers[side]
  end,
  begin = function(arena) stActive = true; return true end,
  finish = function() stActive = false end,
  update = function(dt, battle, groundY)
    updSeen = { trainer = battle.showEnemyTrainer and true or false,
                back = battle.showPlayerBack and true or false }
  end,
  draw = function(pull) end,
  cast = function(shadowMap) end,
  active = function() return stActive end,
  footprint = function(side) return 12 end,
}
local fakePack = {
  load = function(dex) return PACKS[dex] end,
  keep = function(dex) kept[dex] = true end,
}
local fakeOv = {
  sideTexture = function() return nil end,
  hudTexture = function() return nil end,
}
fakeGame.mods = { exports = { VOXEL_FORK = { lib = {
  require = function(name)
    if name == "OverworldBattle" then return fakeOv end
    if name == "Stadium" then return fakeSt end
    if name == "StadiumMon" then return FakeMon end
    if name == "StadiumPack" then return fakePack end
    error("unexpected module " .. tostring(name))
  end,
} } } }

T.eq(adapter.tryInstall(), true, "stadium-family fork wired")
T.check(fakeSt.__doubleBattlesOrigBegin ~= nil, "begin wrapped")
T.check(fakeSt.__doubleBattlesOrigUpdate ~= nil, "update wrapped")
T.check(fakeSt.__doubleBattlesOrigFootprint ~= nil, "footprint wrapped")
local BattleState = require("src.battle.BattleState")
T.eq(BattleState.__doubleBattlesStadiumTaps, true, "battle taps installed")

-- a hot reload re-points, never stacks
local stUpdateProbe = fakeSt.__doubleBattlesOrigUpdate
adapter = chunk()({
  log = { warn = function() end, info = function() end },
  alive = alive,
})
T.eq(adapter.tryInstall(), true, "reload generation installs")
T.eq(fakeSt.__doubleBattlesOrigUpdate, stUpdateProbe,
  "reload keeps the once-stored original")

-- ------- a real decorated 2v2 on the model tier

local Pokemon = require("src.pokemon.Pokemon")
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 12)

local api = run.loader.exports.double_battles
T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double pushed")
local b = pushed
T.check(b and b.__double and b.enemy2 and b.player2, "full 2v2 up")

local function dexFor(battler)
  local def = battler and battler.mon
    and Data.pokemon[battler.mon.species]
  return def and def.dex
end
for _, battler in ipairs({ b.player, b.player2, b.enemy, b.enemy2 }) do
  PACKS[dexFor(battler)] = true
end

fakeSt.begin({ player = { 0, 0 }, enemy = { 0, 100 }, map = {} })
T.check(stActive, "the original begin ran")
local s = fakeSt.__doubleBattlesPairState
T.check(s and s.arena ~= nil, "arena captured for the pair")

fakeSt.update(0.016, b, 0)
T.eq(s.covering.enemy, true, "enemy pair ready: partner has a model")
T.eq(s.covering.player, true, "player pair ready too")
T.eq(updSeen.trainer, false, "no borrow while the pair covers")
T.eq(updSeen.back, false, "player side unborrowed too")

local em = s.mons.enemy
T.check(em and em.rig, "enemy partner mon built")
T.check(kept[em.species] == true, "partner species pinned in the cache")

-- covers delegates to the original while the pair is ready
coverCalls = 0
T.eq(fakeSt.covers(b, "enemy"), true, "covered side keeps the models")
T.check(coverCalls > 0, "the original covers decided")
T.eq(s.coversLead.enemy, true, "the answer is recorded for the draws")
fakeSt.covers(b, "player")

-- geometry: axis enemy(0,100)->player(0,0) puts the lateral step on +x;
-- spacing is lead footprint 12 + own radius 10 + 6
fakeSt.update(0.016, b, 0)
T.check(em.at ~= nil, "partner placed")
T.eq(em.at[1], 28, "partner one spacing off the axis")
T.eq(em.at[3], 100, "partner on its lead's row")
T.check(em.built and em.built > 0, "partner posed and skinned")

-- the draws and the sun both see the partner
em.drawn, em.shadow = 0, 0
fakeSt.draw("pull")
T.eq(em.drawn, 1, "partner model drawn")
fakeSt.cast("shadowmap")
T.eq(em.shadow, 1, "partner casts its shadow")

-- the B-mode disc widens to the pair, live
T.eq(fakeSt.footprint("enemy"), 38, "disc widened: spacing + radius")

-- ------- the battle taps drive the partner's model

b.__dbStadiumAttack = { battler = b.enemy2, index = 33 }
fakeSt.update(0.016, b, 0)
T.eq(em.attacked, 33, "partner move played on its own model")
T.eq(b.__dbStadiumAttack, nil, "the tap is consumed")

-- the faint waits for the bar the player reads as the death
b.enemy2.faintQueued = true
b.enemy2.mon.hp = 0
b.enemy2.shownHP = 5
b.__dbStadiumFaints = { [b.enemy2] = true }
fakeSt.update(0.016, b, 0)
T.check(em.state ~= "faint", "collapse held while the bar drains")
T.eq(em.visible, true, "dead partner still on its feet meanwhile")
b.enemy2.shownHP = 0
fakeSt.update(0.016, b, 0)
T.eq(em.state, "faint", "collapse fires when the bar empties")

-- revive the slot for the fallback checks
b.enemy2.faintQueued = nil
b.enemy2.mon.hp = 10
em.state = "idle"

-- ------- no pack: the side rides the cards and the lead stands down

PACKS[dexFor(b.enemy2)] = nil
em.species = false  -- force the next setSpecies through the pack probe
fakeSt.update(0.016, b, 0)
T.eq(s.covering.enemy, false, "packless partner: pair not ready")
T.eq(updSeen.trainer, true, "lead model stood down via the borrow")
T.eq(b.showEnemyTrainer, nil, "and the flag restored after")
coverCalls = 0
T.eq(fakeSt.covers(b, "enemy"), false, "side rides the cards")
T.eq(coverCalls, 0, "decided without the original")
fakeSt.draw("pull")
T.eq(em.drawn, 1, "no partner draw on the card tier")

-- pack returns: the side climbs back to the models
PACKS[dexFor(b.enemy2)] = true
em.species = false
fakeSt.update(0.016, b, 0)
T.eq(s.covering.enemy, true, "pair recovers when the pack is back")

-- ------- collapse to 1v1: everything delegates again

b.enemy2.mon.hp = 0
fakeSt.update(0.016, b, 0)
coverCalls = 0
T.eq(fakeSt.covers(b, "enemy"), true, "collapsed side: covers delegates")
T.check(coverCalls > 0, "the original covers ran")

-- ------- finish releases the pair

fakeSt.finish()
T.eq(s.arena, nil, "arena dropped at finish")
T.eq(next(s.mons), nil, "partner mons released")

-- ------- begin missed: wired mid-battle, the pair still recovers
--
-- The mode's begin runs while the battle is staged, which can be
-- before this adapter is wired (installed off the battle-started
-- event).  The update hook must key its state on the battle itself
-- and fetch the arena live, or the side rides the cards forever with
-- the lead's model drawn behind them.

fakeOv.arena = function() return { player = { 0, 0 }, enemy = { 0, 100 } } end
stActive = true          -- the mode is live; our begin wrap never saw it
b.enemy2.mon.hp = 10
fakeSt.update(0.016, b, 0)
T.check(s.arena ~= nil, "arena fetched live off the public getter")
T.eq(s.covering.enemy, true, "pair covers without a seen begin")
T.check(s.mons.enemy and s.mons.enemy.rig, "partner mon rebuilt")

-- and with no arena reachable at all, the side rides the cards with
-- the lead's model stood down rather than doubling the draw
fakeOv.arena = nil
fakeSt.begin({ player = { 0, 0 }, enemy = { 0, 100 }, map = {} })
s.arena = nil            -- as if the stage had never been picked up
fakeSt.update(0.016, b, 0)
T.eq(s.covering.enemy, false, "no arena: pair not ready")
T.eq(updSeen.trainer, true, "lead model stood down on the card tier")
T.eq(fakeSt.covers(b, "enemy"), false, "side rides the cards")

run.release()
T.finish("double_battles_stadium_pair")

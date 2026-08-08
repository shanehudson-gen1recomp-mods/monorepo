-- Aiming and the HUD, headless: while the target prompt is up the
-- aimed foe occupies battle.enemy for the WHOLE frame, so every HUD
-- (native draw, wide panels, render.hud chrome like gen1_modern_ui's
-- cards) names the Pokémon under the cursor.  Sticky anchors keep the
-- sprites in place; the slots are restored before turn logic runs.
-- Also covers the blackout wiring on mod-launched battles (onFinish ->
-- afterBattle, the engine path that revives and warps after a wipe).
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local pushed
local afterBattleCalls = {}
local fakeOw = {
  pushBattle = function(_, b) pushed = b end,
  afterBattle = function(_, result, b)
    afterBattleCalls[#afterBattleCalls + 1] = { result = result, battle = b }
  end,
}
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
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 12)

local api = run.loader.exports.double_battles
T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double pushed")
local b = pushed
T.check(b and b.__double, "captured a decorated battle")

local lead, partner = b.enemy, b.enemy2

local function press(key)
  pressed[key] = true
  b:update(0.016)
  pressed[key] = nil
end

-- open the target prompt
b:resolveTurn({ id = b.player.curMoves[1].id })
T.eq(b.phase, "db_target", "target prompt opens")
T.eq(b.__dbAimBattler, lead, "aim starts on the lead")

-- classic geometry through the real draw: record where each battler's
-- pic lands (the stub reads real sprite PNG dimensions)
local placed
local lastImg
local origPicImage = b.picImage
b.picImage = function(self, sprite)
  lastImg = origPicImage(self, sprite)
  return lastImg
end
b.drawBattlerPic = function(self, battler, x, y, sc)
  placed[battler] = { x = x, y = y, sc = sc or 1,
    w = lastImg and lastImg:getWidth() or 0,
    h = lastImg and lastImg:getHeight() or 0 }
end
local function frame()
  placed = {}
  b:draw()
  return placed
end

local restFrame = frame()
press("right") -- aim at the partner (slots swapped)
local aimFrame = frame()
press("left") -- back to the lead for the rest of the test

T.check(restFrame[lead] and aimFrame[lead], "lead drawn in both frames")
T.eq(aimFrame[lead].x, restFrame[lead].x,
  "the lead does not jump when the aim switches")
T.eq(aimFrame[lead].y, restFrame[lead].y,
  "nor does it move vertically")
local pp = restFrame[partner]
T.check(pp ~= nil, "partner drawn")
T.check(pp.x + pp.w * pp.sc <= 96, "partner stays out of the lead slot")
T.check(pp.y >= 26, "partner stays below the enemy HUD")
local ally = restFrame[b.player2]
T.check(ally ~= nil, "your partner drawn")
T.check(ally.x + ally.w * ally.sc <= 96,
  "your partner stays out of the foe slot")

-- spy at the root of the frame: whoever reads battle.enemy while the
-- prompt is up must see the aimed battler
local hudEnemy, hudPlayer
b.drawClassic = function(self)
  hudEnemy, hudPlayer = self.enemy, self.player
end

b:draw()
T.eq(hudEnemy, lead, "aiming at the lead: HUD reads the lead")

press("right")
T.eq(b.__dbAimBattler, partner, "cursor moved to the second foe")
T.eq(b.enemy, partner, "the aimed foe holds the lead slot")
b:draw()
T.eq(hudEnemy, partner, "aiming at the partner: any frame reader sees it")
T.eq(lead.dbAnchor, 1, "lead keeps its spot on screen")
T.eq(partner.dbAnchor, 2, "partner keeps its spot on screen")

press("left")
T.eq(b.enemy, lead, "aiming back restores the slots")
b:draw()
T.eq(hudEnemy, lead, "HUD follows back to the lead")

-- cancel must also restore the slots
press("right")
press("b")
T.eq(b.phase, "moveSelect", "B backs out to the move menu")
T.eq(b.enemy, lead, "cancel restores the lead slot")
T.check(not b.__dbAimSwapped, "no lingering swap after cancel")

-- lock the partner in; slots restore before turn logic, and pass B
-- (your second mon's pick) owns the player HUD
b:resolveTurn({ id = b.player.curMoves[1].id })
press("right")
press("a")
T.eq(b.phase, "menu", "menu returns for your partner's pick")
T.eq(b.enemy, lead, "lock-in restores the lead slot")
b:draw()
T.eq(hudPlayer.mon, fakeGame.save.party[2], "player HUD shows the partner")

-- blackout wiring: a lost mod-launched battle must reach afterBattle,
-- the engine path that revives the party and warps to the heal point
T.eq(type(b.onFinish), "function", "mod-launched battle has onFinish")
b.onFinish("lose")
T.eq(#afterBattleCalls, 1, "loss reaches afterBattle")
T.eq(afterBattleCalls[1].result, "lose", "with the lose result")
T.eq(afterBattleCalls[1].battle, b, "for this battle")

run.release()
T.finish("double_battles_hud")

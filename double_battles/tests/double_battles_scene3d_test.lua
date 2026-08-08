-- The Dramatic Shape adapter, headless: the voxel mod billboards each
-- side as one 160x144 canvas, so the adapter owns that canvas when a
-- side is doubled and composes both battlers into it, partner beside
-- lead.  No real Dramatic Shape here; fake module tables carry its
-- verified contract (sideTexture result shape, hudTexture reading
-- battle.enemy, Stadium.covers), and the adapter is asserted against
-- them: install idempotence, passthrough, pair composition geometry,
-- the hud slot borrow, and the covers fallback.
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

-- the adapter lib loads standalone; main.lua wires it with this env
local chunk = assert(loadfile(modDir .. "/lib/dramatic_shape.lua"))
local function alive(b)
  return (b and b.mon and b.mon.hp > 0) and true or false
end
local env = {
  log = { warn = function() end, info = function() end },
  alive = alive,
}
local adapter = chunk()(env)

-- ------- install: refused without DS, once wired never stacked

T.eq(adapter.tryInstall(), false, "no DS exports: install refused")
T.eq(adapter.installed(), false, "not installed yet")

local sideCalls, hudCalls, coverCalls = 0, 0, 0
local fakeCanvas = love.graphics.newCanvas(160, 144)
local origSideResult, lastHudEnemy

local fakeOv = {
  sideTexture = function(battle, side)
    sideCalls = sideCalls + 1
    origSideResult = { canvas = fakeCanvas, ax = 80, ay = 96 }
    return origSideResult
  end,
  hudTexture = function(battle, slide)
    hudCalls = hudCalls + 1
    lastHudEnemy = battle.enemy
    return "hud-layer"
  end,
}
local sideProbe = fakeOv.sideTexture
local fakeSt = {
  covers = function(battle, side)
    coverCalls = coverCalls + 1
    return true
  end,
}
fakeGame.mods = { exports = { DRAMATIC_SHAPE = { lib = {
  require = function(name)
    if name == "OverworldBattle" then return fakeOv end
    if name == "Stadium" then return fakeSt end
    error("unexpected module " .. tostring(name))
  end,
} } } }

T.eq(adapter.tryInstall(), true, "wired: install succeeds")
T.eq(adapter.installed(), true, "installed reports true")
T.eq(adapter.tryInstall(), true, "second call still true")
T.eq(fakeOv.__doubleBattlesOrigSideTexture, sideProbe,
  "the original is stored once")

-- a hot reload hands out a fresh adapter; it re-points, never stacks
local adapter2 = chunk()(env)
T.eq(adapter2.tryInstall(), true, "reload generation installs")
T.eq(fakeOv.__doubleBattlesOrigSideTexture, sideProbe,
  "reload keeps the once-stored original")

-- ------- non-double battles pass straight through

sideCalls = 0
local res = fakeOv.sideTexture({}, "enemy")
T.eq(sideCalls, 1, "non-double: original called exactly once")
T.eq(res, origSideResult, "non-double: result identical, untouched")

-- ------- a real decorated 2v2: the adapter owns the enemy texture

local Pokemon = require("src.pokemon.Pokemon")
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 12)

local api = run.loader.exports.double_battles
T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double pushed")
local b = pushed
T.check(b and b.__double, "captured a decorated battle")
local lead, partner = b.enemy, b.enemy2
b.frame = b.frame or 0

local placed, lastImg
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

placed = {}
sideCalls = 0
local own = fakeOv.sideTexture(b, "enemy")
T.eq(sideCalls, 0, "own path never calls the original")
T.check(type(own) == "table" and own.canvas ~= nil, "own texture returned")
T.check(own.canvas ~= fakeCanvas, "our canvas, not the original's")
T.eq(own.ax, 80, "ax is the forced pic column")
T.eq(own.ay, 96, "ay is the forced baseline")

local pl = placed[lead]
T.check(pl ~= nil, "lead drawn")
T.eq(pl.x, 80 - pl.w * pl.sc / 2, "lead centered on column 80")
T.eq(pl.y, 96 - pl.h * pl.sc, "lead feet on the baseline")
local pp = placed[partner]
T.check(pp ~= nil, "partner drawn")
T.eq(pp.x, 36 - pp.w * pp.sc / 2, "partner centered on column 36")
T.eq(pp.y, 96 - pp.h * pp.sc, "partner feet on the baseline")

-- the damage blink hides a battler mid-flicker; its card slot empties
b.fx = { blink = { target = partner, frames = 6 } }
b.frame = 0
placed = {}
fakeOv.sideTexture(b, "enemy")
T.check(placed[lead] ~= nil, "lead still drawn during partner blink")
T.eq(placed[partner], nil, "blinking partner suppressed")
b.fx = nil

-- ------- hudTexture: the acting partner borrows the slot pair

b.__dbFocus = partner
local trueHP = partner.mon.hp
partner.mon.hp = math.max(1, trueHP - 10)
partner.shownHP = trueHP
hudCalls, lastHudEnemy = 0, nil
local layer = fakeOv.hudTexture(b, 0)
T.eq(layer, "hud-layer", "hud result passes through")
T.eq(hudCalls, 1, "original hud called once")
T.eq(lastHudEnemy, partner, "hud rendered with the partner in the slot")
T.eq(b.enemy, lead, "lead slot restored after the render")
T.eq(b.enemy2, partner, "partner slot restored too")
T.eq(partner.shownHP, trueHP - 2, "shownHP eased by at most 2")
b.__dbFocus = nil

-- ------- Stadium.covers: doubled sides ride the flat cards

coverCalls = 0
T.eq(fakeSt.covers(b, "enemy"), false, "doubled side: no model cover")
T.eq(coverCalls, 0, "decided without the original")

-- ------- collapse back to 1v1: everything returns to the original

b.enemy2 = nil
b.enemy.dbAnchor = 1
sideCalls = 0
local back = fakeOv.sideTexture(b, "enemy")
T.eq(sideCalls, 1, "collapsed side: passthrough to the original")
T.eq(back, origSideResult, "and its result comes back untouched")

coverCalls = 0
T.eq(fakeSt.covers(b, "enemy"), true, "collapsed side: covers delegates")
T.eq(coverCalls, 1, "the original covers ran")

-- a lone survivor anchored at spot 2 keeps its own card position
b.enemy.dbAnchor = 2
placed = {}
sideCalls = 0
fakeOv.sideTexture(b, "enemy")
T.eq(sideCalls, 0, "lone spot-2 survivor: still our texture")
local ls = placed[b.enemy]
T.check(ls ~= nil, "survivor drawn")
T.eq(ls.x, 36 - ls.w * ls.sc / 2, "at the partner column it stood on")
b.enemy.dbAnchor = 1

run.release()
T.finish("double_battles_scene3d")

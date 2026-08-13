-- Free Fly's Gold arms end to end, headless: the badge-gated FREEFLY
-- entry, takeoff, the movement-immunity wraps on Gold's World class,
-- the wild-battle gate, the camera lift, the follower flight rules,
-- a water landing into Gold's surf state, and the New Bark gift
-- ceremony on the talkTo seam.  The world is a Gold-shaped stand-in
-- (stepBody marks it; the facade forwards live fields only), and the
-- real gen2 engine modules (World, Follower, FieldMoves, Mon) are the
-- ones the mod patches.  Every play-test bug this week lived in one
-- of these paths.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data"); Data:load()

Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }
-- the mod's own requires resolve through the REAL Gen 2 facades here,
-- so reads arrive renamed exactly as on a Gold boot: data.sprites is
-- gen2Sprites, and the fixture provides the gold-shaped tables
Data.gen2Sprites = { SPRITE_BIRD = { id = "SPRITE_BIRD",
  image = "fixture_bird.png", frames = 6, walker = true } }
Data.gen2Icons = { species = {}, icons = {} }
Data.gen2Palettes = {}
-- a Johto species for the gift, shaped like a real record
do
  local pidgey = Data.pokemon.PIDGEY
  local noctowl = {}
  for k, v in pairs(pidgey) do noctowl[k] = v end
  noctowl.id, noctowl.name, noctowl.dex = "NOCTOWL", "NOCTOWL", 164
  Data.pokemon.NOCTOWL = noctowl
end

local water = false
local map = {
  id = "ROUTE_29",
  def = { tileset = "OVERWORLD", environment = "ROUTE" },
  widthCells = 30, heightCells = 30,
  inBounds = function(_, x, y)
    return x >= 0 and y >= 0 and x < 30 and y < 30
  end,
  isWalkableCell = function() return not water end,
  isWaterCell = function() return water end,
  cellCollision = function() return 0 end,
  warpAtCell = function() return nil end,
  cellTile = function() return 0 end,
}
local player = {
  cellX = 15, cellY = 15, px = 240, py = 240,
  facing = "down", moving = false,
  tryMove = function() return "blocked" end,
}
local followerNpc = { pikachuFollower = true, cellX = 15, cellY = 16,
                      px = 240, py = 256,
                      draw = function() end }
local camY = {}
local ow = {
  stepBody = function() end,
  drawPeople = function() end,
  maps = {}, neighbors = {}, ghosts = {},
  npcs = { followerNpc }, entities = { followerNpc },
  playerState = "normal",
  tod = "DAY", viewW = 160, viewH = 144,
  player = player, map = map,
  camera = { x = 0, y = 0,
    follow = function(self, x, y) camY[#camY + 1] = y end },
  partyMoveUser = function(self, move)
    if move == "SURF" then return { species = "LAPRAS" } end
  end,
  applyPlayerState = function(self, st) self.playerState = st end,
}
local shown, choices = {}, {}
ow.showText = function(self, text, cb)
  shown[#shown + 1] = text
  if cb then cb() end
end
ow.askYesNo = function(self, cb) choices[#choices + 1] = cb end

local LIVE = { map = true, player = true, npcs = true, entities = true,
               ghosts = true, camera = true }
local facade = setmetatable({}, {
  __index = function(_, k)
    if LIVE[k] then return ow[k] end
    if k == "isOverworld" then return true end
    return nil
  end,
  __newindex = function(t, k, v)
    if LIVE[k] then ow[k] = v else rawset(t, k, v) end
  end,
})

local pressed = {}
local Game = {
  data = Data, overworld = facade, world = ow,
  save = {
    party = {
      { species = "RATTATA", hp = 20, moves = { { id = "TACKLE" } } },
      { species = "LAPRAS", hp = 20, moves = { { id = "SURF" } } },
    },
    player = { badges = {} },
    inventory = {}, flags = {},
  },
  stack = { top = function() return nil end, states = {} },
  input = {
    isDown = function() return false end,
    wasPressed = function(_, b) return pressed[b] == true end,
  },
  mods = { exports = {} },
}
-- no engine stubs: on a Gen 2 load the mod's own requires resolve
-- through the real Gen2Compat facades, so this harness drives those

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/free_fly",
                          { data = Data, generation = 2 })
T.eq(#run.errors, 0, "loads clean on the Gen 2 loader")
-- inject the live game AFTER load: the load-time generation probe
-- must see the arm empty, exactly as a real Gold boot orders it
run.loader.game = Game
run.loader.events:emit("game.ready")
local api = run.loader.exports.free_fly
-- the facade the mod's requires resolved to: its tick and talk seams
-- live there, exactly as on a Gold boot
local OC = require("src.mods.Gen2Compat")
  .resolve("src.world.OverworldController")
T.check(type(OC) == "table" and OC.__freeFlyTick ~= nil,
        "the flight tick rides the real facade")

local landedEvents = {}
run.loader.events:on("mod.free_fly.landed", function(ev)
  landedEvents[#landedEvents + 1] = ev
end)

local flyMon = { species = "NOCTOWL", hp = 20,
                 moves = { { id = "FLY", pp = 15 } } }
local function submenu()
  return Runtime.call("ui.party.submenu",
    function(_, items) return items end,
    Game, {}, flyMon, { overworld = ow })
end

-- the badge gate reads Gold's own store
local out = submenu()
T.eq(#out, 0, "no STORMBADGE, no FREEFLY entry")
Game.save.player.badges.STORM = true
out = submenu()
T.eq(#out, 1, "STORMBADGE serves the FREEFLY entry")
T.eq(out[1].label, "FREEFLY", "and it is the flight entry")

-- takeoff through the entry's own onSelect
out[1].onSelect(flyMon, Game)
T.eq(api.isFlying(), true, "takeoff works on Gold")
for _ = 1, 120 do OC.__freeFlyTick(ow, 1 / 60) end
T.check(api.altitude() > 40, "the mount climbs to cruise")

-- movement immunity rides Gold's World class while airborne
local World2 = require("src.world.gen2.World")
T.check(World2.__freeFlyMoveWrapped, "the World class wraps installed")
T.eq(World2.takeWarp({ player = player }), nil,
     "doors do not swallow a flyer")
T.eq(World2.tryLedgeJump({ player = player }), false,
     "ledges do not hop a flyer")
T.eq(World2.checkCarpetWhileStanding({ player = player }), false,
     "forced movement does not grab a flyer")
T.eq(World2.checkTrainerBattle({ player = player }), nil,
     "trainers do not spot a flyer")

-- the wild-battle gate: wild suppressed, trainers untouched, only
-- while airborne
T.eq(World2.__freeFlyWildGate({ wild = {} }), true,
     "a foreign wild battle is gated mid-air")
T.check(not World2.__freeFlyWildGate({ wild = {}, trainer = {} }),
        "trainer battles pass the gate")

-- the camera tracks the mount
T.check(ow.camera.__freeFlyLift and ow.camera.__freeFlyLift > 40,
        "the camera lift follows the altitude")
camY = {}
ow.camera:follow(0, 100, 160, 144)
T.check(camY[1] and camY[1] < 100, "follow subtracts the lift")

-- a grounded companion sits the flight out
local present = false
for _, npc in ipairs(ow.npcs) do
  if npc == followerNpc then present = true end
end
T.check(not present, "a non-flying companion disappears mid-flight")

-- a FLYING-type lead trails at altitude instead
Game.save.party[1] = { species = "PIDGEOT", hp = 20,
                       moves = { { id = "FLY" } } }
table.insert(ow.npcs, followerNpc)
OC.__freeFlyTick(ow, 1 / 60)
present = false
for _, npc in ipairs(ow.npcs) do
  if npc == followerNpc then present = true end
end
T.check(present, "a FLYING-type companion stays")
T.check((followerNpc.__freeFlyLift or 0) > 40,
        "and trails at the player's altitude")

-- a water landing hands straight into Gold's surf state
Game.save.player.badges.FOG = true
water = true
pressed.b = true
OC.__freeFlyTick(ow, 1 / 60)
pressed.b = false
for _ = 1, 240 do OC.__freeFlyTick(ow, 1 / 60) end
T.eq(api.isFlying(), false, "the landing completes")
T.eq(ow.playerState, "surf", "the landing entered Gold's surf state")
T.check(landedEvents[1] and landedEvents[1].water == true,
        "the landed event says water")
water = false

-- the New Bark gift: the talkTo seam, the yes/no ceremony, the grant
local giftNpc = { def = { name = "FREE_FLY_GIFT" } }
T.eq(OC.talkTo(ow, { def = { name = "SOMEONE_ELSE" } }), false,
     "strangers fall through to the normal dispatch")
shown, choices = {}, {}
T.eq(OC.talkTo(ow, giftNpc), true, "the gift bird answers the A press")
T.check(#choices == 1, "the offer stacks a yes/no choice")
local before = #Game.save.party
choices[1](false)
T.eq(#Game.save.party, before, "declining grants nothing")
shown, choices = {}, {}
OC.talkTo(ow, giftNpc)
choices[1](true)
T.eq(#Game.save.party, before + 1, "accepting grants the bird")
local granted = Game.save.party[#Game.save.party]
T.eq(granted.species, "NOCTOWL", "and it is the NOCTOWL")
T.eq(granted.freeFlyGift, true, "badge-exempt like the Kanto gift")
local knowsFly = false
for _, mv in ipairs(granted.moves or {}) do
  if mv.id == "FLY" then knowsFly = true end
end
T.check(knowsFly, "the gift knows FLY")
shown = {}
OC.talkTo(ow, giftNpc)
T.check(shown[1] and shown[1]:find("hoots", 1, true) ~= nil,
        "a taken gift just hoots")

run.release()
T.finish("free_fly_gold_flight")

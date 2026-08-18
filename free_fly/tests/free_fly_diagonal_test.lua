-- Diagonal flight on a directional mount: with two directions held,
-- the pose faces the true diagonal row and the input the engine sees
-- alternates axes each cell (the zigzag that reads straight at flight
-- speed).  A four-way mount keeps plain cardinal flight untouched.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local OC = { update = function() end, draw = function() end }
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] =
  require("src.world.FieldDefaults")

local held = {}
local ow = {
  entities = {}, isOverworld = true,
  camera = { x = 0, y = 0, follow = function() end },
  player = { cellX = 10, cellY = 10, px = 160, py = 160,
             facing = "up", sprite = { fake = "walk" },
             walkPhase = function() return 0 end,
             tryMove = function() return "blocked" end },
  map = {
    id = "ROUTE_1", def = { tileset = "OVERWORLD" },
    widthCells = 20, heightCells = 18,
    inBounds = function() return true end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
    warpAtCell = function() return nil end,
    cellTile = function() return 0 end,
    cellCollision = function() return 0 end,
  },
}
package.loaded["src.core.Game"] = {
  data = Data,
  save = { flags = {}, party = {}, inventory = { THUNDERBADGE = 1 } },
  overworld = ow,
  input = { isDown = function(_, key) return held[key] == true end,
            wasPressed = function() return false end },
  renderer = { worldViewSize = function() return 160, 144 end },
  stack = { top = function() return ow end },
}
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/free_fly",
  { data = Data })
T.eq(#run.errors, 0, "loads clean")
run.loader.events:emit("game.ready")

local Game = package.loaded["src.core.Game"]
local Player = require("src.world.Player")
local Runtime = require("src.mods.Runtime")
local p = ow.player

-- a real takeoff through the FREEFLY entry, so the flight state is
-- authentic and the tick keeps it alive
package.loaded["src.inventory.Badges"] = { count = function() return 8 end }
local api = run.loader.exports.free_fly
local flyMon = { species = "PIDGEOT", hp = 20,
                 moves = { { id = "FLY", pp = 15 } } }
local out = Runtime.call("ui.party.submenu",
  function(_, items) return items end,
  Game, {}, flyMon, { overworld = ow })
T.check(#out >= 1 and out[1].label == "FREEFLY", "flight entry served")
out[1].onSelect(flyMon, Game)
T.eq(api.isFlying(), true, "airborne")
for _ = 1, 30 do OC.__freeFlyTick(ow, 1 / 60) end

-- swap in a DIRECTIONAL mount
Player.__freeFlyMount = { def = { directions = 8 },
                          __freeFlyAirSheet = true }

held = { up = true, left = true }
OC.__freeFlyTick(ow, 1 / 60)
local _, _, _, facing = Player.pose(p)
T.eq(facing, "upleft", "two held directions face the diagonal row")
T.eq(Game.input:isDown("left"), false,
  "one axis is withheld from the engine for this cell")
T.eq(Game.input:isDown("up"), true, "and the other passes through")
local firstDrop = Game.input:isDown("left")

-- crossing into the next cell flips the exposed axis: the zigzag
p.cellX = p.cellX - 1
OC.__freeFlyTick(ow, 1 / 60)
T.eq(Game.input:isDown("left"), true, "next cell exposes the other axis")
T.eq(Game.input:isDown("up"), false, "and withholds the first")
local _, _, _, facing2 = Player.pose(p)
T.eq(facing2, "upleft", "the pose faces the diagonal the whole way")
T.eq(Runtime.call("movement.speed", function(f) return f end, 8, {}), 6,
  "zigzag steps shorten so a diagonal tile costs straight-line time")

-- releasing a direction restores plain four-way flight
held = { up = true }
OC.__freeFlyTick(ow, 1 / 60)
T.eq(Game.input:isDown("up"), true, "single direction passes through")
local _, _, _, facing3 = Player.pose(p)
T.eq(facing3, "upleft",
  "the look holds through the corner grace, then sweeps back")
for _ = 1, 6 do OC.__freeFlyTick(ow, 1 / 60) end  -- the grace expires
p.__skyFacingT = -1  -- a notch interval elapses
local _, _, _, facing4 = Player.pose(p)
T.eq(facing4, "up", "and lands on the cardinal")
T.eq(Runtime.call("movement.speed", function(f) return f end, 8, {}), 8,
  "cardinal flight keeps its full step speed")

-- a four-way mount never diagonals
Player.__freeFlyMount = { def = {}, __freeFlyAirSheet = true }
held = { up = true, left = true }
OC.__freeFlyTick(ow, 1 / 60)
T.eq(Game.input:isDown("left"), true, "no axis withheld on a 4-way mount")
local _, _, _, facing4 = Player.pose(p)
T.check(facing4 ~= "upleft", "no diagonal facing on a 4-way mount")

run.release()
T.finish("free_fly_diagonal")

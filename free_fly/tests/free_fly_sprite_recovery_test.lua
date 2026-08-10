-- The Charmander bug: a session torn down mid-flight (hot reload, a
-- mod update) can leave the MOUNT sheet on the player with no stashed
-- walking sprite, and the old code would then stash the mount as the
-- "walking sheet" on the next takeoff, restoring the wrong figure on
-- every landing after.  Air sheets are tagged now: the idle tick heals
-- a tagged player sprite by rebuilding the real walking sheet, and a
-- tagged sheet is never stashed.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local OC = {}
OC.update = function() end
OC.draw = function() end
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] =
  require("src.world.FieldDefaults")

local ow = {
  entities = {},
  isOverworld = true,
  camera = { x = 0, y = 0 },
  player = { cellX = 10, cellY = 10, px = 160, py = 160,
             facing = "down" },
  map = {
    id = "ROUTE_1",
    def = { tileset = "OVERWORLD" },
    widthCells = 20, heightCells = 18,
    inBounds = function() return true end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
  },
}
package.loaded["src.core.Game"] = {
  data = Data,
  save = { flags = {}, party = {} },
  overworld = ow,
  renderer = { worldViewSize = function() return 160, 144 end },
  stack = { top = function() return ow end },
}
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/free_fly",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")
run.loader.events:emit("game.ready")

local p = ow.player

-- a normal walking sprite is left completely alone
local normal = { fake = "walk" }
p.sprite = normal
OC.__freeFlyTick(ow, 1 / 60)
T.eq(p.sprite, normal, "a normal walking sprite is untouched")

-- the poisoned state: a stale AIR sheet on the player, no stash
-- (exactly what a mid-flight reload leaves behind)
local stale = { __freeFlyAirSheet = true }
p.sprite = stale
p.freeFlyWalkSprite = nil
p.freeFlying = nil
OC.__freeFlyTick(ow, 1 / 60)
T.check(p.sprite ~= stale, "the stale air sheet is healed off the player")
T.check(p.sprite ~= nil and not p.sprite.__freeFlyAirSheet,
  "with a real walking sheet, not another mount")

-- the mod's own mount renderers carry the tag, so a lost session can
-- always be recognized
T.check(require("src.world.Player").__freeFlyBird == nil
    or require("src.world.Player").__freeFlyBird.__freeFlyAirSheet == true,
  "the default bird mount is tagged as an air sheet")

run.release()
T.finish("free_fly_sprite_recovery")

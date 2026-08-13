-- The Charmander-generic bug: a session torn down mid-flight (hot
-- reload, a mod update) can leave the MOUNT sheet on the player with no
-- stashed walking sprite, and the unguarded code then stashed the mount
-- as the "walking sheet" on the next takeoff, restoring the wrong
-- figure on every landing after.  Air sheets are recognized by tag or
-- by seed now: the idle tick heals a recognized player sprite by
-- rebuilding the real walking sheet, a recognized sheet is never
-- stashed, and a poisoned stash is discarded rather than restored.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local OC = {}
OC.update = function() end
OC.draw = function() end
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }

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

-- a poisoned stash (no tag, but seeded like our renderers) must not
-- be restored; the real sheet is rebuilt instead
local legacyPoison = { seed = "free_fly_SPRITE_MONSTER" }
p.sprite = { seed = "free_fly_mount" }
p.freeFlyWalkSprite = legacyPoison
OC.__freeFlyTick(ow, 1 / 60)
T.check(p.sprite ~= legacyPoison and p.freeFlyWalkSprite ~= legacyPoison,
  "a poisoned stash is discarded, not restored")
T.check(p.sprite and p.sprite.seed == "player",
  "the rebuilt sheet is the engine's own player sprite")

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

-- a wild_skies-seeded sheet is recognized the same way
p.sprite = { seed = "wild_skies_pic_PIDGEOT" }
p.freeFlyWalkSprite = nil
OC.__freeFlyTick(ow, 1 / 60)
T.check(p.sprite and p.sprite.seed == "player",
  "a wild_skies-seeded sheet is healed off the player too")

-- the mod's own mount renderers carry the tag, so a lost session can
-- always be recognized
local Player = require("src.world.Player")
T.check(Player.__freeFlyBird == nil
    or Player.__freeFlyBird.__freeFlyAirSheet == true,
  "the default bird mount is tagged as an air sheet")

run.release()
T.finish("free_fly_sprite_recovery")

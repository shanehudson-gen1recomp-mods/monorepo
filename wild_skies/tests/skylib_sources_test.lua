-- skylib's borrowed-sprite sources against stubbed engine modules:
-- resolution, the levitates kind check, caching, fallbacks, external
-- source registration and the options-changed matcher.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local MOD_DIR = os.getenv("MOD_DIR") or "mods/wild_skies"

package.loaded["src.render.SpriteRenderer"] = {
  new = function(def, seed) return { def = def, seed = seed } end,
}

local levDef
local fakeGame = { mods = { exports = { overworld_wild_spawns = {
  render = { waterSpriteRegistry = {
    isReady = function() return true end,
    resolve = function(_, dex, variant, preferred)
      T.eq(dex, 17, "dex passed through")
      T.eq(variant, "normal", "normal variant requested")
      T.eq(preferred, "levitates", "levitates preferred")
      return levDef
    end,
  } },
} } } }
package.loaded["src.core.Game"] = fakeGame

local Sky = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()

local data = {
  icons = {},
  pokemon = { PIDGEOTTO = { icon = "BIRD", dex = 17 } },
  sprites = { SPRITE_BIRD = { image = "generic_bird.png", frames = 6 } },
}

-- an animated levitates def is borrowed, and cached on the second call;
-- True Size sheets carry their own frame box and anchor, which must
-- ride through or the renderer crops to the top-left 16x16 tile
levDef = { image = "lev/017.png", frames = 6, kind = "levitates",
           frameWidth = 24, frameHeight = 32, anchorX = 12, anchorY = 30 }
local r, class = Sky.mountSprite(data, "PIDGEOTTO", "t")
T.eq(r.def.image, "lev/017.png", "levitates def borrowed")
T.eq(class, "BIRD", "icon class still resolved")
T.eq(r.def.frameWidth, 24, "True Size frame width carries through")
T.eq(r.def.frameHeight, 32, "True Size frame height carries through")
T.eq(r.def.anchorY, 30, "True Size anchor carries through")
T.check(Sky.mountSprite(data, "PIDGEOTTO", "t") == r, "renderer cached")

-- swimming fallthrough and missing art both land on the generic sheet
levDef = { image = "swim/017.png", frames = 6, kind = "swimming" }
T.eq(Sky.mountSprite(data, "PIDGEOTTO", "t2").def.image, "generic_bird.png",
  "swimming kind rejected")
levDef = nil
T.eq(Sky.mountSprite(data, "PIDGEOTTO", "t3").def.image, "generic_bird.png",
  "no in-air art falls back")

-- a broken source never breaks the caller
fakeGame.mods.exports.overworld_wild_spawns.render.waterSpriteRegistry
  .resolve = function() error("boom") end
T.eq(Sky.mountSprite(data, "PIDGEOTTO", "t4").def.image, "generic_bird.png",
  "source error falls back")

-- a disabled source mod (no exports) is skipped
fakeGame.mods.exports = {}
T.eq(Sky.mountSprite(data, "PIDGEOTTO", "t5").def.image, "generic_bird.png",
  "disabled source skipped")

-- external registration: validation, precedence over built-ins,
-- direct (mod-less) sources, replacement and unregistration
T.eq(Sky.registerSpriteSource("nope"), false, "non-table rejected")
T.eq(Sky.registerSpriteSource({ id = "x" }), false, "missing resolve rejected")
T.eq(Sky.registerSpriteSource({ resolve = function() end }), false,
  "missing id and mod rejected")

local packDef = { image = "pack/017.png", frames = 6 }
T.eq(Sky.registerSpriteSource({
  id = "test_pack",
  resolve = function(exports, game, species, dex)
    T.eq(exports, nil, "direct source gets nil exports")
    T.eq(species, "PIDGEOTTO", "species passed to source")
    T.eq(dex, 17, "dex passed to source")
    return packDef
  end,
}), true, "valid direct source registers")
T.eq(Sky.mountSprite(data, "PIDGEOTTO", "t6").def.image, "pack/017.png",
  "registered source outranks built-ins")

-- re-registering the same id replaces, not duplicates
T.eq(Sky.registerSpriteSource({
  id = "test_pack",
  resolve = function() return { image = "pack2/017.png", frames = 6 } end,
}), true, "re-register accepted")
T.eq(Sky.mountSprite(data, "PIDGEOTTO", "t7").def.image, "pack2/017.png",
  "re-registered source replaces")

-- a static def from a source is refused (flyers need animation)
T.eq(Sky.registerSpriteSource({
  id = "test_pack",
  resolve = function() return { image = "pack3/017.png", frames = 1 } end,
}), true, "static-art source registers")
T.eq(Sky.mountSprite(data, "PIDGEOTTO", "t8").def.image, "generic_bird.png",
  "static def falls through to generic")

T.eq(Sky.unregisterSpriteSource("test_pack"), true, "unregister by id")
T.eq(Sky.unregisterSpriteSource("test_pack"), false, "second unregister no-op")

-- spriteSourceChanged matches built-ins by mod and registered by id
T.check(Sky.spriteSourceChanged({ mod = "overworld_wild_spawns" }),
  "built-in source matched")
T.check(not Sky.spriteSourceChanged({ mod = "someone_else" }),
  "foreign mod ignored")
T.check(not Sky.spriteSourceChanged(nil), "nil payload ignored")
Sky.registerSpriteSource({ id = "opt_pack", resolve = function() end })
T.check(Sky.spriteSourceChanged({ mod = "opt_pack" }),
  "registered source matched by id")
Sky.unregisterSpriteSource("opt_pack")

-- the family's small shared helpers
T.eq(Sky.monName(data, { nickname = "BUDDY", species = "PIDGEOTTO" }),
  "BUDDY", "nickname wins")
T.eq(Sky.monName(data, { species = "MISSINGNO" }), "MISSINGNO",
  "unknown species falls back to the id")
local slotData = { encounters = { R1 = { grass = { slots = {
  { species = "PIDGEY", level = 3 } } } } } }
T.eq(#Sky.grassSlots(slotData, "R1"), 1, "grass slots read through")
T.eq(#Sky.grassSlots(slotData, "R2"), 0, "missing map gives empty list")

T.finish("skylib_sources")

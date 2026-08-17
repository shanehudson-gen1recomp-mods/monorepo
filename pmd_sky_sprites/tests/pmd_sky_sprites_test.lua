-- PMD Sky Sprites through a real loader: the baked data parses, defs
-- come out 8-directional and animated (the shared resolver's contract:
-- frames > 1 or the source falls through), the dex keying is declared
-- for the canonical-dex guard, and registration lands on the sky mods
-- loaded before it.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local dir = os.getenv("MOD_DIR") or "mods/pmd_sky_sprites"
local skyDir = dir:gsub("pmd_sky_sprites", "wild_skies")

local run = T.sdk.loadMods({ skyDir, dir }, { data = Data })
T.eq(#run.errors, 0, "loads clean beside wild_skies")

local api = run.loader.exports.pmd_sky_sprites
T.check(api ~= nil, "exports registered")

-- the def shape the shared resolver consumes (Mewtwo's Hover is one
-- of the community-drawn sheets that survive the official-art filter)
local def = api.sheetFor("MEWTWO", 150)
T.check(def ~= nil, "Mewtwo has a sheet")
T.eq(api.sheetFor("BULBASAUR", 1), nil,
  "a species with no air animation answers nil (Walk is never shipped)")
T.eq(def.directions, 8, "eight direction rows")
T.check((def.frames or 0) > 1, "animated (the resolver's contract)")
T.check(type(def.durations) == "table" and #def.durations == def.frames,
  "durations per frame")
T.check(def.frameWidth > 0 and def.frameHeight > 0, "real frame geometry")
T.check(def.image:find("^mods/pmd_sky_sprites/sprites/") ~= nil,
  "image path inside this mod")
T.eq(def.trueColor, true, "full-colour art bypasses the palette bakes")
T.eq(api.sheetFor("MISSINGNO", 9999), nil, "unknown dex answers nil")
T.eq(api.source.dexKeyed, true, "dex keying declared for the guard")

-- registration reached wild_skies: its resolver now knows the source
-- (unregister answers true only for a registered id)
local ws = run.loader.exports.wild_skies
T.eq(ws.unregisterSpriteSource("pmd_sky_sprites"), true,
  "the source was registered with wild_skies")
T.eq(ws.registerSpriteSource(api.source), true, "and re-registers")

run.release()
T.finish("pmd_sky_sprites")

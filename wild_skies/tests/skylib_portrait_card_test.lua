-- Portrait flyers under a voxel overworld mod: the Dramatic Shape
-- family builds each figure's card as a hard-coded 16x16 window of
-- def.image textured with the renderer's own image, so a portrait def
-- must point at a 16x16 image every Assets.image consumer can load.
-- The bake never touches the filesystem (the mod sandbox reroutes
-- love.filesystem where no engine-side reader could see the file):
-- the card lives in memory and a shared wrap on the engine's
-- Assets.image serves it under a virtual path.  Without a usable
-- Assets module the old raw-pic def carries on unchanged.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local MOD_DIR = os.getenv("MOD_DIR") or "mods/wild_skies"

package.loaded["src.render.SpriteRenderer"] = {
  new = function(def, seed)
    return { def = def, seed = seed, frameCount = def.frames or 1,
             frameWidth = def.frameWidth, frameHeight = def.frameHeight,
             frames = { [0] = "q0" } }
  end,
}

-- a 32x32 front pic: white background, one grey body box
local SIZE = 32
local function freshPic()
  local g = {}
  for y = 0, SIZE - 1 do
    g[y] = {}
    for x = 0, SIZE - 1 do
      local body = x >= 8 and x <= 23 and y >= 8 and y <= 23
      g[y][x] = body and { 0.6, 0.6, 0.6, 1 } or { 1, 1, 1, 1 }
    end
  end
  return g
end

local function gridData(g, w, h)
  return {
    getWidth = function() return w end,
    getHeight = function() return h end,
    getPixel = function(_, x, y)
      local p = g[y][x]
      return p[1], p[2], p[3], p[4]
    end,
    setPixel = function(_, x, y, r, gr, b, a)
      g[y][x] = { r, gr, b, a }
    end,
    mapPixel = function(_, fn)
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local p = g[y][x]
          p[1], p[2], p[3], p[4] = fn(x, y, p[1], p[2], p[3], p[4])
        end
      end
    end,
  }
end

local smallGrid
local function fakeLove()
  return {
    image = { newImageData = function(a, b)
      if type(a) == "string" then
        return gridData(freshPic(), SIZE, SIZE)
      end
      smallGrid = {}
      for y = 0, b - 1 do
        smallGrid[y] = {}
        for x = 0, a - 1 do smallGrid[y][x] = { 0, 0, 0, 0 } end
      end
      return gridData(smallGrid, a, b)
    end },
    graphics = {
      newImage = function(idata) return { idata = idata } end,
      newQuad = function(x, y, w, h, iw, ih)
        return { x = x, y = y, w = w, h = h, iw = iw, ih = ih }
      end,
    },
  }
end

local function freshData()
  return {
    encounters = { ROUTE_1 = { grass = { rate = 25, slots = {
      { species = "SCYTHER", level = 20 } } } } },
    icons = {},
    pokemon = { SCYTHER = { icon = "MON",
                            spriteFront = "battle/front/scyther.png",
                            picSize = 4 } },
    sprites = {},
  }
end

-- bake available: an Assets module to wrap.  The def points at the
-- virtual card path, the wrap serves the in-memory 16x16 card there,
-- and every other path passes through to the stock resolver.
local savedLove = rawget(_G, "love")
_G.love = fakeLove()
local Assets = { image = function(path) return { stock = path } end }
package.loaded["src.render.Assets"] = Assets
local Sky = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()
local r = Sky.mountSprite(freshData(), "SCYTHER", "card")
local cardPath = "sky_family/card/SCYTHER.png"
T.check(r ~= nil, "portrait resolved with bake available")
T.eq(r.def.image, cardPath, "def.image is the virtual card path")
T.eq(r.def.frameWidth, 16, "card window width is the whole image")
T.eq(r.def.frameHeight, 16, "card window height is the whole image")
T.check(Assets.image(cardPath) == r.image,
        "Assets.image serves the baked card at the virtual path")
T.eq(Assets.image("battle/front/scyther.png").stock,
     "battle/front/scyther.png",
     "other paths pass through to the stock resolver")
T.eq(r.image.idata:getWidth(), 16, "renderer texture is the 16x16 bake")
T.eq(r.image.idata:getHeight(), 16,
     "a frame-0 16x16 window covers the texture exactly")
T.check(r.draw ~= nil, "the 2D overworld draw survives the bake")
T.check(not Sky.trueSized(r), "a baked card is not a True Size sheet")

-- baked pixels: background flooded away, the body opaque in its shade
T.eq(smallGrid[0][0][4], 0, "baked background is transparent")
T.eq(smallGrid[8][8][4], 1, "baked body is opaque")
T.check(math.abs(smallGrid[8][8][1] - 0.6) < 0.01,
        "baked body keeps the processed shade")

-- a second sky-family mod's own library copy reuses the one wrap and
-- registry instead of stacking another
local registry = Assets.__skyFamilyCards
local Sky2 = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()
local r2 = Sky2.mountSprite(freshData(), "SCYTHER", "card2")
T.check(r2 ~= nil and Assets.__skyFamilyCards == registry,
        "library copies share one card registry")
T.check(Assets.image(cardPath) ~= nil,
        "and the shared wrap still serves cards")

-- bake unavailable (no usable Assets module): old behavior, the def
-- keeps the raw pic path and its full-size crop box
package.loaded["src.render.Assets"] = true
local Sky3 = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()
local f = Sky3.mountSprite(freshData(), "SCYTHER", "raw")
T.check(f ~= nil, "portrait still resolves without Assets")
T.eq(f.def.image, "battle/front/scyther.png",
     "no bake keeps the raw pic path")
T.eq(f.def.frameWidth, SIZE, "no bake keeps the full-size crop box")
T.check(f.draw ~= nil, "the 2D draw is unchanged without a bake")

_G.love = savedLove
package.loaded["src.render.SpriteRenderer"] = nil
package.loaded["src.render.Assets"] = nil

T.finish("skylib_portrait_card")

-- Portrait flyers under a voxel overworld mod: the Dramatic Shape
-- family builds each figure's card as a hard-coded 16x16 window of
-- def.image textured with the renderer's own image, so a portrait def
-- must point at a real 16x16 file when the bake is possible, and keep
-- the old raw-pic def when it is not (headless, read-only fs).
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
    encode = function(self) return { png = self } end,
  }
end

local written, dirs, smallGrid = {}, {}, nil
local function fakeLove(withFs)
  local l = {
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
  if withFs then
    l.filesystem = {
      createDirectory = function(d) dirs[d] = true; return true end,
      write = function(path, data)
        written[path] = data
        return true
      end,
    }
  end
  return l
end

local data = {
  encounters = { ROUTE_1 = { grass = { rate = 25, slots = {
    { species = "SCYTHER", level = 20 } } } } },
  icons = {},
  pokemon = { SCYTHER = { icon = "MON",
                          spriteFront = "battle/front/scyther.png",
                          picSize = 4 } },
  sprites = {},
}

-- bake available: the def points at the baked 16x16 file, so a voxel
-- card's 16x16 window IS the whole image and its bound texture (the
-- renderer's image, via trueColor) matches it
local savedLove = rawget(_G, "love")
_G.love = fakeLove(true)
local Sky = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()
local r = Sky.mountSprite(data, "SCYTHER", "card")
local bakedPath = "save/mod-derived/sky_family/pics/SCYTHER.png"
T.check(r ~= nil, "portrait resolved with bake available")
T.eq(r.def.image, bakedPath, "def.image is the baked file")
T.eq(r.def.frameWidth, 16, "card window width is the whole image")
T.eq(r.def.frameHeight, 16, "card window height is the whole image")
T.check(written[bakedPath] ~= nil, "the baked png was written")
T.check(dirs["save/mod-derived/sky_family/pics"],
        "derived directory created")
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

-- bake unavailable (no writable filesystem): old behavior, the def
-- keeps the raw pic path and its full-size crop box
written, dirs, smallGrid = {}, {}, nil
_G.love = fakeLove(false)
local Sky2 = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()
local f = Sky2.mountSprite(data, "SCYTHER", "raw")
T.check(f ~= nil, "portrait still resolves without a filesystem")
T.eq(f.def.image, "battle/front/scyther.png",
     "no bake keeps the raw pic path")
T.eq(f.def.frameWidth, SIZE, "no bake keeps the full-size crop box")
T.check(next(written) == nil, "nothing written without a filesystem")
T.check(f.draw ~= nil, "the 2D draw is unchanged without a bake")

_G.love = savedLove
package.loaded["src.render.SpriteRenderer"] = nil

T.finish("skylib_portrait_card")

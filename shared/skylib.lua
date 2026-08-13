-- Shared helpers for the gen1recomp-mods family.  Synced into each mod as
-- lib/shared/skylib.lua (scripts/dev.sh, scripts/pack.sh, release CI) and
-- loaded through mod:read, so the same file works from a checkout, the
-- game's save directory and a packed zip alike.
local Sky = {}

-- the species' party-icon class, via the same resolution the party menu
-- uses: bySpecies override, the pokemon record's own icon, dex default
function Sky.iconClass(data, species)
  local icons = data.icons or {}
  local def = data.pokemon and data.pokemon[species]
  local entry = (icons.bySpecies and icons.bySpecies[species])
             or (def and def.icon)
             or (def and def.dex and icons.byDex and icons.byDex[def.dex])
  return type(entry) == "string" and entry or nil
end

-- icon classes with a real walker sheet in the imported cache
Sky.MOUNT_SPRITES = {
  BIRD = "SPRITE_BIRD", MON = "SPRITE_MONSTER",
  WATER = "SPRITE_SEEL", FAIRY = "SPRITE_FAIRY", PIKACHU = "SPRITE_FAIRY",
}

-- ------- borrowed art from other sprite mods
-- Ordered adapters over other mods' exports (game.mods.exports only lists
-- mods that are enabled and loaded clean), so our creatures wear that
-- mod's per-species art.  Everything here flies, so adapters resolve
-- in-air sheets only: a ground walk cycle toggled in the sky reads as
-- walking on air, worse than the generic mount sheets, which are at
-- least drawn mid-flight.  Species without in-air art keep those.

-- the levitates sheets pose their subject over a waterline, splash
-- included; the splash is this one flat color on every gen 1 sheet
-- (verified across the full set), keyed to alpha so the sky stays dry
local WATER_SPLASH = { 232 / 255, 232 / 255, 248 / 255 }

local function splashFreeImage(path)
  if not (love and love.image and love.image.newImageData
          and love.graphics) then
    return nil
  end
  -- a fresh decode, never the engine's cached ImageData: the source mod
  -- still draws these sheets on real water, splash and all
  local ok, id = pcall(love.image.newImageData, path)
  if not ok or not id then return nil end
  local w = WATER_SPLASH
  id:mapPixel(function(_, _, r, g, b, a)
    if math.abs(r - w[1]) < 0.004 and math.abs(g - w[2]) < 0.004
       and math.abs(b - w[3]) < 0.004 then
      return r, g, b, 0
    end
    return r, g, b, a
  end)
  local okI, img = pcall(love.graphics.newImage, id)
  return okI and img or nil
end

Sky.SPRITE_SOURCES = {
  { -- Wilds of Kanto's "levitates" water sheets: hovering poses in the
    -- engine's own 6-frame walker format, style-independent.  The
    -- registry falls through to swimming art, hence the kind check.
    mod = "overworld_wild_spawns",
    stripWater = true,
    dexKeyed = true,
    resolve = function(exports, game, species, dex)
      if not dex then return nil end
      local reg = exports.render and exports.render.waterSpriteRegistry
      if not (reg and reg.isReady and reg:isReady()) then return nil end
      local waterDef = reg:resolve(dex, "normal", "levitates")
      if type(waterDef) ~= "table" or waterDef.kind ~= "levitates"
         or type(waterDef.image) ~= "string" then
        return nil
      end
      -- carry the sheet geometry through: True Size sheets (WoK 2.x)
      -- are taller than 16x16 and declare their own frame box and
      -- anchor; a rebuilt def without them crops to the top-left tile
      return { image = waterDef.image, frames = waterDef.frames or 6,
               frameWidth = waterDef.frameWidth,
               frameHeight = waterDef.frameHeight,
               anchorX = waterDef.anchorX, anchorY = waterDef.anchorY,
               walker = true, trueColor = true, id = waterDef.id }
    end,
  },
  { -- Wilds of Kanto's land sheets: the same per-species HGSS art its
    -- own wilds wear and Dramatic Sky Ride's mounts fly on.  Standing
    -- poses, so the levitates in-air art above outranks this; every
    -- creature the sky asks about is airborne anyway, so no further
    -- gate is needed.
    mod = "overworld_wild_spawns",
    id = "overworld_wild_spawns_land",
    dexKeyed = true,
    resolve = function(exports, game, species, dex)
      return Sky.bindPipelineDef(exports and exports.render, game,
        species, dex)
    end,
  },
  { -- the same Wilds pipeline EMBEDDED in Stadium 2's Gold mod: on a
    -- Gold boot its HGSS sheets are the only per-species walker art
    -- around, and its 16x16 cards are exactly what that mod's voxel
    -- billboards expect (front-pic portraits texture wrong there)
    mod = "STADIUM2_OVERWORLD_MODELS",
    id = "stadium2_wilds_land",
    dexKeyed = true,
    resolve = function(exports, game, species, dex)
      local wilds = exports and exports.wilds
      return Sky.bindPipelineDef(wilds and wilds.render, game,
        species, dex)
    end,
  },
  { -- any OTHER mod embedding the Wilds pipeline under the same
    -- export shape (exports.wilds.render): capability probed, so a
    -- fork under a new id serves art the day it ships.  Its option
    -- flips will not live-re-dress (no id to match), which a respawn
    -- catches.
    id = "embedded_wilds_scan",
    dexKeyed = true,
    resolve = function(_, game, species, dex)
      local exportsById = game and game.mods and game.mods.exports
      for _, ex in pairs(exportsById or {}) do
        local wilds = type(ex) == "table" and ex.wilds or nil
        local def = Sky.bindPipelineDef(wilds and wilds.render, game,
          species, dex)
        if def then return def end
      end
      return nil
    end,
  },
}

-- drive a Wilds-family bind pipeline (Wilds of Kanto itself, or the
-- copy embedded in Stadium 2's Gold mod) with a throwaway entity and
-- lift the finished def: style routing, palette mode and True Size
-- stay the provider's own decisions, and geometry, trueColor and
-- frames all ride through as theirs
function Sky.bindPipelineDef(render, game, species, dex)
  if not (render and render.applyProviderSprite) then return nil end
  local entity = { species = species, enhancedDexId = dex,
                   id = "sky_borrow_" .. tostring(species),
                   spawnId = "sky_borrow_" .. tostring(species) }
  local ok, applied = pcall(render.applyProviderSprite, render,
                            entity, game)
  if not (ok and applied and entity.sprite
          and type(entity.sprite.def) == "table") then
    return nil
  end
  -- fail closed on anything that is not clearly OUR species' art: a
  -- provider that fell back to placeholder art says so on the entity,
  -- and a real per-species sheet names its species or padded dex in
  -- the path.  Older provider builds can answer a failed resolution
  -- with another species' sheet; a wrong-species mount is worse than
  -- the generic one.
  if entity.spriteFallbackStep ~= nil then return nil end
  local meta = entity.spriteProviderMeta
  if type(meta) == "table" and meta.fallbackUsed == true then
    return nil
  end
  local def = entity.sprite.def
  if type(def.image) ~= "string" then return nil end
  local path = def.image:lower()
  if path:find("fallback", 1, true) or path:find("missing", 1, true) then
    return nil
  end
  local named = path:find(tostring(species):lower():gsub("_", ""), 1,
    true) ~= nil
  local byDex = dex ~= nil
    and path:find(string.format("%03d", dex), 1, true) ~= nil
  local byId = type(def.id) == "string"
    and def.id:lower():find(tostring(species):lower(), 1, true) ~= nil
  if not (named or byDex or byId) then return nil end
  return def
end

-- other mods can offer their own in-air art: a source carries a mod id
-- (its exports are passed to resolve; skipped while that mod is off) or
-- stands alone (resolve gets nil exports).  Registered sources outrank
-- the built-ins; re-registering an id replaces it.  Note each of our
-- mods bundles its own skylib copy, so a pack registers with every mod
-- it wants to dress.
function Sky.registerSpriteSource(source)
  if type(source) ~= "table" or type(source.resolve) ~= "function" then
    return false, "source table with a resolve function required"
  end
  local id = source.id or source.mod
  if id == nil then return false, "source needs an id or a mod" end
  Sky.unregisterSpriteSource(id)
  table.insert(Sky.SPRITE_SOURCES, 1, source)
  return true
end

function Sky.unregisterSpriteSource(id)
  for i = #Sky.SPRITE_SOURCES, 1, -1 do
    local s = Sky.SPRITE_SOURCES[i]
    if (s.id or s.mod) == id then
      table.remove(Sky.SPRITE_SOURCES, i)
      return true
    end
  end
  return false
end

local function animated(def) return def and (def.frames or 1) > 1 end

-- Wilds of Kanto keys its sprite packs by NATIONAL dex position
-- (their issue #55), so a dataset that reorders the dex would dress
-- our creatures in the wrong species' art (their example: Mewtwo at a
-- reordered #248 wearing Tyranitar's sheet).  A few sentinel species
-- whose canon numbers never move tell us whether this dataset's dex
-- space is still national; dex-keyed borrowing is skipped when it
-- is not, and the identity-correct fallbacks (class sheets, Gold's
-- per-species pics) dress the sky instead.
local CANON_DEX = { PIKACHU = 25, MEWTWO = 150, CHIKORITA = 152,
                    HOOTHOOT = 163, HO_OH = 250 }
local canonCache = setmetatable({}, { __mode = "k" })

function Sky.canonicalDex(data)
  if not (data and data.pokemon) then return false end
  local hit = canonCache[data]
  if hit ~= nil then return hit end
  local ok = true
  for species, dex in pairs(CANON_DEX) do
    local def = data.pokemon[species]
    if def and def.dex ~= nil and def.dex ~= dex then
      ok = false
      break
    end
  end
  canonCache[data] = ok
  return ok
end

local sourceCache = {}

local function borrowedSprite(data, species, dex, seedPrefix)
  local okG, Game = pcall(require, "src.core.Game")
  Game = okG and Game or nil
  local exportsById = Game and Game.mods and Game.mods.exports or nil
  local canon
  for _, source in ipairs(Sky.SPRITE_SOURCES) do
    local exports = source.mod and exportsById and exportsById[source.mod]
      or nil
    if source.dexKeyed then
      if canon == nil then canon = Sky.canonicalDex(data) end
      if not canon then exports = nil end
    end
    if exports ~= nil or source.mod == nil then
      local ok, def = pcall(source.resolve, exports, Game, species, dex)
      if ok and animated(def) then
        local key = (seedPrefix or "shared") .. "#" .. def.image
        if sourceCache[key] == nil then
          local SpriteRenderer = require("src.render.SpriteRenderer")
          local okR, renderer = pcall(SpriteRenderer.new, def,
            (seedPrefix or "shared") .. "_borrowed")
          if okR and renderer and source.stripWater then
            local dry = splashFreeImage(def.image)
            if dry then renderer.image = dry end
          end
          if okR and renderer then
            renderer.skySource = tostring(source.mod or source.id)
          end
          sourceCache[key] = okR and renderer or false
        end
        if sourceCache[key] then return sourceCache[key] end
      end
    end
  end
end

-- true when a mod.options_changed payload belongs to a sprite source;
-- callers re-resolve their live sprites so a style change shows at once
function Sky.spriteSourceChanged(payload)
  local id = payload and payload.mod
  if id == nil then return false end
  for _, source in ipairs(Sky.SPRITE_SOURCES) do
    if source.mod == id or source.id == id then return true end
  end
  return false
end

-- where a piece of art came from, for the Sky Dex's provenance line: a
-- path under a mod's derived-file home or a mods folder names the mod,
-- anything else is the game's own imported data
function Sky.artSource(path)
  if type(path) ~= "string" then return "game" end
  return path:match("mod%-derived/([^/]+)")
    or path:match("^mods/([^/]+)")
    or "game"
end

local mountCache = {}

-- Gold ships no overworld art for most species (its icon table maps
-- nearly every flyer to ICON_BIRD), but it ships every species' battle
-- front pic.  This builds an overworld-sized renderer from that pic:
-- the white BACKGROUND becomes transparent by border flood (the cart
-- uses white inside bodies too, so a plain colour key would punch
-- holes in bellies), and the shades remap to the species' shipped
-- colour pair.  Returns nil headless or when anything is missing, so
-- the caller's ladder just falls through.
local picCache = {}

-- Voxel overworld mods (the Dramatic Shape family) draw each figure as
-- one flat card UV-mapped to a hard-coded 16x16 window of def.image and
-- textured with the renderer's resolved image, so a portrait def
-- pointing at the raw front-pic file shows a corner crop of mostly
-- background there.  Bake the processed pic down to a real 16x16 file
-- (box filter, alpha thresholded so the silhouette stays crisp) in the
-- engine's derived-art root, so the card's window IS the whole image.
-- Returns the baked love image and its path, or nil wherever the
-- filesystem or pixel APIs are missing, which keeps the raw-pic def.
local CARD = 16

local function bakeCardPic(id, size, w, h, species)
  local fs = love and love.filesystem
  if not (fs and fs.write and fs.createDirectory) then return nil end
  local okS, small = pcall(love.image.newImageData, CARD, CARD)
  if not (okS and small and small.setPixel and small.encode) then
    return nil
  end
  local step = size / CARD
  local okP = pcall(function()
    for ty = 0, CARD - 1 do
      for tx = 0, CARD - 1 do
        local x0, y0 = math.floor(tx * step), math.floor(ty * step)
        local x1 = math.max(x0, math.ceil((tx + 1) * step) - 1)
        local y1 = math.max(y0, math.ceil((ty + 1) * step) - 1)
        local rs, gs, bs, as, n = 0, 0, 0, 0, 0
        for y = y0, math.min(y1, h - 1) do
          for x = x0, math.min(x1, w - 1) do
            local r, g, b, a = id:getPixel(x, y)
            rs, gs, bs = rs + r * a, gs + g * a, bs + b * a
            as, n = as + a, n + 1
          end
        end
        if n > 0 and as / n >= 0.35 then
          small:setPixel(tx, ty, rs / as, gs / as, bs / as, 1)
        else
          small:setPixel(tx, ty, 0, 0, 0, 0)
        end
      end
    end
  end)
  if not okP then return nil end
  local dir = "save/mod-derived/sky_family/pics"
  local rel = dir .. "/" .. tostring(species):gsub("[^%w_]", "_")
    .. ".png"
  local okW = pcall(function()
    fs.createDirectory(dir)
    assert(fs.write(rel, small:encode("png")))
  end)
  if not okW then return nil end
  local okI, img = pcall(love.graphics.newImage, small)
  if not okI then return nil end
  return img, rel
end

local function goldPicRenderer(data, species, seedPrefix)
  local mon = data.pokemon and data.pokemon[species]
  local path = mon and mon.spriteFront
  if type(path) ~= "string" then return nil end
  local key = (seedPrefix or "shared") .. "#pic#" .. tostring(species)
  if picCache[key] ~= nil then return picCache[key] or nil end
  picCache[key] = false
  if not (love and love.image and love.image.newImageData
          and love.graphics) then
    return nil
  end
  local okD, id = pcall(love.image.newImageData, path)
  if not (okD and id) then return nil end
  local w, h = id:getWidth(), id:getHeight()
  if w < 8 or h < 8 then return nil end
  local outside, queue = {}, {}
  local function push(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return end
    local k = y * w + x
    if outside[k] then return end
    local r, g, b = id:getPixel(x, y)
    if r > 0.83 and g > 0.83 and b > 0.83 then
      outside[k] = true
      queue[#queue + 1] = x
      queue[#queue + 1] = y
    end
  end
  for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
  for y = 0, h - 1 do push(0, y); push(w - 1, y) end
  local qi = 1
  while queue[qi] do
    local x, y = queue[qi], queue[qi + 1]
    qi = qi + 2
    push(x + 1, y); push(x - 1, y); push(x, y + 1); push(x, y - 1)
  end
  local colors
  pcall(function()
    local Palettes = require("src.world.gen2.Palettes")
    colors = Palettes.monColors(data.gen2Palettes, species)
  end)
  id:mapPixel(function(x, y, r, g, b, a)
    if outside[y * w + x] then return r, g, b, 0 end
    if colors then
      local col = (r > 0.83 and colors[1]) or (r > 0.5 and colors[2])
        or (r > 0.17 and colors[3]) or colors[4]
      return col[1] / 255, col[2] / 255, col[3] / 255, a
    end
    return r, g, b, a
  end)
  local okI, img = pcall(love.graphics.newImage, id)
  if not okI then return nil end
  local size = (mon.picSize or 0) * 8
  if size < 8 then size = h end
  local card, cardPath = bakeCardPic(id, size, w, h, species)
  local def = { id = "SKY_PIC_" .. tostring(species), image = path,
                frames = 1, walker = false, trueColor = true,
                frameWidth = size, frameHeight = size,
                spriteType = "POKEMON_PIC", species = species }
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local seed = (seedPrefix or "shared") .. "_pic_" .. tostring(species)
  local renderer
  if card then
    def.image, def.frameWidth, def.frameHeight = cardPath, CARD, CARD
    local okR, r = pcall(SpriteRenderer.new, def, seed)
    -- the def's trueColor makes the baked card the texture a voxel
    -- pipeline binds, so it must match the def's 16x16 window
    if okR and r then renderer = r; renderer.image = card end
  end
  if not renderer then
    def.image, def.frameWidth, def.frameHeight = path, size, size
    card = nil
    local okR, r = pcall(SpriteRenderer.new, def, seed)
    if not (okR and r) then return nil end
    renderer = r
    renderer.image = img
  end
  -- provenance reads off the ORIGINAL pic path: the baked card under
  -- sky_family is our derivation, not where the art came from
  renderer.skySource = Sky.artSource(path)
  -- overworld-sized: the pic normalises to a 20px creature and the
  -- flyer's own dex scale rides on top at draw; the odd walk phase
  -- nudges it a pixel for a wingless hover.  With a baked card the 2D
  -- draw keeps the full-resolution pic through its own window quad;
  -- self.image and self.frames stay the card's, sized for 3D.
  local k, picImage, picQuad = 20 / size, nil, nil
  if card then
    local okQ, q = pcall(love.graphics.newQuad, 0, 0, size, size, w, h)
    if okQ and q then
      picImage, picQuad = img, q
    else
      k = 20 / CARD
    end
  end
  renderer.draw = function(self, px, py, camX, camY, facing, walkPhase)
    local image = picImage or self.image
    local quad = picQuad or self.frames[0]
    local fx = math.floor(px + 8 - camX)
    local fy = math.floor(py + 12 - camY)
      - ((walkPhase == 1) and 1 or 0)
    local top = fy - 20
    if facing == "right" then
      love.graphics.draw(image, quad, fx + 10, top, 0, -k, k)
    else
      love.graphics.draw(image, quad, fx - 10, top, 0, k, k)
    end
  end
  picCache[key] = renderer
  return renderer
end

-- a cached walker SpriteRenderer for the species, preferring per-species
-- art borrowed from an enabled sprite mod, then the species' icon class,
-- falling back to the bird.  Returns renderer, class; renderer is nil
-- only when even the bird sheet is missing (e.g. the ROM-free fixture
-- base).
function Sky.mountSprite(data, species, seedPrefix, opts)
  local class = species and Sky.iconClass(data, species) or nil
  local mon = species and data.pokemon and data.pokemon[species]
  local borrowed = mon and borrowedSprite(data, species, mon.dex,
    seedPrefix)
  if borrowed then return borrowed, class end
  local spriteId = (class and Sky.MOUNT_SPRITES[class]) or "SPRITE_BIRD"
  local def = data.sprites and data.sprites[spriteId]
  -- Gold arm, probed from the encounter shape so leftover gen2 tables
  -- on a Gen 1 boot never trigger it.  Gold ships NO flying-pose art
  -- at all, so the ladder composes the best of what exists: a
  -- species' own walker sheet where Gold has one, then a choice the
  -- caller can steer with opts.skyArt: "auto" keeps bird-shaped
  -- species (ICON_BIRD) on the flapping walker sheet in their own
  -- colours (wings beat a battle pose in the sky) and dresses every
  -- other shape in its species-true front pic; "portrait" prefers
  -- the pic for everything, "classic" the walker sheets.  Icon
  -- strips are the last resort.  Every sheet rung is baked in the
  -- species' shipped colours.
  local goldColours = false
  local skyArt = opts and opts.skyArt or "auto"
  if Sky.gen2Encounters(data.encounters) then
    local sprites = data.sprites or {}
    local icons = data.gen2Icons
    local iconId = icons and icons.species and icons.species[species]
    local ownDef = sprites["SPRITE_" .. tostring(species)]
    -- bird-shaped by the gen2 icon table, or by the Gen 1 icon class
    -- when that table is silent: a Crystal-shaped Gen 1 boot has
    -- gen2-shaped encounters but only the Gen 1 icons, and its Pidgey
    -- must keep the flapping sheet under AUTO exactly like vanilla
    local birdShape = iconId == "ICON_BIRD"
      or (iconId == nil and class == "BIRD")
    local preferPic
    if skyArt == "portrait" then
      preferPic = ownDef == nil
    elseif skyArt == "classic" then
      preferPic = false
    else
      preferPic = ownDef == nil and not birdShape
    end
    if preferPic then
      local pic = goldPicRenderer(data, species, seedPrefix)
      if pic then return pic, class end
    end
    local walkerDef = ownDef
      or (type(iconId) == "string"
          and sprites[iconId:gsub("^ICON_", "SPRITE_")])
      or sprites.SPRITE_BIRD
    if walkerDef then
      def = walkerDef
      spriteId = (walkerDef.id or "SPRITE_?") .. "_" .. tostring(species)
      goldColours = true
    else
      local pic = not preferPic
        and goldPicRenderer(data, species, seedPrefix) or nil
      if pic then return pic, class end
      local entry = iconId and icons.icons and icons.icons[iconId]
      if entry and entry.image then
        spriteId = "SKY_ICON_" .. tostring(iconId) .. "_"
          .. tostring(species)
        def = { id = spriteId, image = entry.image,
                frames = entry.frames or 1,
                walker = false, spriteType = "POKEMON_SPRITE",
                palette = "PAL_OW_RED", paletteId = 0,
                species = species, icon = iconId }
        goldColours = true
      end
    end
  end
  if not Sky.gen2Encounters(data.encounters) then
    -- the same composition on Gen 1: species records there carry a
    -- front pic too (Crystal 251 extracts real Gen 2 portraits for
    -- its species), so non-bird shapes wear their own portrait
    -- instead of a generic class sheet.  BIRD-class species keep the
    -- flapping sheet, and CLASSIC keeps today's look everywhere.
    local wantPic = skyArt == "portrait"
      or (skyArt == "auto" and class ~= "BIRD")
    if skyArt ~= "classic" and (wantPic or def == nil) then
      local pic = goldPicRenderer(data, species, seedPrefix)
      if pic then return pic, class end
    end
  end
  if not def then return nil, class end
  local key = (seedPrefix or "shared") .. "#" .. spriteId
  if mountCache[key] == nil then
    local SpriteRenderer = require("src.render.SpriteRenderer")
    local okR, renderer = pcall(SpriteRenderer.new, def,
      (seedPrefix or "shared") .. "_" .. spriteId)
    if okR and renderer then
      renderer.skySource = Sky.artSource(def.image)
    end
    mountCache[key] = okR and renderer or false
    -- the species' own shipped colours (its battle-pic pair) make
    -- Gold's shared sheets read per-species instead of engine red
    if mountCache[key] and goldColours then
      pcall(function()
        local Palettes = require("src.world.gen2.Palettes")
        local colors = Palettes.monColors(data.gen2Palettes, species)
        if colors and renderer.setObjPalette then
          renderer:setObjPalette(colors, "sky:" .. tostring(species))
        end
      end)
      -- an icon sheet is a two-frame ANIMATION strip, not a facing
      -- set: the stock pose tables would pin it to one frame forever,
      -- so this draw picks the frame from the caller's flap phase and
      -- mirrors on a rightward heading.  Walker sheets keep the stock
      -- pose tables.
      if def.icon and (def.frames or 1) > 1
         and renderer.getScreenOrigin then
        renderer.draw = function(self, px, py, camX, camY, facing,
                                 walkPhase)
          local x, y = self:getScreenOrigin(px, py, camX, camY)
          local image = self.resolveImage and self:resolveImage()
            or self.image
          local frame = math.floor(walkPhase or 0) % self.frameCount
          local quad = self.frames[frame] or self.frames[0]
          if facing == "right" then
            love.graphics.draw(image, quad, x + self.frameWidth, y,
                               0, -1, 1)
          else
            love.graphics.draw(image, quad, x, y)
          end
        end
      end
    end
  end
  return mountCache[key] or nil, class
end

-- a borrowed walker sheet that declares its own frame geometry (Wilds
-- of Kanto's True Size) already encodes the species' size; scaling it
-- again by dex height would double it.  Pic and icon renderers keep
-- the dex scale: their geometry is a crop box, not a size statement.
function Sky.trueSized(renderer)
  local def = renderer and renderer.def
  if not def or def.walker ~= true then return false end
  return (def.frameWidth or 16) ~= 16 or (def.frameHeight or 16) ~= 16
end

-- dex height -> draw scale: Pidgey reads small, Charizard reads big
function Sky.dexScale(data, species)
  local def = data.pokemon and data.pokemon[species]
  local dex = (def and def.dexEntry) or {}
  local feet = (dex.heightFt or 2) + (dex.heightIn or 0) / 12
  return math.max(0.85, math.min(1.6, 0.75 + feet * 0.14))
end

function Sky.hasType(data, species, wanted)
  local def = data.pokemon and data.pokemon[species]
  for _, t in ipairs((def and def.types) or {}) do
    if t == wanted then return true end
  end
  return false
end

-- ------- generation-agnostic engine reads
-- Gold is a second engine, not a skin: the same questions have
-- different answers there (kind-first encounter tables, no Renderer
-- singleton, a header byte instead of a tileset list).  Everything in
-- this section probes the data or object in hand rather than asking
-- which game is running, so any dataset speaking either shape is
-- understood.

-- Gold keys wild encounters by kind first (encounters.grass[mapId],
-- slots split per time of day); Gen 1 by map first
-- (encounters[mapId].grass.slots)
function Sky.gen2Encounters(enc)
  return type(enc) == "table" and type(enc.grass) == "table"
    and enc.grass.slots == nil and enc.grass.rate == nil
end

-- Gold's overworld is a World instance; stepBody is the probe the
-- engine's own compat adapter uses to tell one from a Gen 1
-- OverworldState
function Sky.goldWorld(ow)
  return ow ~= nil and ow.stepBody ~= nil
end

-- the LIVE overworld.  On Gold, game.overworld is the adapter's
-- facade, which forwards a handful of fields but not the World's own
-- members (stepBody, maps, viewW), so generation probes and neighbor
-- reads against it silently answer wrong; game.world is the real
-- instance there.  Gen 1's game.overworld is already the real state.
function Sky.liveOverworld(game)
  if not game then return nil end
  local world = game.world
  if world ~= nil and world.stepBody ~= nil then return world end
  return game.overworld
end

-- a map's grass encounter slots, or an empty list; the same table the
-- engine rolls classic encounters from.  tod picks the slot table on
-- datasets that split by time of day (Gold's MORN/DAY/NITE)
function Sky.grassSlots(data, mapId, tod)
  local enc = data and data.encounters
  if not enc then return {} end
  if Sky.gen2Encounters(enc) then
    local row = enc.grass[mapId]
    local slots = row and row.slots
    if not slots then return {} end
    return slots[tod] or slots.DAY or {}
  end
  local encDef = enc[mapId]
  local slots = encDef and encDef.grass and encDef.grass.slots
  return slots or {}
end

-- every wild slot table the dataset carries, one row per (map,
-- terrain, period): { mapId, terrain, period, slots }.  period is nil
-- where the dataset has no time-of-day split (all of Gen 1, Gold's
-- water tables)
function Sky.wildRows(data)
  local enc = data and data.encounters
  local rows = {}
  if type(enc) ~= "table" then return rows end
  if Sky.gen2Encounters(enc) then
    for mapId, row in pairs(enc.grass) do
      for period, slots in pairs(row.slots or {}) do
        rows[#rows + 1] = { mapId = mapId, terrain = "grass",
                            period = period, slots = slots }
      end
    end
    for mapId, row in pairs(type(enc.water) == "table" and enc.water
                            or {}) do
      if row.slots then
        rows[#rows + 1] = { mapId = mapId, terrain = "water",
                            slots = row.slots }
      end
    end
  else
    for mapId, def in pairs(enc) do
      for _, terrain in ipairs({ "grass", "water" }) do
        local t = type(def) == "table" and def[terrain]
        if t and t.slots then
          rows[#rows + 1] = { mapId = mapId, terrain = terrain,
                              slots = t.slots }
        end
      end
    end
  end
  return rows
end

-- does the world host wildlife on this map, and on which terrain;
-- nil when the map has no wild tables at all
function Sky.mapWild(data, mapId)
  local enc = data and data.encounters
  if type(enc) ~= "table" then return nil end
  if Sky.gen2Encounters(enc) then
    local g = enc.grass[mapId]
    local w = type(enc.water) == "table" and enc.water[mapId] or nil
    if not (g or w) then return nil end
    return { grass = g ~= nil, water = w ~= nil }
  end
  local def = enc[mapId]
  if type(def) ~= "table" then return nil end
  return {
    grass = (def.grass ~= nil and def.grass.slots ~= nil
             and #def.grass.slots > 0),
    water = def.water ~= nil,
  }
end

-- the map's own slot levels (grass for the given tod, plus water), so
-- callers can deal levels off the local curve
function Sky.slotLevels(data, mapId, tod)
  local levels = {}
  local function take(slots)
    for _, slot in ipairs(slots or {}) do
      if slot.level then levels[#levels + 1] = slot.level end
    end
  end
  take(Sky.grassSlots(data, mapId, tod))
  local enc = data and data.encounters
  if type(enc) == "table" then
    if Sky.gen2Encounters(enc) then
      local row = type(enc.water) == "table" and enc.water[mapId] or nil
      take(row and row.slots)
    else
      local def = enc[mapId]
      take(def and def.water and def.water.slots)
    end
  end
  return levels
end

-- the maps within a few seams and doorways of one map, walked over
-- the connection graph the defs already carry, warps included so a
-- gated area (the Safari Zone) counts as next door to its town.
-- Returns a set of map ids including the start, or nil when the def
-- carries no graph at all: a dataset without one keeps whatever
-- world-wide behavior the caller had.
function Sky.nearbyMaps(data, mapId, hops)
  local maps = data and data.maps
  local def = maps and maps[mapId]
  if not def then return nil end
  local function links(d)
    local out = {}
    for _, c in pairs(d.connections or {}) do
      local id
      if type(c) == "table" then
        id = (type(c.mapId) == "string" and c.mapId)
          or (type(c.map) == "string" and c.map)
      elseif type(c) == "string" then
        id = c
      end
      if id then out[#out + 1] = id end
    end
    for _, w in ipairs(d.warps or {}) do
      if type(w) == "table" and type(w.destMap) == "string" then
        out[#out + 1] = w.destMap
      end
    end
    return out
  end
  if #links(def) == 0 then return nil end
  local near = { [mapId] = true }
  local frontier = { mapId }
  for _ = 1, hops or 2 do
    local grown = {}
    for _, id in ipairs(frontier) do
      local d = maps[id]
      if d then
        for _, link in ipairs(links(d)) do
          if not near[link] then
            near[link] = true
            grown[#grown + 1] = link
          end
        end
      end
    end
    frontier = grown
  end
  return near
end

-- the visible world area in world pixels.  Gen 1's renderer knows it;
-- Gold has no Renderer singleton (reading game.renderer there only
-- puts a warning in the log) and its world carries viewW/viewH
-- instead, unset until the first frame has drawn.  The GB screen is
-- the answer before either has spoken.
function Sky.viewSize(game, ow)
  if ow and ow.viewW and ow.viewH then return ow.viewW, ow.viewH end
  if Sky.goldWorld(ow) then return 160, 144 end
  local r = game and game.renderer
  if r and r.worldViewSize then return r:worldViewSize() end
  return 160, 144
end

-- is there sky over this map?  Gold's headers carry an environment
-- byte and its Map.isOutside ignores the tileset list; Gen 1 needs
-- data.field's list, which Gold does not have (and would warn about),
-- so the list is only fetched where the map record says Gen 1
function Sky.outsideMap(data, mapDef)
  if not mapDef then return false end
  local Map = require("src.world.Map")
  if mapDef.environment ~= nil then
    return Map.isOutside(mapDef) == true
  end
  local FieldDefaults = require("src.world.FieldDefaults")
  return Map.isOutside(mapDef,
    FieldDefaults.field(data, "outsideTilesets")) == true
end

-- how far the journey has come: Gold keeps a flag set at
-- save.player.badges, Gen 1 counts the badge items its data lists
function Sky.badgeCount(data, save)
  if save and save.player and type(save.player.badges) == "table" then
    local n = 0
    for _, has in pairs(save.player.badges) do
      if has then n = n + 1 end
    end
    return n
  end
  local n = 0
  pcall(function()
    local Badges = require("src.inventory.Badges")
    n = Badges.count(data, save) or 0
  end)
  return n
end

-- a mon's display name: nickname first, then the species record's
-- name, then the raw species id
function Sky.monName(data, mon)
  if not mon then return "?" end
  if mon.nickname then return mon.nickname end
  local def = data and data.pokemon and data.pokemon[mon.species]
  return (def and def.name) or tostring(mon.species)
end

function Sky.knowsMove(mon, moveId)
  for _, mv in ipairs((mon and mon.moves) or {}) do
    if (type(mv) == "table" and mv.id or mv) == moveId then return true end
  end
  return false
end

-- One shared self-healing wrap over the overworld update for the whole
-- mod family.  Foreign mods (wilds of kanto's follower engine) restore
-- OC.update wholesale from a snapshot taken before we wrapped it, which
-- silently drops our per-frame ticks; the render.compose hook chain
-- plays watchdog and re-wraps whatever update is current whenever the
-- tag goes missing.  The tag, flag and key list are shared by every mod
-- that calls this, so two sky mods never mistake each other's wrap for
-- a foreign one and fight over the top of the chain.  Each mod
-- registers the OC key its tick lives at; the wrap dispatches to
-- whatever keys are present.
--
-- The watchdog deliberately does NOT touch OC.draw: gen1_modern_ui
-- fingerprints the overworld's shipped draw renderer (rawget compare)
-- and downgrades every menu to classic for the session when the slot
-- holds anything else.  render.compose is a proper engine hook chain,
-- fires every composed frame (battles and menus included), and cannot
-- be amputated by a foreign snapshot restore, so it heals strictly
-- better than the draw wrap it replaces.
local composeHooked = false
local inputHooked = false
function Sky.ensureUpdateWrap(OC, tickKey, hooks)
  local keys = OC.__skyTickKeys or {}
  OC.__skyTickKeys = keys
  if tickKey then
    for _, k in ipairs(keys) do
      if k == tickKey then tickKey = nil; break end
    end
    if tickKey then keys[#keys + 1] = tickKey end
  end

  OC.__skyEnsureUpdateWrap = function()
    if OC.update == OC.__skyUpdateWrap then return end
    -- a tagged wrap existing but not installed means another mod
    -- replaced the update slot; say so, so player logs name the culprit
    -- class instead of showing silently missing features
    if OC.__skyUpdateWrap then
      print("[sky] overworld update hook was replaced by another mod; re-arming")
    end
    local orig = OC.update
    local function wrap(self, dt)
      -- an outer copy of this wrap is mid-frame (a foreign restore can
      -- resurrect an older one inside the chain): pass through and let
      -- the outermost run the ticks exactly once
      if OC.__skyTicking then
        if orig then orig(self, dt) end
        return
      end
      if orig then
        OC.__skyTicking = true
        local ok, err = pcall(orig, self, dt)
        OC.__skyTicking = nil
        if not ok then error(err, 0) end
      end
      for _, key in ipairs(OC.__skyTickKeys or {}) do
        local tick = OC[key]
        if tick then
          local ok, err = pcall(tick, self, dt)
          if not ok then
            print("[sky] " .. key .. " failed: " .. tostring(err))
          end
        end
      end
    end
    OC.__skyUpdateWrap = wrap
    OC.update = wrap
  end
  OC.__skyEnsureUpdateWrap()

  -- claim the pre-fix flag so an older sibling's skylib (free_fly
  -- <=1.5.1 / wild_skies <=1.6.1) skips its OC.draw wrap when a newer
  -- family mod loaded first; a stale wrap from an old copy that ran
  -- earlier can't be unwound (its original draw is private to the
  -- closure), so mixed versions need the older mod updated too
  OC.__skyDrawWrapped = true

  -- Some full visual stacks replace OC.update after composition has already
  -- run. In that ordering the render watchdog heals one frame too early and
  -- solo sky simulation remains detached, while network snapshots can still
  -- make multiplayer look healthy. input.step is the engine's fixed update
  -- seam immediately before the active state advances, so it is a safe
  -- second watchdog; it restores the dispatcher but never ticks simulation.
  if hooks and not inputHooked then
    inputHooked = true
    pcall(function()
      hooks:wrap("input.step", function(nextFn, ...)
        local ensure = OC.__skyEnsureUpdateWrap
        if ensure then ensure() end
        return nextFn(...)
      end)
    end)
  end

  if hooks and not composeHooked then
    composeHooked = true
    -- pcall: an engine old enough to lack the render.compose chain
    -- just loses the watchdog, never the tick (1.6.0-level behavior)
    pcall(function()
      hooks:wrap("render.compose", function(nextFn, ...)
        local ensure = OC.__skyEnsureUpdateWrap
        if ensure then ensure() end
        return nextFn(...)
      end)
    end)
  end
end

-- ------- simulated flight attitude
-- No era game ships flying poses, so motion carries the illusion:
-- lean into turns, pitch with climb and dive, pulse with the flap.
-- Works on any art, portraits included.  The owner updates attitude
-- in its tick and applies the transform around its draw.
function Sky.flightAttitude(f, dt)
  dt = math.max(dt or 1 / 60, 1e-4)
  local h = f.heading or 0
  local last = f.__skyLastHeading or h
  f.__skyLastHeading = h
  local dh = (h - last + math.pi) % (2 * math.pi) - math.pi
  local grounded = f.mode == "ground"
  local targetBank = grounded and 0
    or math.max(-0.3, math.min(0.3, dh / dt * 0.12))
  f.__skyBank = (f.__skyBank or 0)
    + (targetBank - (f.__skyBank or 0)) * math.min(1, dt * 5)
  local alt = f.alt or 0
  local lastAlt = f.__skyLastAlt or alt
  f.__skyLastAlt = alt
  local targetPitch = grounded and 0
    or math.max(-0.28, math.min(0.28, (alt - lastAlt) / dt * -0.005))
  f.__skyPitch = (f.__skyPitch or 0)
    + (targetPitch - (f.__skyPitch or 0)) * math.min(1, dt * 4)
end

-- the transform for one draw: the lean and pitch mirror with the
-- travel direction so the nose leads, and the squash pulses at the
-- flap rate.  Returns rotation (radians) and a vertical scale.
function Sky.flightTransform(f)
  if f.mode == "ground" then return 0, 1 end
  local dir = f.facing == "left" and -1 or 1
  local angle = ((f.__skyBank or 0) + (f.__skyPitch or 0)) * dir
  local squash = 1 - 0.05 * (0.5 + 0.5 * math.sin((f.t or 0)
    * (f.flap or 6) * math.pi))
  return angle, squash
end

-- Gold's world draws its people from world.npcs and never consults
-- the entity list, so a family mod that renders its own creatures
-- hangs a tail on World:drawPeople instead.  Same dispatch shape as
-- ensureUpdateWrap: the wrap installs once per world instance, keys
-- re-register freely, and a hot reload swaps the implementation
-- without stacking wraps.
function Sky.ensureDrawTail(world, key, impl)
  if not (world and world.drawPeople) then return false end
  local keys = world.__skyDrawKeys or {}
  world.__skyDrawKeys = keys
  local seen = false
  for _, k in ipairs(keys) do
    if k == key then seen = true; break end
  end
  if not seen then keys[#keys + 1] = key end
  world[key] = impl
  if not world.__skyDrawTailWrapped then
    world.__skyDrawTailWrapped = true
    local orig = world.drawPeople
    world.drawPeople = function(self, s, billboard)
      orig(self, s, billboard)
      for _, k in ipairs(self.__skyDrawKeys or {}) do
        local draw = self[k]
        if draw then
          local ok, err = pcall(draw, self, s)
          if not ok then
            print("[sky] " .. k .. " draw failed: " .. tostring(err))
          end
        end
      end
    end
  end
  return true
end

return Sky

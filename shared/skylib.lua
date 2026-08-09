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
    resolve = function(exports, game, species, dex)
      if not dex then return nil end
      local reg = exports.render and exports.render.waterSpriteRegistry
      if not (reg and reg.isReady and reg:isReady()) then return nil end
      local waterDef = reg:resolve(dex, "normal", "levitates")
      if type(waterDef) ~= "table" or waterDef.kind ~= "levitates"
         or type(waterDef.image) ~= "string" then
        return nil
      end
      return { image = waterDef.image, frames = waterDef.frames or 6,
               walker = true, trueColor = true, id = waterDef.id }
    end,
  },
}

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

local sourceCache = {}

local function borrowedSprite(species, dex, seedPrefix)
  local okG, Game = pcall(require, "src.core.Game")
  Game = okG and Game or nil
  local exportsById = Game and Game.mods and Game.mods.exports or nil
  for _, source in ipairs(Sky.SPRITE_SOURCES) do
    local exports = source.mod and exportsById and exportsById[source.mod]
      or nil
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

local mountCache = {}

-- a cached walker SpriteRenderer for the species, preferring per-species
-- art borrowed from an enabled sprite mod, then the species' icon class,
-- falling back to the bird.  Returns renderer, class; renderer is nil
-- only when even the bird sheet is missing (e.g. the ROM-free fixture
-- base).
function Sky.mountSprite(data, species, seedPrefix)
  local class = species and Sky.iconClass(data, species) or nil
  local mon = species and data.pokemon and data.pokemon[species]
  local borrowed = mon and borrowedSprite(species, mon.dex, seedPrefix)
  if borrowed then return borrowed, class end
  local spriteId = (class and Sky.MOUNT_SPRITES[class]) or "SPRITE_BIRD"
  local def = data.sprites and data.sprites[spriteId]
  if not def then return nil, class end
  local key = (seedPrefix or "shared") .. "#" .. spriteId
  if not mountCache[key] then
    local SpriteRenderer = require("src.render.SpriteRenderer")
    mountCache[key] = SpriteRenderer.new(def,
      (seedPrefix or "shared") .. "_" .. spriteId)
  end
  return mountCache[key], class
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

-- a map's grass encounter slots, or an empty list; the same table the
-- engine rolls classic encounters from
function Sky.grassSlots(data, mapId)
  local encDef = data and data.encounters and data.encounters[mapId]
  local slots = encDef and encDef.grass and encDef.grass.slots
  return slots or {}
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

return Sky

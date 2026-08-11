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
  -- Gold arm, probed from the encounter shape so leftover gen2 tables
  -- on a Gen 1 boot never trigger it.  Gold's cache ships real walker
  -- sheets for a few dozen species, so the ladder is: the species'
  -- own sheet, then the sheet matching its icon assignment
  -- (ICON_ODDISH -> SPRITE_ODDISH), then the generic bird, and only
  -- then the flat two-frame icon strip (the day-care mon's def
  -- shape).  Every rung is baked in the species' shipped colours
  -- below, so the shared sheets still read per-species.
  local goldColours = false
  if Sky.gen2Encounters(data.encounters) then
    local sprites = data.sprites or {}
    local icons = data.gen2Icons
    local iconId = icons and icons.species and icons.species[species]
    local walkerDef = sprites["SPRITE_" .. tostring(species)]
      or (type(iconId) == "string"
          and sprites[iconId:gsub("^ICON_", "SPRITE_")])
      or sprites.SPRITE_BIRD
    if walkerDef then
      def = walkerDef
      spriteId = (walkerDef.id or "SPRITE_?") .. "_" .. tostring(species)
      goldColours = true
    else
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
  if not def then return nil, class end
  local key = (seedPrefix or "shared") .. "#" .. spriteId
  if mountCache[key] == nil then
    local SpriteRenderer = require("src.render.SpriteRenderer")
    local okR, renderer = pcall(SpriteRenderer.new, def,
      (seedPrefix or "shared") .. "_" .. spriteId)
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

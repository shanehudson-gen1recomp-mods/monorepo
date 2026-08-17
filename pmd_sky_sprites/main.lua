-- PMD Sky Sprites: SpriteCollab's directional sheets as in-air art.
--
-- The sky family (wild_skies, free_fly) resolves flyer and mount art
-- through an ordered list of sprite sources; this mod registers one
-- that answers with the PMDCollab sheet baked for the species' dex
-- number.  Sheets are N frame columns by 8 direction rows (clockwise
-- from facing the camera), so the shared resolver's directional rung
-- draws real diagonals where a caller offers them and clean cardinals
-- everywhere else.  In PMD a flying species flies in its Walk cycle,
-- so the bake prefers Fly, then Hover, then Walk -- and since the sky
-- family only ever asks for airborne species, every answer reads as
-- flight.
--
-- Registration happens at LOAD, not on game.ready: this mod's
-- priority (200) puts it after the sky mods in load order, so their
-- exports are already there -- and the engine's event emitter re-sorts
-- equal-priority listeners on every subscription, which the sky
-- family's update-wrap ordering cannot afford.
return function(mod)
  local BASE = "mods/pmd_sky_sprites/"

  local sheets
  do
    local src = mod:read("data/sheets.lua")
    if src then
      local ok, t = pcall(function()
        return assert((loadstring or load)(src,
          "@pmd_sky_sprites/data/sheets.lua"))()
      end)
      if ok and type(t) == "table" then sheets = t end
    end
  end
  if not sheets then
    mod.log:error("data/sheets.lua missing or invalid; run "
      .. "scripts/pmd_pack.py in the monorepo and repack")
    return
  end

  local function defFor(species, dex)
    local rec = dex and sheets[dex]
    if not rec then return nil end
    return {
      id = "PMD_SKY_" .. tostring(species),
      image = BASE .. "sprites/" .. rec.file,
      frames = rec.frames,
      frameWidth = rec.fw, frameHeight = rec.fh,
      directions = 8, durations = rec.durations,
      frameSubset = rec.subset,
      walker = false, trueColor = true,
      spriteType = "POKEMON_SPRITE", species = species,
    }
  end

  local source = {
    id = "pmd_sky_sprites",
    -- SpriteCollab keys species by NATIONAL dex; the shared resolver's
    -- canonical-dex guard keeps a reordered dex from wearing the wrong
    -- species' wings
    dexKeyed = true,
    resolve = function(_, _, species, dex)
      return defFor(species, dex)
    end,
  }

  local dressed = 0
  for _, id in ipairs({ "wild_skies", "free_fly" }) do
    local handle = mod.find(id)
    local reg = handle and handle.exports
      and handle.exports.registerSpriteSource
    if type(reg) == "function" then
      local ok, accepted = pcall(reg, source)
      if ok and accepted then dressed = dressed + 1 end
    end
  end
  local count = 0
  for _ in pairs(sheets) do count = count + 1 end
  if dressed > 0 then
    mod.log:info("%d species sheets dressing %d sky mods", count, dressed)
  else
    mod.log:info("%d species sheets ready; no sky mod enabled to dress",
      count)
  end

  -- for tests, companion mods (a future Dramatic Sky Ride hookup), and
  -- the curious
  mod.exports.sheetFor = defFor
  mod.exports.source = source
end

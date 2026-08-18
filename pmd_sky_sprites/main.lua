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

  local function loadLib(rel)
    local src = mod:read(rel)
    if not src then return nil end
    local ok, out = pcall(function()
      return assert((loadstring or load)(src,
        "@pmd_sky_sprites/" .. rel))()
    end)
    if ok then return out end
  end

  local sheets = loadLib("data/sheets.lua")
  if type(sheets) ~= "table" then
    sheets = {}
    mod.log:error("data/sheets.lua missing or invalid; run "
      .. "scripts/pmd_pack.py in the monorepo and repack")
  end

  -- Reading the player's cartridge is a setting, not a silent given:
  -- the toggle names what a .nds in the mod folder gets used for, and
  -- turning it off leaves the community sheets alone.  Read at resolve
  -- time, so the manager toggle takes effect without a reboot (the sky
  -- mods re-resolve live sprites on mod.options_changed).
  mod.options:define({
    { key = "rom_import", label = "IMPORT PMD", type = "toggle",
      default = true },
  })

  -- ------- the player's own cartridge, read in-game
  --
  -- A .nds dropped beside main.lua is the player's Explorers of Sky
  -- dump; lib/romread.lua pulls the official in-air sheets straight
  -- out of it at resolve time, so species the community pack does not
  -- cover yet still fly in real PMD art -- from the player's cart, not
  -- from anything this mod ships.  The sheets live only in memory,
  -- served through the engine's Assets.image choke point under
  -- virtual paths, the sky family's card pattern.
  local ROM_PREFIX = BASE .. "rom/"

  local function registerRomImage(rel, image)
    local okA, Assets = pcall(require, "src.render.Assets")
    if not (okA and type(Assets) == "table"
            and type(Assets.image) == "function") then
      return false
    end
    local reg = Assets.__pmdSkyRomSheets
    if not reg then
      reg = {}
      Assets.__pmdSkyRomSheets = reg
      local origImage = Assets.image
      Assets.image = function(path, ...)
        local hit = reg[path]
        if hit then return hit end
        return origImage(path, ...)
      end
    end
    reg[rel] = image
    return true
  end

  local function bakeRomSheet(dex, sheet)
    if not (love and love.image and love.image.newImageData
            and love.graphics and love.graphics.newImage) then
      return nil
    end
    local fw, fh, n = sheet.fw, sheet.fh, sheet.frames
    local okD, id = pcall(love.image.newImageData, fw * n, fh * 8)
    if not (okD and id and id.setPixel) then return nil end
    local pal = sheet.palette
    local okP = pcall(function()
      for dir = 1, 8 do
        local row = sheet.rows[dir]
        for f = 1, n do
          local ox, oy = (f - 1) * fw, (dir - 1) * fh
          for i, v in pairs(row[f]) do
            local c = pal[v + 1]
            id:setPixel(ox + (i - 1) % fw, oy + math.floor((i - 1) / fw),
              c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
          end
        end
      end
    end)
    if not okP then return nil end
    local okI, img = pcall(love.graphics.newImage, id)
    if not okI then return nil end
    local rel = ROM_PREFIX .. ("%04d.png"):format(dex)
    if not registerRomImage(rel, img) then return nil end
    return rel
  end

  -- A 16x16 card of the down-facing first frame, for voxel worlds
  -- that cut a hard-coded 16x16 window from def.image (the shared
  -- resolver swaps it in as the def's image; the sheet itself keeps
  -- serving the directional draw).  ROM sheets never exist as files,
  -- so the card bakes here, straight from the parsed pixels.
  local function bakeRomCard(dex, sheet)
    if not (love and love.image and love.image.newImageData
            and love.graphics and love.graphics.newImage) then
      return nil
    end
    local okD, id = pcall(love.image.newImageData, 16, 16)
    if not (okD and id and id.setPixel) then return nil end
    local fw, fh = sheet.fw, sheet.fh
    local pal, canvas = sheet.palette, sheet.rows[1][1]
    local sx, sy = fw / 16, fh / 16
    local okP = pcall(function()
      for ty = 0, 15 do
        for tx = 0, 15 do
          local x0, y0 = math.floor(tx * sx), math.floor(ty * sy)
          local x1 = math.max(x0, math.ceil((tx + 1) * sx) - 1)
          local y1 = math.max(y0, math.ceil((ty + 1) * sy) - 1)
          local rs, gs, bs, hit, n = 0, 0, 0, 0, 0
          for y = y0, math.min(y1, fh - 1) do
            for x = x0, math.min(x1, fw - 1) do
              local v = canvas[y * fw + x + 1]
              if v then
                local c = pal[v + 1]
                rs, gs, bs = rs + c[1], gs + c[2], bs + c[3]
                hit = hit + 1
              end
              n = n + 1
            end
          end
          if n > 0 and hit / n >= 0.25 then
            id:setPixel(tx, ty, rs / hit / 255, gs / hit / 255,
              bs / hit / 255, 1)
          else
            id:setPixel(tx, ty, 0, 0, 0, 0)
          end
        end
      end
    end)
    if not okP then return nil end
    local okI, img = pcall(love.graphics.newImage, id)
    if not okI then return nil end
    local rel = ROM_PREFIX .. ("card/%04d.png"):format(dex)
    if not registerRomImage(rel, img) then return nil end
    return rel
  end

  local romName
  for _, name in ipairs(mod:list("") or {}) do
    if name:lower():match("%.nds$") then romName = name; break end
  end

  local romReader  -- nil until first asked, false when unusable
  local function reader()
    if romReader ~= nil then return romReader or nil end
    romReader = false
    if not romName then return nil end
    local Rom = loadLib("lib/romread.lua")
    if not Rom then
      mod.log:error("lib/romread.lua missing or invalid")
      return nil
    end
    local bytes = mod:read(romName)
    local r, err = bytes and Rom.open(bytes)
    if not r then
      mod.log:error("%s: %s", romName, err or "unreadable")
      return nil
    end
    romReader = r
    mod.log:info("reading official air sheets from %s", romName)
    return r
  end

  -- which WAN group is each species' air (or airworthy Walk) cycle,
  -- and which frame columns to show -- baked from SpriteCollab
  -- AnimData by scripts/pmd_animdata.py.  No entry, no guessing: the
  -- group indices mean different animations per species.
  local anims = loadLib("data/anims.lua")
  if type(anims) ~= "table" then anims = {} end

  local romRecs = {}
  local function romRec(dex)
    local hit = romRecs[dex]
    if hit ~= nil then return hit or nil end
    romRecs[dex] = false
    local a = anims[dex]
    if not a then return nil end
    local r = reader()
    if not r then return nil end
    local ok, sheet = pcall(r.sheet, r, dex, a.group)
    if not (ok and sheet) then return nil end
    local path = bakeRomSheet(dex, sheet)
    if not path then return nil end
    romRecs[dex] = {
      path = path, anim = a.anim, subset = a.subset,
      card = bakeRomCard(dex, sheet),
      fw = sheet.fw, fh = sheet.fh,
      frames = sheet.frames, durations = sheet.durations,
    }
    return romRecs[dex]
  end

  -- community sheet first (the mod's identity), the player's cart
  -- fills the gaps
  local function defFor(species, dex)
    local rec = dex and (sheets[dex]
      or (mod.options:get("rom_import") and romRec(dex) or nil))
    if not rec then return nil end
    return {
      id = "PMD_SKY_" .. tostring(species),
      image = rec.path or (BASE .. "sprites/" .. rec.file),
      cardImage = rec.card,
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
  local rom = romName and (", plus " .. romName .. " on demand") or ""
  if dressed > 0 then
    mod.log:info("%d species sheets dressing %d sky mods%s",
      count, dressed, rom)
  else
    mod.log:info("%d species sheets ready%s; no sky mod enabled to dress",
      count, rom)
  end

  -- for tests, companion mods (a future Dramatic Sky Ride hookup), and
  -- the curious
  mod.exports.sheetFor = defFor
  mod.exports.source = source
  mod.exports.romFile = function() return romName end
end

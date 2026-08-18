-- Reads in-air animation sheets straight out of the player's own PMD
-- Explorers of Sky (US) cartridge dump, in-game.  The offline twin is
-- scripts/pmd_rom_extract.py in the monorepo; the two implement the
-- same formats (NitroFS, PKDPX, SIR0/WAN, from Project Pokemon's
-- public docs) and are kept honest against each other by a checksum
-- harness there.  Nothing official ships in the mod: the player drops
-- their .nds beside main.lua and the art comes off their cart.
--
-- Pure byte-in, table-out: no love.*, no engine requires, so it runs
-- and tests headless.  Rendering to a real image is the caller's job.
--
-- reader = Rom.open(bytes)          -- nil, err when not a usable ROM
-- sheet  = reader:sheet(dex, group) -- nil when no pack renders that
--                                   -- animation group for the species
-- sheet: { frames, durations, fw, fh, palette, rows }
--   rows is 8 direction lists (clockwise from facing the camera) of
--   `frames` canvases; a canvas maps pixel index (y*fw + x, 1-based)
--   to a palette index, transparent pixels absent.  palette is 16
--   { r, g, b, a } entries, 0-255.

local byte = string.byte
local band, bor = bit.band, bit.bor
local lshift, rshift = bit.lshift, bit.rshift
local floor = math.floor

-- offsets are 0-based throughout, matching the format docs
local function u8(d, o) return byte(d, o + 1) end
local function u16(d, o)
  local a, b = byte(d, o + 1, o + 2)
  return a + b * 256
end
local function u32(d, o)
  local a, b, c, e = byte(d, o + 1, o + 4)
  return a + b * 256 + c * 65536 + e * 16777216
end
local function s16(d, o)
  local v = u16(d, o)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

-- ------- NDS filesystem

local function nitrofsFind(rom, wanted)
  if #rom < 0x50 then return nil end
  local fntOff, fatOff = u32(rom, 0x40), u32(rom, 0x48)
  if fntOff == 0 or fatOff == 0 or fntOff >= #rom or fatOff >= #rom then
    return nil
  end
  local found
  local function walk(dirId, prefix)
    if found then return end
    local entryOff = fntOff + band(dirId, 0xFFF) * 8
    local subOff = u32(rom, entryOff)
    local fid = u16(rom, entryOff + 4)
    local p = fntOff + subOff
    while true do
      local t = u8(rom, p); p = p + 1
      if t == 0 or t == nil then break end
      local nameLen = band(t, 0x7F)
      local name = rom:sub(p + 1, p + nameLen)
      p = p + nameLen
      if band(t, 0x80) ~= 0 then
        local subId = u16(rom, p); p = p + 2
        walk(subId, prefix .. name .. "/")
        if found then return end
      else
        if prefix .. name == wanted then
          local s = u32(rom, fatOff + fid * 8)
          local e = u32(rom, fatOff + fid * 8 + 4)
          found = { s, e }
          return
        end
        fid = fid + 1
      end
    end
  end
  local ok = pcall(walk, 0xF000, "/")
  if not ok then return nil end
  return found
end

-- ------- PKDPX

local function pkdpx(d)
  local ctrl = { byte(d, 8, 16) }
  local outLen = u32(d, 16)
  local src, len = 20, #d
  local out, n = {}, 0
  while n < outLen and src < len do
    local cmd = u8(d, src); src = src + 1
    for bitpos = 7, 0, -1 do
      if n >= outLen or src >= len then break end
      if band(cmd, lshift(1, bitpos)) ~= 0 then
        n = n + 1; out[n] = u8(d, src); src = src + 1
      else
        local cb = u8(d, src); src = src + 1
        local h, lo4 = rshift(cb, 4), band(cb, 0xF)
        local c
        for i = 1, 9 do
          if ctrl[i] == h then c = i - 1; break end
        end
        if c then
          -- per SkyTemple's PX spec: flags 1 and 5 shift ALL nibbles
          -- then restore nibble 0; flags 2-4 / 6-8 touch only the one
          local ny = { lo4, lo4, lo4, lo4 }
          if c == 1 then
            ny = { lo4, lo4 + 1, lo4 + 1, lo4 + 1 }
          elseif c >= 2 and c <= 4 then
            ny[c] = lo4 - 1
          elseif c == 5 then
            ny = { lo4, lo4 - 1, lo4 - 1, lo4 - 1 }
          elseif c >= 6 then
            ny[c - 4] = lo4 + 1
          end
          for i = 1, 4 do ny[i] = band(ny[i], 0xF) end
          n = n + 1; out[n] = bor(lshift(ny[1], 4), ny[2])
          n = n + 1; out[n] = bor(lshift(ny[3], 4), ny[4])
        else
          local lo = u8(d, src); src = src + 1
          local disp = 0x1000 - bor(lshift(lo4, 8), lo)
          for _ = 1, h + 3 do
            n = n + 1; out[n] = out[n - disp]
          end
        end
      end
    end
  end
  local parts, i = {}, 1
  while i <= n do
    local j = math.min(i + 4095, n)
    parts[#parts + 1] = string.char(unpack(out, i, j))
    i = j + 1
  end
  return table.concat(parts)
end

-- ------- WAN

-- OAM shape/size -> pixel dimensions, keyed shape * 4 + size
local OAM_DIMS = {
  [0] = { 8, 8 }, [1] = { 16, 16 }, [2] = { 32, 32 }, [3] = { 64, 64 },
  [4] = { 16, 8 }, [5] = { 32, 8 }, [6] = { 32, 16 }, [7] = { 64, 32 },
  [8] = { 8, 16 }, [9] = { 8, 32 }, [10] = { 16, 32 }, [11] = { 32, 64 },
}

local Wan = {}
Wan.__index = Wan

function Wan.new(d)
  assert(d:sub(1, 4) == "SIR0", "not SIR0")
  local self = setmetatable({ d = d, imgCache = {} }, Wan)
  local wan = u32(d, 4)
  local animInfo, imgInfo = u32(d, wan), u32(d, wan + 4)
  self.mfRef = u32(d, animInfo)
  local groupsPtr = u32(d, animInfo + 8)
  local nGroups = u16(d, animInfo + 12)
  self.imgTable = u32(d, imgInfo)
  local palInfo = u32(d, imgInfo + 4)
  self.palColorsPtr = u32(d, palInfo)
  self.groups = {}
  for g = 0, nGroups - 1 do
    local p = groupsPtr + g * 8
    local seqList, nSeq = u32(d, p), u32(d, p + 4)
    local seqs = {}
    if seqList ~= 0 then
      for i = 0, nSeq - 1 do
        seqs[#seqs + 1] = u32(d, seqList + i * 4)
      end
    end
    self.groups[g + 1] = seqs
  end
  return self
end

function Wan:sequence(ptr)
  local d, frames, p = self.d, {}, ptr
  while #frames < 200 do
    local dur, flag = u8(d, p), u8(d, p + 1)
    local mf = u16(d, p + 2)
    if dur == 0 and flag == 0 and mf == 0 then break end
    frames[#frames + 1] = { dur, mf, s16(d, p + 4), s16(d, p + 6) }
    p = p + 12
  end
  return frames
end

function Wan:metaframes(group)
  local d = self.d
  local p = u32(d, self.mfRef + group * 4)
  local out, lastImg = {}, 0
  while true do
    local img = s16(d, p)
    local attr0, attr1 = u16(d, p + 4), u16(d, p + 6)
    if img < 0 then img = lastImg end
    lastImg = img
    local dims = OAM_DIMS[rshift(attr0, 14) * 4 + rshift(attr1, 14)]
      or OAM_DIMS[0]
    local y = band(attr0, 0xFF)
    if y > 128 then y = y - 256 end
    local x = band(attr1, 0x1FF) - 256
    out[#out + 1] = {
      img = img, x = x, y = y, w = dims[1], h = dims[2],
      hflip = band(attr1, 0x1000) ~= 0, vflip = band(attr1, 0x2000) ~= 0,
    }
    p = p + 10
    if band(attr1, 0x0800) ~= 0 then break end
    if #out > 32 then break end
  end
  return out
end

function Wan:imageBytes(index)
  local hit = self.imgCache[index]
  if hit then return hit end
  local d = self.d
  local p = u32(d, self.imgTable + index * 4)
  local parts = {}
  while true do
    local src = u32(d, p)
    local amt = u16(d, p + 4)
    if src == 0 and amt == 0 then break end
    if src == 0 then
      parts[#parts + 1] = string.rep("\0", amt)
    else
      parts[#parts + 1] = d:sub(src + 1, src + amt)
    end
    p = p + 12
  end
  local out = table.concat(parts)
  self.imgCache[index] = out
  return out
end

function Wan:palette()
  local d, colors = self.d, {}
  for i = 0, 15 do
    local p = self.palColorsPtr + i * 4
    colors[i + 1] = { u8(d, p), u8(d, p + 1), u8(d, p + 2),
                      i == 0 and 0 or 255 }
  end
  return colors
end

local function drawMetaframe(canvas, cw, ch, wan, mf, xo, yo, cx, cy)
  local data = wan:imageBytes(mf.img)
  local w, h = mf.w, mf.h
  local tilesW = floor(w / 8)
  local dlen = #data
  local baseX, baseY = cx + mf.x + xo, cy + mf.y + yo
  for py = 0, h - 1 do
    for px = 0, w - 1 do
      local tile = floor(py / 8) * tilesW + floor(px / 8)
      local inTile = (py % 8) * 8 + px % 8
      local bi = tile * 32 + floor(inTile / 2)
      if bi < dlen then
        local b = byte(data, bi + 1)
        local v = inTile % 2 == 0 and band(b, 0xF) or rshift(b, 4)
        if v ~= 0 then
          local ox = baseX + (mf.hflip and w - 1 - px or px)
          local oy = baseY + (mf.vflip and h - 1 - py or py)
          if ox >= 0 and ox < cw and oy >= 0 and oy < ch then
            canvas[oy * cw + ox + 1] = v
          end
        end
      end
    end
  end
end

-- Same sanity rails as the offline extractor: junk where a group
-- should be reads as a runaway animation, and without these one bad
-- species tries to bake a sixty-thousand-pixel sheet.
local MAX_FRAMES, MAX_DURATION, MAX_FRAME_PX = 40, 120, 256

local function renderGroup(wan, groupIndex)
  local seqs = wan.groups[groupIndex + 1]
  if not seqs or #seqs ~= 8 then return nil end
  local dirs = {}
  for i = 1, 8 do dirs[i] = wan:sequence(seqs[i]) end
  local n = #dirs[1]
  if n == 0 or n > MAX_FRAMES then return nil end
  local durations = {}
  for f = 1, n do
    local dur = dirs[1][f][1]
    if dur > MAX_DURATION then return nil end
    durations[f] = dur
  end
  local loX, loY, hiX, hiY = 1e6, 1e6, -1e6, -1e6
  for i = 1, 8 do
    if #dirs[i] ~= n then return nil end
    for f = 1, n do
      local xo, yo = dirs[i][f][3], dirs[i][f][4]
      for _, mf in ipairs(wan:metaframes(dirs[i][f][2])) do
        loX = math.min(loX, mf.x + xo)
        loY = math.min(loY, mf.y + yo)
        hiX = math.max(hiX, mf.x + xo + mf.w)
        hiY = math.max(hiY, mf.y + yo + mf.h)
      end
    end
  end
  local fw = math.max(8, hiX - loX)
  local fh = math.max(8, hiY - loY)
  if fw > MAX_FRAME_PX or fh > MAX_FRAME_PX then return nil end
  fw = fw + fw % 2
  fh = fh + fh % 2
  local cx, cy = -loX, -loY
  local rows = {}
  for i = 1, 8 do
    local row = {}
    for f = 1, n do
      local canvas = {}
      local metas = wan:metaframes(dirs[i][f][2])
      for m = #metas, 1, -1 do
        drawMetaframe(canvas, fw, fh, wan, metas[m],
          dirs[i][f][3], dirs[i][f][4], cx, cy)
      end
      row[f] = canvas
    end
    rows[i] = row
  end
  return { frames = n, durations = durations,
           fw = fw, fh = fh, palette = wan:palette(), rows = rows }
end

-- ------- the reader

-- The game splits each species' 13 animation groups across three
-- packs (Hover lives in m_attack, Walk in monster/m_ground); a group
-- index means the same animation wherever it renders, so a sheet
-- request just tries the packs in turn.  Which index IS a species'
-- air animation comes from the caller (data/anims.lua, baked from
-- SpriteCollab AnimData -- slot 4 is Spearow's Hover but Pidgeot's
-- FlapAround tumble, so it cannot be hard-coded).
local PACKS = { "/MONSTER/m_attack.bin", "/MONSTER/monster.bin",
                "/MONSTER/m_ground.bin" }

local Reader = {}
Reader.__index = Reader

-- Sprite packs are NOT dex-indexed: gender-variant slots are
-- interleaved through the list (12 of them by Gyarados, and a small
-- reorder around Skarmory), so dex 144 read as a slot is Ditto
-- wearing Articuno's name.  The game's own species table,
-- /BALANCE/monster.md, carries each species' sprite slot; without it
-- the dex is used as-is (the identity holds for a synthetic fixture).
function Reader:spriteSlot(dex)
  local md = self.md
  if not md then return dex end
  if dex < 1 or dex >= md.count then return dex end
  return u16(md.d, 8 + dex * md.esz + 16)
end

local function packEntry(pack, dex)
  if dex < 0 or dex >= pack.count then return nil end
  local d = pack.d
  local off = u32(d, 8 + dex * 8)
  local size = u32(d, 12 + dex * 8)
  if size == 0 or off + size > #d then return nil end
  local e = d:sub(off + 1, off + size)
  if e:sub(1, 5) == "PKDPX" then
    local ok, plain = pcall(pkdpx, e)
    if not ok then return nil end
    e = plain
  end
  if e:sub(1, 4) ~= "SIR0" then return nil end
  return e
end

function Reader:sheet(dex, group)
  if type(group) ~= "number" then return nil end
  local slot = self:spriteSlot(dex)
  for _, pack in ipairs(self.packs) do
    local d = packEntry(pack, slot)
    if d then
      local ok, sheet = pcall(function()
        return renderGroup(Wan.new(d), group)
      end)
      if ok and sheet then return sheet end
    end
  end
  return nil
end

local Rom = {}

-- The whole ROM comes in, only the monster sprite packs stay: the
-- caller can drop its 134MB string right after this returns.
function Rom.open(bytes)
  if type(bytes) ~= "string" or #bytes < 0x50 then
    return nil, "not an NDS ROM"
  end
  local packs = {}
  for _, name in ipairs(PACKS) do
    local range = nitrofsFind(bytes, name)
    if range and range[2] > range[1] and range[2] <= #bytes then
      local d = bytes:sub(range[1] + 1, range[2])
      local count = #d >= 16 and u32(d, 4) or 0
      if count > 0 and count <= 4096 then
        packs[#packs + 1] = { d = d, count = count }
      end
    end
  end
  if #packs == 0 then
    return nil, "no /MONSTER sprite packs (not an Explorers of Sky ROM?)"
  end
  local md
  local range = nitrofsFind(bytes, "/BALANCE/monster.md")
  if range and range[2] > range[1] and range[2] <= #bytes then
    local d = bytes:sub(range[1] + 1, range[2])
    local count = #d >= 8 and d:sub(1, 2) == "MD" and u32(d, 4) or 0
    if count > 0 and count <= 8192 and #d > 8 then
      md = { d = d, count = count,
             esz = math.floor((#d - 8) / count) }
      if md.esz < 18 then md = nil end
    end
  end
  return setmetatable({ packs = packs, md = md }, Reader)
end

return Rom

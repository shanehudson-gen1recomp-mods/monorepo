-- The in-game ROM reader against a synthetic cartridge: a hand-built
-- NitroFS image whose /MONSTER/m_attack.bin holds one uncompressed
-- SIR0/WAN with a Hover group (dex 1, two frames, all eight
-- directions), so the parse, the def ladder and the Assets.image
-- choke point are all exercised without a byte of Nintendo's data.
package.path = "./?.lua;./?/init.lua;" .. package.path

local io = require("io")
local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local dir = os.getenv("MOD_DIR") or "mods/pmd_sky_sprites"
local skyDir = dir:gsub("pmd_sky_sprites", "wild_skies")

-- ------- fixture builder

local function buf()
  local b = { parts = {}, len = 0 }
  function b:bytes(s)
    self.parts[#self.parts + 1] = s
    self.len = self.len + #s
  end
  function b:u8(v) self:bytes(string.char(v % 256)) end
  function b:u16(v)
    self:bytes(string.char(v % 256, math.floor(v / 256) % 256))
  end
  function b:u32(v)
    self:bytes(string.char(v % 256, math.floor(v / 256) % 256,
      math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256))
  end
  function b:pad(n) self:bytes(string.rep("\0", n)) end
  function b:str() return table.concat(self.parts) end
  return b
end

-- dexes whose data/anims.lua rows point at group 4: Spearow's Hover
-- and Pidgeotto's FlapAround (whose row also carries the flap subset).
-- The fixture's monster.md maps BOTH to sprite slot 33, off their dex
-- on purpose: sprite packs are not dex-indexed (the Articuno-in-
-- Ditto's-feathers bug), and this proves the mapping is honored.
local HOVER_DEX, FLAP_DEX, WAN_SLOT = 21, 17, 33
local DUR_A, DUR_B = 3, 5
local ENTRIES = 34
local MD_COUNT = 24

local function buildWan()
  local base = 16  -- SIR0 header
  local IMG_DATA = base            -- one 8x8 tile, every pixel colour 1
  local STRIP = IMG_DATA + 32
  local IMGTAB = STRIP + 24
  local PALDATA = IMGTAB + 4
  local PALINFO = PALDATA + 64
  local MF0 = PALINFO + 4
  local MFREF = MF0 + 10
  local SEQ = MFREF + 4
  local SEQLIST = SEQ + 36
  local GROUPS = SEQLIST + 32
  local AI = GROUPS + 40
  local II = AI + 16
  local W = II + 16

  local b = buf()
  b:bytes("SIR0"); b:u32(W); b:u32(0); b:u32(0)
  b:bytes(string.rep(string.char(0x11), 32))            -- IMG_DATA
  b:u32(IMG_DATA); b:u16(32); b:pad(6); b:pad(12)       -- STRIP + end
  b:u32(STRIP)                                          -- IMGTAB
  b:pad(4)                                              -- colour 0
  b:u8(200); b:u8(30); b:u8(40); b:u8(0)                -- colour 1
  b:pad(56)                                             -- colours 2-15
  b:u32(PALDATA)                                        -- PALINFO
  b:u16(0); b:u16(0); b:u16(0); b:u16(0x0900); b:u16(0) -- MF0 (is_last)
  b:u32(MF0)                                            -- MFREF
  for _, dur in ipairs({ DUR_A, DUR_B }) do             -- SEQ
    b:u8(dur); b:u8(0); b:u16(0); b:u16(0); b:u16(0); b:pad(4)
  end
  b:pad(12)                                             -- SEQ terminator
  for _ = 1, 8 do b:u32(SEQ) end                        -- SEQLIST
  for _ = 1, 4 do b:u32(0); b:u32(0) end                -- groups 0-3
  b:u32(SEQLIST); b:u32(8)                              -- group 4: Hover
  b:u32(MFREF); b:u32(0); b:u32(GROUPS); b:u16(5); b:u16(0)  -- AI
  b:u32(IMGTAB); b:u32(PALINFO); b:u16(0); b:u16(0)     -- II
  b:u16(0); b:u16(1)                                    -- n_imgs
  local blob = b:str()
  assert(#blob == W, "fixture WAN layout drifted")
  b:u32(AI); b:u32(II)                                  -- W
  return b:str()
end

local function buildRom()
  local wan = buildWan()
  local wanOff = 8 + ENTRIES * 8
  local p = buf()
  p:pad(4); p:u32(ENTRIES)
  for slot = 0, ENTRIES - 1 do
    if slot == WAN_SLOT then p:u32(wanOff); p:u32(#wan)
    else p:u32(0); p:u32(0) end
  end
  p:bytes(wan)
  local pack = p:str()

  local md = buf()
  md:bytes("MD"); md:pad(2); md:u32(MD_COUNT)
  for i = 0, MD_COUNT - 1 do                    -- 68-byte entries,
    md:pad(16)                                  -- sprite slot at +16
    md:u16((i == HOVER_DEX or i == FLAP_DEX) and WAN_SLOT or i)
    md:pad(50)
  end
  local mdBlob = md:str()

  local packAt, mdAt = 0xE0, 0xE0 + #pack
  local r = buf()
  r:pad(0x40)
  r:u32(0x50); r:u32(71); r:u32(0xD0); r:u32(16)        -- FNT / FAT
  r:u32(24); r:u16(0); r:u16(0)                         -- root dir entry
  r:u32(45); r:u16(0); r:u16(0)                         -- MONSTER entry
  r:u32(59); r:u16(1); r:u16(0)                         -- BALANCE entry
  r:u8(0x87); r:bytes("MONSTER"); r:u16(0xF001)
  r:u8(0x87); r:bytes("BALANCE"); r:u16(0xF002); r:u8(0)
  r:u8(12); r:bytes("m_attack.bin"); r:u8(0)
  r:u8(10); r:bytes("monster.md"); r:u8(0)
  r:pad(0xD0 - r.len)
  r:u32(packAt); r:u32(packAt + #pack)                  -- file 0
  r:u32(mdAt); r:u32(mdAt + #mdBlob)                    -- file 1
  r:bytes(pack)
  r:bytes(mdBlob)
  return r:str()
end

local rom = buildRom()

-- ------- the parser, pure

local Rom = dofile(dir .. "/lib/romread.lua")
T.check(Rom.open("not a rom") == nil, "junk bytes answer nil")

local reader = Rom.open(rom)
T.check(reader ~= nil, "fixture ROM opens")
T.eq(reader:spriteSlot(HOVER_DEX), WAN_SLOT,
  "monster.md maps the dex to its sprite slot")
local sheet = reader:sheet(HOVER_DEX, 4)
T.check(sheet ~= nil, "fixture dex parses through the slot mapping")
T.eq(sheet.frames, 2, "two frames")
T.eq(sheet.durations[1], DUR_A, "first duration")
T.eq(sheet.durations[2], DUR_B, "second duration")
T.eq(sheet.fw, 8, "frame width from the metaframe extents")
T.eq(sheet.fh, 8, "frame height from the metaframe extents")
T.eq(#sheet.rows, 8, "all eight directions")
T.eq(sheet.rows[8][2][64], 1, "pixels carry the palette index")
T.eq(sheet.palette[2][1], 200, "palette colours read")
T.eq(sheet.palette[2][4], 255, "non-zero colours opaque")
T.eq(sheet.palette[1][4], 0, "colour zero transparent")
T.check(reader:sheet(HOVER_DEX, 0) == nil,
  "a group the fixture lacks answers nil")
T.check(reader:sheet(3, 4) == nil, "an empty pack entry answers nil")
T.check(reader:sheet(999, 4) == nil, "past the pack answers nil")

-- ------- through the mod, fixture dropped beside main.lua

local fixturePath = dir .. "/00_pmd_fixture.nds"
local f = assert(io.open(fixturePath, "wb"))
f:write(rom); f:close()

local ok, err = pcall(function()
  local run = T.sdk.loadMods({ skyDir, dir }, { data = Data })
  T.eq(#run.errors, 0, "loads clean with a ROM present")
  local api = run.loader.exports.pmd_sky_sprites
  T.eq(api.romFile(), "00_pmd_fixture.nds", "the .nds is discovered")

  -- Spearow has no community sheet, so this answer can only have
  -- come off the fixture cartridge, at the group its anims row names
  local def = api.sheetFor("SPEAROW", HOVER_DEX)
  T.check(def ~= nil, "the ROM fills a species the pack lacks")
  T.eq(def.image, "mods/pmd_sky_sprites/rom/0021.png",
    "served under the mod's virtual rom/ path")
  T.eq(def.frames, 2, "frame count from the cart")
  T.eq(def.durations[2], DUR_B, "durations from the cart")
  T.eq(def.directions, 8, "eight direction rows")
  T.eq(def.trueColor, true, "full-colour art bypasses the palette bakes")
  T.eq(def.frameSubset, nil, "a Hover row shows every column")

  -- Pidgeotto's row is FlapAround, a tumble: the def masks it down to
  -- the two clean flap columns
  local flap = api.sheetFor("PIDGEOTTO", FLAP_DEX)
  T.check(flap ~= nil, "a FlapAround species resolves")
  T.check(type(flap.frameSubset) == "table" and flap.frameSubset[1] == 1
    and flap.frameSubset[2] == 2, "masked to the clean flap columns")

  local Assets = require("src.render.Assets")
  T.check(Assets.image(def.image) ~= nil,
    "the Assets.image choke point serves the baked sheet")

  -- the IMPORT PMD toggle gates the cartridge rung, live
  local schema = run.loader.optionSchemas.pmd_sky_sprites
  local row
  for _, r in ipairs(schema or {}) do
    if r.key == "rom_import" then row = r end
  end
  T.check(row ~= nil, "the IMPORT PMD option is declared")
  T.eq(row["type"], "toggle", "as a toggle")
  T.eq(row.default, true, "on by default")
  run.loader.modOptions.pmd_sky_sprites = { rom_import = false }
  T.eq(api.sheetFor("SPEAROW", HOVER_DEX), nil,
    "toggled off, the cartridge stops answering")
  run.loader.modOptions.pmd_sky_sprites = { rom_import = true }
  T.check(api.sheetFor("SPEAROW", HOVER_DEX) ~= nil,
    "toggled back on, it answers again without a reboot")

  T.eq(api.sheetFor("MISSINGNO", 9999), nil, "unknown dex still nil")
  run.release()
end)

os.remove(fixturePath)
assert(ok, err)

T.finish("pmd_rom_import")

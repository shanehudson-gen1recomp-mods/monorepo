-- Verifies pmd_sky_sprites/lib/romread.lua against the Python
-- extractor on a real ROM: both sides render every Hover sheet and
-- compare geometry, durations and a pixel checksum.
--
--   python3 scripts/pmd_rom_ref.py rom.nds > ref.json
--   luajit scripts/pmd_rom_verify.lua rom.nds ref.json

local romPath, refPath = arg[1], arg[2]
assert(romPath and refPath,
  "usage: luajit scripts/pmd_rom_verify.lua <rom.nds> <ref.json>")

local root = arg[0]:match("^(.*)/scripts/") or "."
local Rom = dofile(root .. "/pmd_sky_sprites/lib/romread.lua")
local anims = dofile(root .. "/pmd_sky_sprites/data/anims.lua")

local f = assert(io.open(romPath, "rb"))
local bytes = f:read("*a"); f:close()
local reader = assert(Rom.open(bytes))
bytes = nil; collectgarbage()

-- just enough JSON for the flat shape pmd_rom_ref.py emits
local rf = assert(io.open(refPath, "rb"))
local json = rf:read("*a"); rf:close()
local ref = {}
for dexStr, body in json:gmatch('"(%d+)": {(.-)}') do
  local rec = {
    frames = tonumber(body:match('"frames": (%d+)')),
    fw = tonumber(body:match('"fw": (%d+)')),
    fh = tonumber(body:match('"fh": (%d+)')),
    chk = tonumber(body:match('"chk": (%d+)')),
    durations = {},
  }
  for d in body:match('"durations": %[(.-)%]'):gmatch("%d+") do
    rec.durations[#rec.durations + 1] = tonumber(d)
  end
  ref[tonumber(dexStr)] = rec
end

local bad, got = 0, 0
for dex = 1, 251 do
  local sheet = anims[dex] and reader:sheet(dex, anims[dex].group)
  local want = ref[dex]
  if (sheet == nil) ~= (want == nil) then
    bad = bad + 1
    print(("dex %d: presence mismatch (lua=%s python=%s)"):format(
      dex, tostring(sheet ~= nil), tostring(want ~= nil)))
  elseif sheet then
    got = got + 1
    local durOk = #sheet.durations == #want.durations
    if durOk then
      for i = 1, #want.durations do
        if sheet.durations[i] ~= want.durations[i] then durOk = false end
      end
    end
    local chk = 0
    for di = 0, 7 do
      for fi = 0, sheet.frames - 1 do
        for i, v in pairs(sheet.rows[di + 1][fi + 1]) do
          local c = sheet.palette[v + 1]
          chk = (chk + (di * 7919 + fi * 104729 + i)
            * (c[1] + 2 * c[2] + 4 * c[3] + 8)) % 2147483647
        end
      end
    end
    if sheet.frames ~= want.frames or sheet.fw ~= want.fw
        or sheet.fh ~= want.fh or not durOk or chk ~= want.chk then
      bad = bad + 1
      print(("dex %d: MISMATCH frames %d/%d fw %d/%d fh %d/%d chk %d/%d")
        :format(dex, sheet.frames, want.frames, sheet.fw, want.fw,
                sheet.fh, want.fh, chk, want.chk))
    end
  end
end
print(("%d species compared, %d mismatches"):format(got, bad))
os.exit(bad == 0 and 0 or 1)

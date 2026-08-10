-- The curated sky-trainer donor table: every donor must resolve to a
-- real trainer party AND a real map object header (its dialogue is
-- reused verbatim), and the mount pick must ride a FLY-capable roster
-- mon, falling back to a level-fitted Pidgeot only when none exists.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

package.loaded["src.core.Game"] = {
  data = Data,
  overworld = { entities = {} },
  renderer = { worldViewSize = function() return 160, 144 end },
}

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local dbg = run.loader.exports.wild_skies.__skyTrainerDebug
T.check(type(dbg) == "table", "debug seam exported")
T.check(type(dbg.donors) == "table" and #dbg.donors >= 8,
  "at least 8 curated donors")

local function hasFly(species)
  local def = Data.pokemon[species]
  for _, m in ipairs((def and def.tmhm) or {}) do
    if m == "FLY" then return true end
  end
  return false
end

for i, d in ipairs(dbg.donors) do
  local cls = Data.trainers[d.class]
  local party = cls and cls.parties[d.party]
  T.check(party ~= nil and #party > 0,
    ("donor %d: %s party %d exists"):format(i, tostring(d.class), d.party))
  local h = Data:trainerHeader(d.donor.map, d.donor.index)
  T.check(h ~= nil and h.battle ~= nil and h.won ~= nil
    and h.after ~= nil,
    ("donor %d: header %s[%d] has battle/won/after"):format(
      i, tostring(d.donor.map), d.donor.index))
  T.check(type(d.badges) == "table" and d.badges[1] >= 0
    and d.badges[1] <= d.badges[2] and d.badges[2] <= 8,
    ("donor %d: sane badge band"):format(i))
end

-- a real donor rides its own strongest FLY-capable mon
local d1 = dbg.donors[1]
local mount = dbg.donorMount(package.loaded["src.core.Game"],
  d1.class, d1.party)
T.check(mount ~= nil and hasFly(mount.species),
  "curated donor mount is FLY-capable")
T.check(mount.fallback ~= true, "no fallback needed for a bird roster")
local best = 0
for _, m in ipairs(Data.trainers[d1.class].parties[d1.party]) do
  if hasFly(m.species) then best = math.max(best, m.level) end
end
T.eq(mount.level, best, "mount is the strongest eligible roster mon")

-- a roster with no FLY user rides a fitted Pidgeot
Data.trainers.OPP_SKY_TEST = { parties = { {
  { species = "GEODUDE", level = 20 },
  { species = "ONIX", level = 30 },
} } }
local fb = dbg.donorMount(package.loaded["src.core.Game"],
  "OPP_SKY_TEST", 1)
T.eq(fb.species, "PIDGEOT", "no-fly roster gets a Pidgeot")
T.eq(fb.fallback, true, "flagged as the fallback")
T.check(fb.level >= 20 and fb.level <= 30,
  "Pidgeot level clamped inside the roster band")
Data.trainers.OPP_SKY_TEST = nil

run.release()
T.finish("wild_skies_trainer_roster")

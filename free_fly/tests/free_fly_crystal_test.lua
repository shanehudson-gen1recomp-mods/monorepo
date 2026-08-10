-- Gen 2 mounts: free_fly never keeps a species list, so a dataset
-- overhaul (Crystal 251) that registers Johto species into the merged
-- data gets flight for free.  A Hoothoot that knows FLY mounts like
-- any bird, a FLY-compatible Gen 2 species passes the same tmhm bar
-- the teach path uses, and a flightless newcomer stays grounded.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

-- the overhaul's footprint: Gen 2 species in data.pokemon, with the
-- machine list Crystal imports from the ROM
Data.pokemon.HOOTHOOT = {
  dex = 163, types = { "NORMAL", "FLYING" }, tmhm = { "FLY" },
}
Data.pokemon.SKARMORY = {
  dex = 227, types = { "STEEL", "FLYING" }, tmhm = { "FLY" },
}
Data.pokemon.STEELIX = {
  dex = 208, types = { "STEEL", "GROUND" }, tmhm = {},
}

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/free_fly",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local Runtime = require("src.mods.Runtime")

local ow = {
  map = { def = { tileset = "FOREST" } }, -- open sky without map data
  player = {},
}

local function menuFor(mon)
  local game = {
    data = Data,
    save = { party = { mon }, inventory = { THUNDERBADGE = true } },
  }
  -- the engine's partyKnows nominates a field-move user; for this test
  -- it always offers the mon under scrutiny
  ow.partyKnows = function() return mon end
  local out = Runtime.call("ui.party.submenu",
    function(_, items) return items end,
    game, {}, mon, { overworld = ow })
  for _, item in ipairs(out or {}) do
    if item.label == "FREEFLY" then return true end
  end
  return false
end

-- a Gen 2 bird that knows FLY mounts with no special-casing anywhere
T.check(menuFor({ species = "HOOTHOOT",
  moves = { { id = "FLY", pp = 15 } } }),
  "a FLY-knowing Hoothoot offers FREEFLY")

-- the compat path: with a relaxing mod on the engine's eligibility
-- chain, FLY compatibility still gates off the same data-driven tmhm
-- list the teach path reads, so a compatible Gen 2 species qualifies
-- and a flightless one never does
local removeRelax = Runtime.hooks:wrap("fieldmove.eligibility",
  function(next, ...) return next(...) end)

T.check(menuFor({ species = "SKARMORY", moves = {} }),
  "a FLY-compatible Skarmory qualifies through the relaxed chain")
T.check(not menuFor({ species = "STEELIX", moves = {} }),
  "a flightless Steelix stays grounded even with the chain relaxed")

removeRelax()

Data.pokemon.HOOTHOOT = nil
Data.pokemon.SKARMORY = nil
Data.pokemon.STEELIX = nil
run.release()
T.finish("free_fly_crystal")

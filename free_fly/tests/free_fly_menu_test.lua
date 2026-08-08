-- The FREEFLY submenu entry through the real hook chain: the gift
-- marker and knowing FLY each suffice on their own (randomizers can
-- strip moves or species compat), while the badge gate still holds for
-- ordinary mons.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/free_fly",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local Runtime = require("src.mods.Runtime")

local ow = {
  map = { def = { tileset = "FOREST" } }, -- open sky without map data
  player = {},
}

local function menuFor(mon, badge, battle)
  local game = {
    data = Data,
    save = { party = { mon }, inventory = badge and { THUNDERBADGE = true } or {} },
  }
  local out = Runtime.call("ui.party.submenu",
    function(_, items) return items end,
    game, {}, mon, { overworld = ow, battle = battle })
  for _, item in ipairs(out or {}) do
    if item.label == "FREEFLY" then return true end
  end
  return false
end

-- the gift marker alone is enough: no FLY in the moves, no badge, and
-- the species' data doesn't matter (a randomizer may have mangled both)
T.check(menuFor({ species = "PIDGEOT", freeFlyGift = true, moves = {} }, false),
  "gift marker shows FREEFLY with no FLY and no badge")

-- knowing FLY is enough even when the species' compat list disagrees
T.check(menuFor({ species = "RATTATA",
  moves = { { id = "FLY", pp = 15 } } }, true),
  "a FLY knower shows FREEFLY despite hostile species data")

-- the badge gate still holds for a non-gift FLY knower
T.check(not menuFor({ species = "PIDGEOT",
  moves = { { id = "FLY", pp = 15 } } }, false),
  "no badge and no marker withholds FREEFLY")
T.check(menuFor({ species = "PIDGEOT",
  moves = { { id = "FLY", pp = 15 } } }, true),
  "the badge unlocks the same mon")

-- compatibility alone is not enough: no move, no marker, no relaxing mod
T.check(not menuFor({ species = "PIDGEOT", moves = {} }, true),
  "a compatible non-knower stays hidden without a relaxing mod")

-- the battle switch menu runs through the same hook; FREEFLY there let
-- a mid-battle switch unwind the battle and take off
local flyer = { species = "PIDGEOT", moves = { { id = "FLY", pp = 15 } } }
T.check(not menuFor(flyer, true, {}),
  "an eligible flyer stays hidden in the battle switch menu")

-- the mod also tracks battles itself, so a menu context that forgets to
-- say battle (another mod's picker, a stale screen) still shows nothing
Runtime.emit("battle.started", {})
T.check(not menuFor(flyer, true),
  "a running battle hides FREEFLY even without a battle ctx")
Runtime.emit("battle.ended", {})
T.check(menuFor(flyer, true),
  "the entry returns once the battle ends")

run.release()
T.finish("free_fly_menu")

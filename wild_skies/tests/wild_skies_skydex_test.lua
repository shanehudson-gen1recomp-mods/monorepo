-- The Sky Dex through a real loader: the species list derives from the
-- live dataset in dex order, the lane model leads with AUTO (the row
-- the sky flies by default), the START menu gains a SKY DEX entry on
-- the mod hook chain, and the pushed screen navigates and closes
-- headless.  Art renderers may be nil without a render stack; the
-- model's shape must hold either way.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data"); Data:load()

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.eq(#run.errors, 0, "loads clean")

local api = run.loader.exports.wild_skies
T.check(api ~= nil, "exports registered")
T.check(type(api.openSkyDex) == "function", "openSkyDex exported")
T.check(type(api.skyDexLanes) == "function", "skyDexLanes exported")

-- the lane model: one row per SKY ART choice, AUTO first
local lanes = api.skyDexLanes(Data, "PIDGEY")
T.eq(#lanes, 3, "three art lanes")
T.eq(lanes[1].key, "auto", "AUTO lane leads")
T.eq(lanes[2].key, "portrait", "then PORTRAIT")
T.eq(lanes[3].key, "classic", "then CLASSIC")
for _, lane in ipairs(lanes) do
  T.check(type(lane.label) == "string" and type(lane.tag) == "string",
    "lane " .. lane.key .. " carries label and tag")
  T.check(lane.renderer == nil or type(lane.source) == "string",
    "lane " .. lane.key .. " names its art source when resolved")
end

-- the START menu hook: SKY DEX lands on the item list both gens build
local items = Runtime.call("ui.start_menu.items",
  function(_, its) return its end, nil,
  { { label = "POKéDEX" }, { label = "QUIT" } })
local found
for _, item in ipairs(items) do
  if item.label == "SKY DEX" then found = item end
end
T.check(found ~= nil, "SKY DEX entry injected into the START menu")
T.check(type(found.onSelect) == "function", "with an onSelect")

-- the screen: opens on a stubbed game, pages through species, closes
local pressed = {}
local popped = false
local game = {
  data = Data,
  input = {
    wasPressed = function(_, key) return pressed[key] == true end,
    isDown = function() return false end,
  },
  stack = {
    push = function(self, s) self.topState = s end,
    pop = function(self) popped = true end,
  },
}
local screen = api.openSkyDex(game)
T.check(screen ~= nil and game.stack.topState == screen,
  "a screen state is pushed")
T.eq(screen.index, 1, "opens on the first species")

-- only flight-capable species: FLYING types and FLY learners, nothing
-- else, derived from the dataset rather than a hand list
local listed = {}
for _, entry in ipairs(screen.list) do listed[entry.species] = true end
T.check(listed.PIDGEY, "FLYING types are listed (PIDGEY)")
T.check(listed.CHARIZARD or not Data.pokemon.CHARIZARD,
  "FLY learners are listed (CHARIZARD)")
T.check(not listed.BULBASAUR, "grounded species are not (BULBASAUR)")
local total = 0
for _, def in pairs(Data.pokemon) do
  if type(def) == "table" and type(def.dex) == "number" then
    total = total + 1
  end
end
T.check(#screen.list > 0 and #screen.list < total,
  "the dex is a strict subset of the species table")

pressed.down = true
screen:update(1 / 60)
pressed.down = nil
T.eq(screen.index, 2, "DOWN pages to the next species")

pressed.up = true
screen:update(1 / 60)
pressed.up = nil
T.eq(screen.index, 1, "UP pages back")

pressed.up = true
screen:update(1 / 60)
pressed.up = nil
T.check(screen.index > 1, "UP from the first species wraps to the end")

pressed.b = true
screen:update(1 / 60)
pressed.b = nil
T.check(popped, "B closes the dex")

-- the Gen1 Modern UI surface contract: v2, one surface matching the
-- dex screen by id, with a data-only model the presenter can copy
local contract = api.gen1ModernUi
T.check(type(contract) == "table", "gen1ModernUi contract published")
T.eq(contract.apiVersion, 2, "surface contract is apiVersion 2")
local surface = contract.surfaces and contract.surfaces.WildSkiesSkyDex
T.check(type(surface) == "table", "WildSkiesSkyDex surface declared")
T.check(type(surface.match) == "function"
  and type(surface.model) == "function"
  and type(surface.render) == "function",
  "surface has match, model, and render")
T.eq(surface.native.policy, "replace", "surface replaces the native draw")
T.check(surface.match(screen), "the surface matches the dex screen")
T.check(not surface.match({ screenId = "PokedexMenu" }),
  "and nothing else")
local model = surface.model(nil, screen)
T.check(type(model.rows) == "table" and #model.rows > 0,
  "model carries the species rows")
T.eq(model.selected, screen.index, "model tracks the cursor")
T.check(model.rows[1].label:match("^%d%d%d "),
  "rows read dex-number first, Pokedex style")
surface.actions.jump(nil, screen, { index = 3 })
T.eq(screen.index, 3, "the jump action moves the cursor")

run.release()
T.finish("wild_skies_skydex")

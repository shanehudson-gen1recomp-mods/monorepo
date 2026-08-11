-- skylib's generation-agnostic data reads against both encounter
-- shapes: Gen 1's map-first records and Gold's kind-first, per-period
-- tables, plus the view-size and badge-count fallbacks.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local MOD_DIR = os.getenv("MOD_DIR") or "mods/wild_skies"
local Sky = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()

local gen1 = { encounters = {
  ROUTE_1 = { grass = { rate = 25, slots = {
    { species = "PIDGEY", level = 3 },
    { species = "RATTATA", level = 3 },
  } } },
  ROUTE_21 = { water = { rate = 5, slots = {
    { species = "TENTACOOL", level = 10 },
  } } },
} }

local gold = { encounters = {
  grass = { ROUTE_29 = {
    rates = { MORN = 25, DAY = 25, NITE = 25 },
    slots = {
      MORN = { { species = "PIDGEY", level = 2 } },
      DAY  = { { species = "PIDGEY", level = 3 } },
      NITE = { { species = "HOOTHOOT", level = 2 },
               { species = "RATTATA", level = 3 } },
    },
  } },
  water = { ROUTE_41 = { rate = 5, slots = {
    { species = "TENTACOOL", level = 15 },
  } } },
} }

-- shape probe
T.check(not Sky.gen2Encounters(gen1.encounters), "gen 1 shape probed")
T.check(Sky.gen2Encounters(gold.encounters), "gold shape probed")
T.check(not Sky.gen2Encounters(nil), "nil data is not gold")

-- grass slots across shapes and periods
T.eq(#Sky.grassSlots(gen1, "ROUTE_1"), 2, "gen 1 grass slots read")
T.eq(Sky.grassSlots(gold, "ROUTE_29", "NITE")[1].species, "HOOTHOOT",
     "gold night slots read")
T.eq(Sky.grassSlots(gold, "ROUTE_29")[1].level, 3,
     "no tod falls back to DAY")
T.eq(#Sky.grassSlots(gold, "ROUTE_1"), 0, "unknown map is empty")

-- wild rows: one per (map, terrain, period)
T.eq(#Sky.wildRows(gen1), 2, "gen 1 rows: one per map terrain")
T.eq(#Sky.wildRows(gold), 4, "gold rows: three periods plus water")
local sawNite = false
for _, row in ipairs(Sky.wildRows(gold)) do
  if row.period == "NITE" then sawNite = true end
end
T.check(sawNite, "gold rows carry their period")

-- map wildlife presence and the open-sea signature
T.check(Sky.mapWild(gen1, "ROUTE_1").grass, "gen 1 grass presence")
T.check(Sky.mapWild(gen1, "ROUTE_21").water
        and not Sky.mapWild(gen1, "ROUTE_21").grass,
        "gen 1 sea signature")
T.check(Sky.mapWild(gold, "ROUTE_41").water
        and not Sky.mapWild(gold, "ROUTE_41").grass,
        "gold sea signature")
T.eq(Sky.mapWild(gold, "NOWHERE"), nil, "no tables means nil")

-- slot levels follow the local curve
local lv = Sky.slotLevels(gold, "ROUTE_29", "NITE")
T.eq(#lv, 2, "gold night levels collected")
T.eq(#Sky.slotLevels(gen1, "ROUTE_21"), 1, "gen 1 water levels collected")

-- view size: Gold's world fields first, then the Gen 1 renderer,
-- then the GB screen
local w, h = Sky.viewSize(nil, { viewW = 176, viewH = 160 })
T.eq(w, 176, "gold viewW wins")
w, h = Sky.viewSize({}, { stepBody = function() end })
T.eq(w, 160, "gold world before first frame is GB-sized")
w, h = Sky.viewSize({ renderer = {
  worldViewSize = function() return 320, 288 end } }, nil)
T.eq(w, 320, "gen 1 renderer consulted")
w, h = Sky.viewSize(nil, nil)
T.eq(h, 144, "bare fallback is the GB screen")

-- gold world probe
T.check(Sky.goldWorld({ stepBody = function() end }), "world probed by stepBody")
T.check(not Sky.goldWorld({}), "gen 1 overworld is not gold")

-- mount sprites on gold-shaped data: the species' own icon outranks
-- the generic Gen 1 walker sheets and wears the species' colours
package.loaded["src.render.SpriteRenderer"] = {
  new = function(def, seed)
    return { def = def, seed = seed,
             setObjPalette = function(self, colors, group)
               self.colors, self.group = colors, group
             end }
  end,
}
package.loaded["src.world.gen2.Palettes"] = {
  monColors = function(palettes, species)
    T.eq(palettes.tag, "gold-palettes", "palette table passed through")
    return { "w", species, species, "b" }
  end,
}
local goldData = {
  encounters = gold.encounters,
  pokemon = { HOOTHOOT = { icon = "BIRD" } },
  icons = {},
  sprites = { SPRITE_BIRD = { image = "gen1_bird.png", frames = 6 } },
  gen2Icons = { species = { HOOTHOOT = 21 },
                icons = { [21] = { image = "icons/owl.png" } } },
  gen2Palettes = { tag = "gold-palettes" },
}
local owl = Sky.mountSprite(goldData, "HOOTHOOT", "t2")
T.eq(owl.def.image, "icons/owl.png",
     "gold prefers the species icon over the generic sheet")
T.eq(owl.def.species, "HOOTHOOT", "icon def carries its species")
T.eq(owl.colors and owl.colors[2], "HOOTHOOT",
     "the species' shipped colours are baked in")
T.check(Sky.mountSprite(goldData, "HOOTHOOT", "t2") == owl,
        "gold icon renderer cached per species")
local gen1Bird = Sky.mountSprite({
  encounters = gen1.encounters,
  pokemon = { PIDGEY = { icon = "BIRD" } }, icons = {},
  sprites = { SPRITE_BIRD = { image = "gen1_bird.png", frames = 6 } },
}, "PIDGEY", "t3")
T.eq(gen1Bird.def.image, "gen1_bird.png",
     "gen 1 data keeps the walker sheets")
package.loaded["src.render.SpriteRenderer"] = nil
package.loaded["src.world.gen2.Palettes"] = nil

-- badge count: Gold's flag set wins, Gen 1 falls to the Badges module
T.eq(Sky.badgeCount(nil, { player = { badges =
  { ZEPHYRBADGE = true, HIVEBADGE = true, PLAINBADGE = false } } }), 2,
  "gold badges counted")
package.loaded["src.inventory.Badges"] = {
  count = function() return 3 end,
}
T.eq(Sky.badgeCount({}, {}), 3, "gen 1 badges counted")
package.loaded["src.inventory.Badges"] = nil

T.finish("skylib_gen2_shapes")

-- Derived skies: the ambient pools grow from whatever the world's own
-- encounter tables host, so a dataset overhaul (Crystal 251, or any
-- future generation) feeds the sky without wild_skies naming a single
-- new species.  WATER/FLYING species patrol the sea, species a
-- period-aware ecology export marks nocturnal own the night, and the
-- rest ride the day pool at the levels the world itself deals them.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

-- the overhaul's footprint, shaped the way CRYSTAL_251 leaves it: new
-- species registered into the merged data...
local GEN2 = {
  HOOTHOOT = { dex = 163, types = { "NORMAL", "FLYING" } },
  MANTINE  = { dex = 226, types = { "WATER", "FLYING" } },
  SKARMORY = { dex = 227, types = { "STEEL", "FLYING" } },
  XATU     = { dex = 178, types = { "PSYCHIC", "FLYING" } },
}
local function installGen2()
  for id, def in pairs(GEN2) do Data.pokemon[id] = def end
end
local function removeGen2()
  for id in pairs(GEN2) do Data.pokemon[id] = nil end
end

-- ...and placed into wild slots (a sea route's water and a road's
-- grass).  SEA_TEST has water and no grass, so its sky is ambient.
Data.encounters = Data.encounters or {}
Data.encounters.SEA_TEST = {
  water = { rate = 10, slots = {
    { species = "TENTACOOL", level = 20 },
    { species = "MANTINE", level = 22 },
  } },
}
Data.encounters.SEA_TEST2 = Data.encounters.SEA_TEST
Data.encounters.GEN2_ROAD = {
  grass = { rate = 25, slots = {
    { species = "SKARMORY", level = 25 },
    { species = "XATU", level = 24 },
  } },
}

local ow = {
  entities = {},
  camera = { x = 0, y = 0 },
  player = { cellX = 15, cellY = 15, px = 240, py = 240 },
  tod = "DAY",
  map = {
    id = "SEA_TEST",
    def = { tileset = "OVERWORLD" },
    widthCells = 30, heightCells = 30,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 30 and y < 30
    end,
    isWalkableCell = function() return true end,
  },
}
-- a period-aware ecology export in Crystal 251's shape: Xatu appears
-- only in a night table, Skarmory flies a day one.  Note Xatu is NOT
-- in wild_skies' hand list of nocturnal species; only this export can
-- teach it.
local fakeEcology = {
  list = function()
    return {
      { mapId = "GEN2_ROAD", terrain = "grass", period = "day",
        group = { slots = { { species = "SKARMORY", level = 25 } } } },
      { mapId = "GEN2_ROAD", terrain = "grass", period = "night",
        group = { slots = { { species = "XATU", level = 24 },
                            { species = "SKARMORY", level = 25 } } } },
    }
  end,
}
local Game = {
  data = Data,
  overworld = ow,
  renderer = { worldViewSize = function() return 160, 144 end },
  mods = { exports = {} },
}
package.loaded["src.core.Game"] = Game
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local OC = {}
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = { field = function() return {} end }
run.loader.events:emit("game.ready")
T.check(OC.__wildSkiesTick ~= nil, "ambient spawner armed")

-- deterministic random: the 1000-sided ultra roll always misses; the
-- first single-argument roll of a tick is the pool pick and takes
-- pickIndex (clamped to the pool, consumed once); later single rolls
-- take 1, ranged rolls their low end, bare rolls stay high to skip
-- the flock branches
local pickIndex = nil
local origRandom = love.math.random
love.math.random = function(a, b)
  if a and b then return a end
  if a then
    if a == 1000 then return 2 end
    if pickIndex then
      local v = math.min(pickIndex, a)
      pickIndex = nil
      return v
    end
    return 1
  end
  return 0.9
end

local function freshSky(mapId, tod)
  run.loader.events:emit("map.exited")
  ow.entities = {}
  ow.map.id = mapId or ow.map.id
  ow.tod = tod or "DAY"
end

-- walk the whole pool by index and collect which species this air can
-- host; the picks cache holds per map + time of day, so the pool is
-- stable across the sweep
local function skyHosts(mapId, tod)
  local hosts = {}
  for i = 1, 60 do
    freshSky(mapId, tod)
    pickIndex = i
    OC.__wildSkiesTick(ow, 5)
    local bird = ow.entities[1]
    if bird then hosts[bird.species] = bird end
  end
  return hosts
end

-- vanilla dex: no Gen 2 species exists, so no pool can host one
local hosts = skyHosts("SEA_TEST", "DAY")
T.check(hosts.PIDGEOT and hosts.FEAROW, "the vanilla sea pool flies")
T.eq(hosts.MANTINE, nil, "no Mantine before the overhaul")
T.eq(hosts.TENTACOOL, nil, "non-FLYING water species stay in the water")

-- the overhaul arrives: species + slots + ecology, no new hand lists
installGen2()
Game.mods.exports.CRYSTAL_251 = { ecology = fakeEcology, dexSize = 251 }

hosts = skyHosts("SEA_TEST2", "DAY")
T.check(hosts.MANTINE ~= nil, "Mantine skims the waves it swims in")
if hosts.MANTINE then
  T.check(hosts.MANTINE.level >= 20 and hosts.MANTINE.level <= 22,
    "at the band its own slots deal")
end
T.eq(hosts.SKARMORY, nil, "a land bird does not join the sea pool")
T.eq(hosts.XATU, nil, "the ecology's night species sits out the day")

-- a town's day air hosts the overhaul's land birds
hosts = skyHosts("PALLET_TOWN", "DAY")
T.check(hosts.SKARMORY ~= nil, "Skarmory patrols the town by day")
T.eq(hosts.XATU, nil, "but Xatu only flies at night")

-- and the night sky belongs to what the ecology marks nocturnal
hosts = skyHosts("PALLET_TOWN", "NITE")
T.check(hosts.XATU ~= nil, "Xatu joins the night air")
T.eq(hosts.SKARMORY, nil, "while the day birds roost")

-- encounter-fed skies follow the hand fallback too: a Hoothoot grass
-- slot (Crystal's combined tables list it beside the day species)
-- flies only the night sky
Data.encounters.ROUTE_1 = Data.encounters.ROUTE_1 or {}
local savedRoute1 = Data.encounters.ROUTE_1.grass
Data.encounters.ROUTE_1.grass = { rate = 25, slots = {
  { species = "PIDGEY", level = 4 },
  { species = "HOOTHOOT", level = 4 },
} }

freshSky("ROUTE_1", "DAY")
pickIndex = 2  -- the day list holds only Pidgey, the index clamps to it
OC.__wildSkiesTick(ow, 5)
T.eq(ow.entities[1] and ow.entities[1].species, "PIDGEY",
  "Hoothoot sits out the daylight")

freshSky("ROUTE_1", "NITE")
pickIndex = 1
OC.__wildSkiesTick(ow, 5)
T.eq(ow.entities[1] and ow.entities[1].species, "HOOTHOOT",
  "and owns the night")

Data.encounters.ROUTE_1.grass = savedRoute1
Data.encounters.SEA_TEST = nil
Data.encounters.SEA_TEST2 = nil
Data.encounters.GEN2_ROAD = nil
removeGen2()
love.math.random = origRandom
run.release()
T.finish("wild_skies_crystal")

-- Gold resident skies: a connection crossing swaps per-map flocks
-- instead of clearing (Gold has no mod-facing ghost surface, so the
-- neighbor flocks tick against a translated stand-in world), and a
-- full transition still refreshes the sky.  "Gold" here is the Gen 2
-- engine itself; the ow stand-in carries stepBody, the probe the
-- adapter uses, and id-keyed neighbors the way Gold's world does.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local function mkdef(w, h)
  return { width = w, height = h, tileset = "OVERWORLD",
           environment = 1 }
end
local function mkmap(id, def)
  local w, h = def.width * 2, def.height * 2
  return {
    id = id, def = def, widthCells = w, heightCells = h,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < w and y < h
    end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
  }
end

local defs = { ROUTE_1 = mkdef(15, 15), ROUTE_2 = mkdef(15, 15) }
local ow = {
  stepBody = function() end, -- what marks a world as Gold's
  drawPeople = function() end,
  maps = defs,
  entities = {}, npcs = {}, ghosts = {},
  neighbors = { { id = "ROUTE_2", ox = 480, oy = 0 } },
  camera = { x = 0, y = 0 }, tod = "DAY", viewW = 160, viewH = 144,
  player = { cellX = 15, cellY = 15, px = 240, py = 240 },
  map = mkmap("ROUTE_1", defs.ROUTE_1),
}
local Game = {
  data = Data, overworld = ow, world = ow, save = { party = {} },
  mods = { exports = {} },
  input = { isDown = function() return false end,
            wasPressed = function() return false end },
}
package.loaded["src.core.Game"] = Game
local OC = { update = function() end, draw = function() end }
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = {
  isOutside = function() return true end,
  defIsWalkableCell = function() return true end,
  defIsWaterCell = function() return false end,
}
package.loaded["src.world.FieldDefaults"] = {
  field = function() return {} end,
}

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
                          { data = Data })
T.eq(#run.errors, 0, "loads cleanly")
run.loader.events:emit("game.ready")
local api = run.loader.exports.wild_skies

local id = api.spawnFlyer("PIDGEY", 7)
T.check(id ~= nil, "a bird takes the ROUTE_1 sky")
for _ = 1, 90 do OC.__wildSkiesTick(ow, 1 / 60) end
local seen = api.flyerAt(15, 15, 99)
T.check(seen ~= nil and seen.species == "PIDGEY", "the bird reads back")
T.eq(#ow.entities, 0, "Gold flyers stay out of the entity list")

-- crossing a seam holds the flock for the swap on map.entered
run.loader.events:emit("map.exited", { mapId = "ROUTE_1" })
T.check(api.flyerAt(15, 15, 99) ~= nil,
        "a Gold seam exit does not clear the sky")
ow.map = mkmap("ROUTE_2", defs.ROUTE_2)
ow.neighbors = { { id = "ROUTE_1", ox = -480, oy = 0 } }
run.loader.events:emit("map.entered",
                       { mapId = "ROUTE_2", via = "connection" })

-- cross straight back: the parked ROUTE_1 flock is live again with
-- the same bird in it
run.loader.events:emit("map.exited", { mapId = "ROUTE_2" })
ow.map = mkmap("ROUTE_1", defs.ROUTE_1)
ow.neighbors = { { id = "ROUTE_2", ox = 480, oy = 0 } }
run.loader.events:emit("map.entered",
                       { mapId = "ROUTE_1", via = "connection" })
local back = api.flyerAt(15, 15, 99)
T.check(back ~= nil and back.species == "PIDGEY",
        "crossing back finds the same resident flock")
T.eq(back and back.id, id, "and it is the very same bird")

-- a door is a full transition and refreshes the sky
run.loader.events:emit("map.exited", { mapId = "ROUTE_1" })
run.loader.events:emit("map.entered",
                       { mapId = "PLAYERS_HOUSE_1F", via = "warp" })
T.eq(api.flyerAt(15, 15, 99), nil, "a full transition clears the sky")

run.release()
T.finish("wild_skies_gold_seam")

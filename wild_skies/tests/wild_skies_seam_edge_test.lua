-- Map edges are not cliffs: with seamless connections the neighbor
-- strip is rendered, so a bird crossing the boundary must keep flying
-- and despawn only once outside the camera view (plus margin), or
-- after a long out-of-bounds safety timeout.  Out-of-bounds birds are
-- invisible to every battle seam meanwhile.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local ow = {
  entities = {},
  camera = { x = 0, y = 0 },
  player = { cellX = 25, cellY = 25, px = 400, py = 400 },
  map = {
    id = "ROUTE_1",
    widthCells = 30, heightCells = 30,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 30 and y < 30
    end,
    isWalkableCell = function() return true end,
  },
}
package.loaded["src.core.Game"] = {
  data = Data,
  overworld = ow,
  renderer = { worldViewSize = function() return 160, 144 end },
}
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local api = run.loader.exports.wild_skies

local function spawnRoamer()
  for _ = 1, 8 do
    if api.spawnFlyer("PIDGEY", 5) then break end
  end
  local f = ow.entities[#ow.entities]
  T.check(f and f.species == "PIDGEY", "PIDGEY spawned")
  f.mode = "roam"
  f.t = 1
  f.bold = true
  f.alt, f.altTarget = 40, 40
  return f
end

-- past the west edge but inside the camera view: keeps flying
local bird = spawnRoamer()
bird.px, bird.py = -20, 80
bird.cellX, bird.cellY = -1, 5
bird:tick(ow, 0.05)
T.check(not bird.dead, "out of bounds but in view: alive")

-- and invisible to the battle seams while out of bounds
T.eq(api.flyerAt(bird.cellX, bird.cellY, 1), nil,
  "oob bird hidden from flyerAt")
T.eq(api.takeFlyer(bird.cellX, bird.cellY, 1), nil,
  "oob bird hidden from takeFlyer")
T.eq(api.takeFlockmate(bird.cellX, bird.cellY, 3), nil,
  "oob bird hidden from takeFlockmate")

-- the startle path must not kill it either
bird.px, bird.py = -20, 80
bird.cellX, bird.cellY = -1, 5
bird.startleT = 1
ow.player.cellX, ow.player.cellY = 0, 5
ow.player.px, ow.player.py = 0, 80
bird:tick(ow, 0.05)
T.check(not bird.dead, "startled out of bounds but in view: alive")
ow.player.cellX, ow.player.cellY = 25, 25
ow.player.px, ow.player.py = 400, 400
bird.startleT = nil

-- far outside the view margin: gone
bird.px, bird.py = -120, 80
bird.cellX, bird.cellY = -8, 5
bird:tick(ow, 0.05)
T.check(bird.dead, "outside view + margin: despawns")

-- the safety timeout catches an oob bird the view never releases
local lingerer = spawnRoamer()
lingerer.px, lingerer.py = -20, 80
lingerer.cellX, lingerer.cellY = -1, 5
lingerer.oobT = 25
lingerer:tick(ow, 0.05)
T.check(lingerer.dead, "out of bounds for too long: safety despawn")

run.release()
T.finish("wild_skies_seam_edge")

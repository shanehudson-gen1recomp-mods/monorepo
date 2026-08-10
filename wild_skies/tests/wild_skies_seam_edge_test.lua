-- Map edges are not cliffs: with seamless connections the neighbor
-- strip is rendered, so a bird crossing the boundary must keep flying
-- and despawn only once outside the camera view (plus margin), or
-- after a long out-of-bounds safety timeout.  Out-of-bounds birds are
-- invisible to every battle seam meanwhile.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local OC = {}
OC.update = function() end
OC.draw = function() end
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = {
  field = function() return {} end }

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
Data.sprites.SPRITE_COOLTRAINER_M = Data.sprites.SPRITE_COOLTRAINER_M
  or { image = "fixture_trainer.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")
run.loader.events:emit("game.ready")

local api = run.loader.exports.wild_skies
local dbg = api.__skyTrainerDebug

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

-- ------- trainers ride the seam carry, map exits and toggle-off

-- the seam carry translates trainers (and riders) like flyers and
-- re-attaches them to the rebuilt entity list
local tr = dbg.spawn(1)
T.check(tr ~= nil, "trainer spawned for the carry")
tr.px, tr.py = 160, 160
tr.cellX, tr.cellY = 10, 10
tr.mode = "commute"
local crossed = OC.__wildSkiesCarry(ow, "down", {},
  function(self, dir, conn)
    self.player.px = self.player.px - 320
    self.player.py = self.player.py - 320
    self.entities = { self.player }
    return true
  end)
T.eq(crossed, true, "the crossing itself succeeded")
T.eq(tr.px, 160 - 320, "trainer rebased with the player")
local attached, riderAttached = false, false
for _, e in ipairs(ow.entities) do
  if e == tr then attached = true end
  if e == tr.rider then riderAttached = true end
end
T.check(attached, "trainer re-attached after the seam")
T.check(riderAttached, "rider re-attached after the seam")

-- the seam's own map.exited must NOT clear what the carry kept
run.loader.events:emit("map.exited", {})
T.eq(#dbg.list(), 1, "the carried trainer survives the seam's map swap")

-- but a real exit (a door, a cave) clears trainers with the birds
run.loader.events:emit("map.exited", {})
T.eq(#dbg.list(), 0, "a real map exit clears the trainers")
for _, e in ipairs(ow.entities) do
  T.check(e ~= tr and e ~= tr.rider, "no trainer entity survives the exit")
end

-- toggling SKY TRAINERS off flies the live ones out
local tr2 = dbg.spawn(1)
tr2.mode = "commute"
run.loader.events:emit("mod.options_changed",
  { mod = "wild_skies", key = "trainers", value = false })
T.eq(tr2.mode, "leave", "live trainer leaves on toggle-off")

-- and an engaged one releases the freeze before it goes
local tr3 = dbg.spawn(1)
tr3.mode = "await"
ow.engaging = true
ow.emote = { npc = tr3, frames = 60, onDone = function() end }
run.loader.events:emit("mod.options_changed",
  { mod = "wild_skies", key = "trainers", value = false })
T.eq(ow.engaging, false, "toggle-off releases a held engage")
T.eq(ow.emote, nil, "and clears our bubble")
T.eq(tr3.mode, "leave", "the engaged trainer leaves too")

run.release()
T.finish("wild_skies_seam_edge")

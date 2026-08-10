-- Generic normalized SKY provider: bounded snapshots, replica/authority
-- handoff, canonical claims, resident neighbors, and clean solo fallback.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local function map(id)
  return {
    id = id, def = { tileset = "OVERWORLD" },
    widthCells = 30, heightCells = 30,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 30 and y < 30
    end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
  }
end

local sourceMap, neighborMap = map("ROUTE_1"), map("ROUTE_2")
local ow = {
  isOverworld = true,
  entities = {}, npcs = {}, ghosts = {},
  camera = { x = 0, y = 0 }, tod = "DAY",
  player = { cellX = 15, cellY = 15, px = 240, py = 240 },
  runner = { isRunning = function() return false end,
    run = function(self, rows) self.rows = rows end },
  map = sourceMap,
  neighbors = { { map = neighborMap, ox = 480, oy = 0 } },
}
local Game = {
  data = Data, overworld = ow, save = { party = {} },
  renderer = { worldViewSize = function() return 160, 144 end },
  input = { isDown = function() return false end,
    wasPressed = function() return false end },
  mods = { exports = {} },
}
package.loaded["src.core.Game"] = Game
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local emitMapExit = function() end
local OC = { update = function() end, draw = function() end,
  crossConnection = function(self, _, conn)
    emitMapExit()
    self.map = conn.map
    self.neighbors = conn.neighbors or {}
    self.entities = {}
    return true
  end }
package.loaded["src.world.OverworldController"] = OC
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = { field = function() return {} end }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.eq(#run.errors, 0, "loads cleanly")
emitMapExit = function()
  run.loader.events:emit("map.exited", { mapId = ow.map and ow.map.id })
end
run.loader.events:emit("game.ready")
local api = run.loader.exports.wild_skies

T.check(not api.applySharedSkyFieldSnapshot({ domain = "SKY",
  map = "ROUTE_1", revision = 0, localAuthority = false, spawns = {} }),
  "snapshots require an explicitly registered provider")

local claims = {}
local provider = {
  requestClaim = function(mapId, id, context)
    claims[#claims + 1] = { map = mapId, id = id, context = context }
    return true
  end,
}
T.check(not api.registerSharedSkyProvider("bad", {}),
  "provider registration requires a claim seam")
T.check(api.registerSharedSkyProvider("fixture", provider),
  "a generic provider registers without an MMO dependency")

local id
for _ = 1, 8 do
  id = api.spawnFlyer("PIDGEY", 7)
  if id then break end
end
T.check(id ~= nil, "fixture flyer spawned")
local f = ow.entities[#ow.entities]
f.px, f.py, f.alt, f.cellX, f.cellY = 160, 96, 56, 10, 6
f.facing, f.mode, f.bold, f.t = "left", "roam", true, 1
f.vx, f.vy = -32, 4

local snap = api.sharedSkyFieldSnapshot("ROUTE_1")
T.eq(snap.domain, "SKY", "snapshot names its normalized domain")
T.eq(snap.spawns[1].id, id, "stable flyer id exported")
T.eq(snap.spawns[1].alt, 56, "altitude exported")
T.eq(snap.spawns[1].vx, -32, "horizontal velocity exported")
T.eq(snap.spawns[1].vy, 4, "vertical velocity exported")

T.check(not api.applySharedSkyFieldSnapshot({}),
  "malformed snapshots are rejected")
local duplicate = { domain = "SKY", map = "ROUTE_1", revision = 1,
  localAuthority = false, spawns = {
    { id = "same", species = "PIDGEY", x = 1, y = 1, alt = 32 },
    { id = "same", species = "PIDGEY", x = 2, y = 2, alt = 32 },
  } }
T.check(not api.applySharedSkyFieldSnapshot(duplicate),
  "duplicate canonical ids are rejected")

snap.revision, snap.localAuthority = 1, true
T.check(api.applySharedSkyFieldSnapshot(snap),
  "authority echo enables shared mode")
local staleRevision = { domain = "SKY", map = "ROUTE_1", revision = 0,
  localAuthority = false, spawns = snap.spawns }
T.check(not api.applySharedSkyFieldSnapshot(staleRevision),
  "stale per-map revisions are rejected")
T.eq(api.takeFlyer(10, 6, 1), nil,
  "shared contact waits for provider permission")
T.eq(#claims, 1, "the exact stable flyer is claimed once")
T.eq(claims[1].map, "ROUTE_1", "claim carries its map")
T.eq(claims[1].id, id, "claim carries its stable id")
T.eq(claims[1].context.domain, "SKY", "claim is domain-labeled")
T.eq(api.takeFlyer(10, 6, 1), nil, "duplicate contact stays pending")
T.eq(#claims, 1, "pending contact cannot emit twice")
T.check(api.denySharedSkyFieldContact("ROUTE_1", id),
  "provider denial releases the pending claim")
T.eq(#ow.entities, 1, "denial preserves the canonical flyer")

snap.localAuthority = false
snap.spawns[1].x, snap.spawns[1].y = 176, 112
T.check(api.applySharedSkyFieldSnapshot(snap),
  "replica accepts canonical movement")
T.eq(api.spawnFlyer("SPEAROW", 8), nil,
  "a replica cannot add a private flyer")
T.eq(api.summonFlyer(10, 6, { radius = 8 }), nil,
  "a replica cannot summon from the canonical field")
T.eq(api.takeFlockmate(10, 6, 8), nil,
  "a replica cannot consume a canonical flockmate")
local replica = ow.entities[1]
replica.px, replica.py = replica.sharedX, replica.sharedY
local startX = replica.px
OC.__wildSkiesTick(ow, 1 / 60)
T.check(replica.px < startX,
  "replica predicts continuously from canonical velocity")
T.eq(replica.facing, "left", "replica facing follows its velocity")

local stale = { wildSkiesFlyer = true, id = replica.id }
ow.entities = { stale }
OC.__wildSkiesTick(ow, 1 / 60)
T.eq(#ow.entities, 1, "post-battle identity reconciliation keeps one flyer")
T.check(ow.entities[1] == replica,
  "post-battle identity reconciliation restores the live replica")

snap.localAuthority = true
T.check(api.applySharedSkyFieldSnapshot(snap),
  "a replica can inherit authority")
T.check(replica.sharedReplica == false,
  "authority inheritance promotes a complete flyer")
T.check(type(replica.speed) == "number" and replica.speed > 0,
  "promoted authority has a valid flight speed")
replica.px, replica.py, replica.cellX, replica.cellY = 160, 96, 10, 6
replica.bold, replica.t = true, 1
T.eq(api.takeFlyer(10, 6, 1), nil,
  "authority contact still waits for the provider's atomic claim")
T.eq(#claims, 2, "a new authority contact requests one new claim")
T.check(api.grantSharedSkyFieldContact("ROUTE_1", id),
  "a granted canonical contact starts its encounter")
T.eq(#ow.entities, 0, "the granted flyer leaves the current field once")

local neighborIds = api.sharedSkyNeighborMaps()
T.eq(neighborIds[1], "ROUTE_2", "resident neighbor map is discoverable")
local neighborSnap = api.sharedSkyFieldSnapshot("ROUTE_2")
T.check(neighborSnap and #neighborSnap.spawns > 0,
  "a provider can seed a bounded resident-neighbor sky")
neighborSnap.revision, neighborSnap.localAuthority = 1, false
T.check(api.applySharedSkyFieldSnapshot(neighborSnap),
  "off-screen canonical snapshots are accepted")
T.eq(#ow.ghosts, #neighborSnap.spawns,
  "canonical neighbor flyers project on the engine ghost surface")
T.check(ow.ghosts[1].wildSkiesResidentGhost == true,
  "shared neighbors reuse the renderer-neutral resident surface")
local neighborGhost = ow.ghosts[1].npc
neighborGhost:update()
local entryX, entryY = neighborGhost.px, neighborGhost.py
T.check(OC.crossConnection(ow, "north", { map = neighborMap,
  neighbors = { { map = sourceMap, ox = -480, oy = 0 } } }),
  "a shared player crosses into the resident canonical neighbor")
local entered
for _, entity in ipairs(ow.entities) do
  if entity.id == neighborSnap.spawns[1].id then entered = entity; break end
end
T.check(entered ~= nil, "the shared resident ghost becomes a live replica")
T.eq(entered.px, entryX, "ghost-to-replica handoff preserves displayed x")
T.eq(entered.py, entryY, "ghost-to-replica handoff preserves displayed y")
neighborSnap.localAuthority = true
T.check(api.applySharedSkyFieldSnapshot(neighborSnap),
  "the entrant can inherit authority at the same canonical revision")
T.eq(entered.px, entryX, "replica-to-authority handoff does not rewind x")
T.eq(entered.py, entryY, "replica-to-authority handoff does not rewind y")
T.check(entered.sharedReplica == false,
  "the seam entrant becomes a complete authoritative flyer")

run.loader.events:emit("map.exited", { mapId = "ROUTE_2" })
ow.map, ow.neighbors, ow.entities = neighborMap, {}, {}
run.loader.events:emit("map.entered", { mapId = "ROUTE_2" })
local restored
for _, entity in ipairs(ow.entities) do
  if entity.id == neighborSnap.spawns[1].id then restored = entity; break end
end
T.check(restored ~= nil,
  "a hard transition restores a cached canonical destination immediately")
T.check(restored.sharedReplica == false,
  "cached hard-transition state retains its authority role")

T.check(api.clearSharedSkyField(), "shared state clears cleanly")
T.eq(#ow.entities, 0, "shared flyers do not leak into solo play")
T.eq(#ow.ghosts, 0, "shared neighbor ghosts do not leak into solo play")
T.check(api.unregisterSharedSkyProvider("fixture"),
  "the generic provider unregisters by identity")
T.check(not api.unregisterSharedSkyProvider("fixture"),
  "provider unregister is idempotently guarded")

run.release()
T.finish("wild_skies_shared_provider")

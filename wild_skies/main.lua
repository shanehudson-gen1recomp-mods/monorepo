-- Wild Skies: flying Pokémon roam the overworld sky.  Species come
-- from the map's own grass slots; outdoor maps with no flying slots (the
-- sea routes) get a sparse ambient pool instead, so the ocean sky is not
-- empty.  Birds wander in all three dimensions on capped-turn headings
-- with gentle same-species flocking, share the player's flight band,
-- rest on streets and rooftops, and fly off the nearest edge when their
-- visit is over.
--
-- Flyers are lightweight entities inserted into the overworld's entity
-- list (drawn in the world pass, `passable` so they never block anyone)
-- but kept out of the NPC list, so scripts and talk targeting never see
-- them.  All art is the player's own imported cache; nothing ships.
return function(mod)
  -- shared helpers, synced in as lib/shared/ by the monorepo's scripts
  local function loadShared(file)
    local src = mod:read("lib/shared/" .. file)
    if not src then return nil end
    return assert((loadstring or load)(src, "@wild_skies/lib/shared/" .. file))()
  end
  local Sky = loadShared("skylib.lua")
  if not Sky then
    mod.log:error("lib/shared/skylib.lua is missing -- run scripts/dev.sh "
      .. "in the gen1recomp-mods repo to sync shared code; mod disabled")
    return
  end

  mod.options:define({
    { key = "density", label = "SKY DENSITY", type = "choice", default = "med",
      choices = { { "LOW", "low" }, { "MED", "med" }, { "HIGH", "high" } } },
    { key = "size", label = "BIRD SIZE", type = "choice", default = "normal",
      choices = { { "SMALL", "small" }, { "NORMAL", "normal" },
                  { "LARGE", "large" }, { "HUGE", "huge" } } },
    { key = "bumps", label = "GROUND BATTLES", type = "toggle", default = true },
  })

  -- a bird at or below this height can collide with a walking player;
  -- anything cruising higher is safe scenery from the ground
  local LOW_ALT = 12

  local DENSITY = {
    low  = { cap = 3, cooldown = 8 },
    med  = { cap = 6, cooldown = 4 },
    high = { cap = 10, cooldown = 2.5 },
  }
  local function density()
    return DENSITY[mod.options:get("density")] or DENSITY.med
  end

  -- draw-time multiplier on top of the dex-height scale, so the option
  -- applies to birds already in the air the moment it changes
  local SIZE_MULT = { small = 0.7, normal = 1, large = 1.3, huge = 1.6 }
  local function sizeMult()
    return SIZE_MULT[mod.options:get("size")] or 1
  end

  local CLASS_PROFILE = {
    BIRD  = { speed = { 30, 46 }, flap = 8, bob = 2 },
    MON   = { speed = { 22, 34 }, flap = 5, bob = 3 },
    WATER = { speed = { 20, 30 }, flap = 4, bob = 2 },
    FAIRY = { speed = { 24, 36 }, flap = 6, bob = 2 },
  }
  local DEFAULT_PROFILE = CLASS_PROFILE.BIRD

  -- the shared sky band brackets the mount's own cruise heights
  -- (free_fly rides 32/56/80), so birds live in the player's airspace,
  -- some higher, some lower; the odd low pass keeps ground bumps alive
  local SKY_BAND = { 28, 76 }
  local LOW_PASS = 0.12

  -- after any battle born from this sky (a bump or a consumer taking a
  -- bird), the flock keeps its distance for a while: heavy spawns should
  -- decorate the route, not chain fights back to back
  local BATTLE_REST = 25

  local CLIMB = 44            -- px/s vertical on takeoff and landing
  local DRIFT = 22            -- px/s vertical while roaming
  local TURN_MAX = math.rad(85)  -- steering cap per second
  local WANDER = math.rad(150)   -- heading jitter scale
  local FLUSH_CELLS = 2       -- a grounded bird flushes at this distance

  -- crepuscular species only fly the night sky
  local NIGHT_ONLY = { ZUBAT = true, GOLBAT = true }

  -- the sparse pools for outdoor maps whose slots offer no flyers;
  -- repeats weight the roll.  Open water gets its own pool: Pidgeot
  -- skims the waves hunting Magikarp per its own dex entry, and a
  -- forest full of Pidgey over the ocean read wrong
  local AMBIENT_DAY  = { "PIDGEY", "PIDGEY", "PIDGEY", "SPEAROW", "SPEAROW",
                         "PIDGEOTTO", "FEAROW" }
  local AMBIENT_SEA  = { "PIDGEOTTO", "PIDGEOTTO", "PIDGEOT", "SPEAROW",
                         "FEAROW", "FEAROW" }
  local AMBIENT_NITE = { "ZUBAT", "ZUBAT", "ZUBAT", "GOLBAT" }
  -- believable bands for evolved ambient species: the bird's level rolls
  -- off the map's own encounter slots, then these clamp it so a Pidgeot
  -- is never a hatchling and never an outlier (levels ride into battles)
  local AMBIENT_LEVELS = {
    PIDGEOTTO = { 15, 20 }, PIDGEOT = { 25, 32 },
    FEAROW = { 20, 27 }, GOLBAT = { 22, 26 },
  }

  -- once in a thousand spawns, an open outdoor sky hosts a legend
  -- instead.  Only under the open sky (never caves, forest canopy or
  -- peaceful town air, where it could not battle), always bold (a
  -- sighting this rare must be catchable), and never flocked.
  local ULTRA_ODDS = 1000
  local ULTRA_RARES = {
    { species = "ARTICUNO", level = { 48, 52 } },
    { species = "ZAPDOS",   level = { 48, 52 } },
    { species = "MOLTRES",  level = { 48, 52 } },
  }
  local ULTRA_SET = {}
  for _, u in ipairs(ULTRA_RARES) do ULTRA_SET[u.species] = true end

  local flyers = {}
  local battleRest = 0
  local lastBump = nil
  local summonFail -- forward: every summon ends in exactly one event
  local cooldown = 3
  local serial = 0
  local picksCache = { key = nil, picks = nil, ambient = false }

  local function detach(ow, flyer)
    if ow and ow.entities then
      for j = #ow.entities, 1, -1 do
        if ow.entities[j] == flyer then table.remove(ow.entities, j) end
      end
    end
  end

  local function clearAll(ow)
    for i = #flyers, 1, -1 do
      local f = flyers[i]
      if f.summonId and summonFail then summonFail(f, "map changed") end
      detach(ow, f)
      table.remove(flyers, i)
    end
  end

  -- ------- inter-mod API
  -- free_fly (or any mod) can read and consume flyers; this is the
  -- supported seam, so nothing reaches into this mod's internals

  -- newborns are excluded: a flyer must have existed long enough to be
  -- seen before anything may collide with it.  Only BOLD birds answer:
  -- with a heavy sky most flyers are scenery that scatters rather than
  -- battles, or every low pass would drag the player into a fight
  local function flyerNear(cellX, cellY, radius)
    if battleRest > 0 then return nil end
    radius = radius or 1
    for _, f in ipairs(flyers) do
      if not f.dead and f.bold and f.t >= 0.75 and not f.summonId
         and math.abs(f.cellX - cellX) + math.abs(f.cellY - cellY) <= radius then
        return f
      end
    end
  end

  mod.exports.flyerAt = function(cellX, cellY, radius)
    local f = flyerNear(cellX, cellY, radius)
    if f then return { species = f.species, level = f.level } end
  end

  -- sprite packs with in-air art can register a source (shared/README
  -- in the repo documents the shape); this reaches only THIS mod's
  -- bundled resolver, so packs register with each mod they dress
  mod.exports.registerSpriteSource = Sky.registerSpriteSource
  mod.exports.unregisterSpriteSource = Sky.unregisterSpriteSource

  -- consume the flyer: despawns it and hands back its identity, or nil.
  -- Whoever takes it, the mod.wild_skies.flyer_taken event tells every
  -- observer, so trackers need not know each consumer.
  mod.exports.takeFlyer = function(cellX, cellY, radius)
    local f = flyerNear(cellX, cellY, radius)
    if not f then return nil end
    local Game = require("src.core.Game")
    f.dead = true
    detach(Game and Game.overworld, f)
    for i = #flyers, 1, -1 do
      if flyers[i] == f then table.remove(flyers, i) end
    end
    battleRest = BATTLE_REST
    pcall(function()
      mod.events:emit("mod.wild_skies.flyer_taken", {
        species = f.species, level = f.level,
        cellX = f.cellX, cellY = f.cellY,
      })
    end)
    return { species = f.species, level = f.level }
  end

  -- like takeFlyer, but rest-exempt and never a legendary: the partner
  -- slot of a battle ALREADY born from this sky (a bump, an aerial
  -- interception) recruits its flockmate here, when the ordinary
  -- consumers are resting.  The rest exists to stop battles CHAINING,
  -- not to empty the second slot of the one that already started.
  mod.exports.takeFlockmate = function(cellX, cellY, radius)
    radius = radius or 8
    local best, bestD
    for _, f in ipairs(flyers) do
      if not f.dead and f.bold and f.t >= 0.75 and not f.summonId
         and not ULTRA_SET[f.species] then
        local d = math.abs(f.cellX - cellX) + math.abs(f.cellY - cellY)
        if d <= radius and (not bestD or d < bestD) then
          best, bestD = f, d
        end
      end
    end
    if not best then return nil end
    local Game = require("src.core.Game")
    best.dead = true
    detach(Game and Game.overworld, best)
    for i = #flyers, 1, -1 do
      if flyers[i] == best then table.remove(flyers, i) end
    end
    pcall(function()
      mod.events:emit("mod.wild_skies.flyer_taken", {
        species = best.species, level = best.level,
        cellX = best.cellX, cellY = best.cellY,
      })
    end)
    return { species = best.species, level = best.level }
  end

  -- call a bird down: the nearest bold flyer within radius breaks off,
  -- flies hard to the cell, and is consumed on arrival with the
  -- mod.wild_skies.flyer_summoned event ({summonId, species, level,
  -- cellX, cellY}).  Every other ending (too slow, map change, lost)
  -- emits mod.wild_skies.summon_failed ({summonId, reason}) instead, so
  -- a caller deferring work on the summon always hears back exactly
  -- once.  Returns the summonId, or nil and a reason.
  local summonSerial = 0
  mod.exports.summonFlyer = function(cellX, cellY, opts)
    opts = opts or {}
    if battleRest > 0 then return nil, "resting" end
    local radius = opts.radius or 8
    local best, bestD
    for _, f in ipairs(flyers) do
      if not f.dead and f.bold and f.t >= 0.75 and not f.summonId then
        local d = math.abs(f.cellX - cellX) + math.abs(f.cellY - cellY)
        if d <= radius and (not bestD or d < bestD) then
          best, bestD = f, d
        end
      end
    end
    if not best then return nil, "nobody near" end
    summonSerial = summonSerial + 1
    local id = "summon_" .. summonSerial
    best.summonId = id
    best.mode = "summon"
    best.summonX, best.summonY = cellX * 16, cellY * 16
    best.summonBy = best.t + 4
    best.altTarget = 10
    return id
  end

  summonFail = function(f, reason)
    local sid = f.summonId
    if not sid then return end
    f.summonId = nil
    if f.mode == "summon" then f.mode = "roam" end
    pcall(function()
      mod.events:emit("mod.wild_skies.summon_failed",
                      { summonId = sid, reason = reason })
    end)
  end

  -- a classic step encounter that rolls a species with a lookalike near
  -- the player IS that bird as far as anyone can tell, so the roll
  -- consumes it: the bird carries its own level into the battle, and a
  -- defeat or capture never leaves it perched there or flying off.  A
  -- grounded or landing bird outranks a flying one, being the one the
  -- player is actually stood next to.
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    local enc = next(encDef, ctx)
    if enc and enc.species then
      local Game = require("src.core.Game")
      local ow = Game and Game.overworld
      local p = ow and ow.player
      if p then
        local pick, pickIndex
        for i, f in ipairs(flyers) do
          if not f.dead and not f.summonId and f.species == enc.species
             and math.abs(f.cellX - p.cellX)
               + math.abs(f.cellY - p.cellY) <= 2 then
            if f.mode == "ground" or f.mode == "toLand" then
              pick, pickIndex = f, i
              break
            end
            if not pick then pick, pickIndex = f, i end
          end
        end
        if pick then
          enc.level = pick.level or enc.level
          pick.dead = true
          detach(ow, pick)
          table.remove(flyers, pickIndex)
        end
      end
    end
    return enc
  end)

  -- free_fly's exported flight state when it is around, else the raw
  -- field it stamps on the player
  local function playerAirborne(p)
    local ff = mod.find("free_fly")
    local api = ff and ff.exports and ff.exports.isFlying
    if api then
      local ok, v = pcall(api)
      if ok then return v == true end
    end
    return p ~= nil and p.freeFlying == true
  end

  -- the map's grass slots filtered to FLYING types and the time of day;
  -- night-only species own the night sky and sit out the daylight
  local function flyingSlots(game, mapId, tod)
    local all, night = {}, {}
    for _, slot in ipairs(Sky.grassSlots(game.data, mapId)) do
      if Sky.hasType(game.data, slot.species, "FLYING") then
        local pick = { species = slot.species, level = slot.level }
        if NIGHT_ONLY[slot.species] then
          night[#night + 1] = pick
        else
          all[#all + 1] = pick
        end
      end
    end
    if tod == "NITE" then
      return #night > 0 and night or all
    end
    return all
  end

  local Flyer = {}
  Flyer.__index = Flyer

  local function mountFor(game, species)
    local sprite, class = Sky.mountSprite(game.data, species, "wild_skies")
    return sprite, CLASS_PROFILE[class] or DEFAULT_PROFILE
  end

  -- the voxel mod's shape profile, when installed, tells us which cells
  -- are building-scale solids a bird can sit on top of.  The profile is
  -- plain data, so rooftop perching works in the flat 2D game too.
  local tileShape          -- nil = not tried, false = unavailable
  local function roofHeightAt(map, cx, cy)
    if tileShape == nil then
      tileShape = false
      local Game = require("src.core.Game")
      local exports = Game.mods and Game.mods.exports
      local V = exports and exports.DRAMATIC_SHAPE
        and exports.DRAMATIC_SHAPE.lib
      if V and V.require then
        local ok, ts = pcall(V.require, "TileShape")
        if ok and ts and ts.forMap then tileShape = ts end
      end
    end
    if not tileShape then return nil end
    local ok, h = pcall(function()
      local s = tileShape.forMap(map)[map:cellTile(cx, cy)]
      if not s or s.art == "stair" then return nil end
      return (s.h or 0) >= 16 and s.h or nil
    end)
    return ok and h or nil
  end

  -- an occupied roost pulls newcomers in: a bird already sat on a roof
  -- offers the free roof cells beside it to whoever lands next
  local function roofNeighborCell(ow, map)
    for _, f in ipairs(flyers) do
      if not f.dead and f.mode == "ground" and (f.perchAlt or 0) > 0 then
        for _ = 1, 8 do
          local x = f.cellX + love.math.random(-2, 2)
          local y = f.cellY + love.math.random(-2, 2)
          if (x ~= f.cellX or y ~= f.cellY) and map:inBounds(x, y) then
            local h = roofHeightAt(map, x, y)
            if h then
              local taken = false
              for _, o in ipairs(flyers) do
                if not o.dead and o.mode == "ground"
                   and o.cellX == x and o.cellY == y then
                  taken = true
                  break
                end
              end
              if not taken then return x, y, h end
            end
          end
        end
      end
    end
    return nil
  end

  -- somewhere a bird can sit, inside the camera view but away from the
  -- player: a walkable, unoccupied street cell, or a flat rooftop.
  -- Returns cell x, cell y, perch height in px (0 on the street).
  local function findPerchCell(ow, game)
    local cam, map, p = ow.camera, ow.map, ow.player
    local vw, vh = game.renderer:worldViewSize()
    -- downtown birds live on the skyline: in towns they strongly prefer
    -- rooftops, elsewhere it is a coin flip
    local wantRoof = love.math.random()
      < (picksCache.peaceful and 0.85 or 0.5)
    -- rooftops (and treetops) are an outdoor idea; a cave wall is not
    -- furniture
    if wantRoof then
      local MapDef = require("src.world.Map")
      local FieldDefaults = require("src.world.FieldDefaults")
      wantRoof = map.def ~= nil and MapDef.isOutside(map.def,
        FieldDefaults.field(game.data, "outsideTilesets")) == true
    end
    -- joining an existing roost beats founding a new one
    if wantRoof then
      local jx, jy, jh = roofNeighborCell(ow, map)
      if jx then return jx, jy, jh end
    end
    -- a roof seeker holds out for a roof through the whole scan and only
    -- settles for the first street cell it saw when none turned up
    local groundX, groundY
    for _ = 1, 24 do
      local x = math.floor((cam.x + love.math.random(0, vw)) / 16)
      local y = math.floor((cam.y + love.math.random(0, vh)) / 16)
      if map:inBounds(x, y)
         and math.abs(x - p.cellX) + math.abs(y - p.cellY) >= 4 then
        local roofH = wantRoof and roofHeightAt(map, x, y) or nil
        if roofH then return x, y, roofH end
        if not groundX and map:isWalkableCell(x, y) then
          local Collision = require("src.world.Collision")
          if not Collision.occupied(ow.entities, x, y, nil) then
            groundX, groundY = x, y
            if not wantRoof then return x, y, 0 end
          end
        end
      end
    end
    if groundX then return groundX, groundY, 0 end
    return nil
  end

  function Flyer.new(game, ow, pick, leader)
    local sprite, profile = mountFor(game, pick.species)
    if not sprite then return nil end
    serial = serial + 1
    local self = setmetatable({}, Flyer)
    self.id = "wild_skies_" .. serial
    self.sprite = sprite
    self.species = pick.species
    self.level = pick.level or love.math.random(3, 10)
    self.passable = true
    self.bobAmp = profile.bob
    self.scale = Sky.dexScale(game.data, pick.species)
    -- big wings beat slower: the class rate eased by dex size
    self.flap = profile.flap / math.max(1, self.scale)
    self.speed = love.math.random(profile.speed[1], profile.speed[2])
    -- roughly a third of birds will meet a player head on; the rest are
    -- scenery to every battle seam and simply scatter
    self.bold = love.math.random() < 0.35

    local map, cam, p = ow.map, ow.camera, ow.player
    local vw, vh = game.renderer:worldViewSize()
    self.mapW = ((map.widthCells or (map.width or 10) * 2)) * 16
    self.mapH = ((map.heightCells or (map.height or 9) * 2)) * 16

    -- a personal patch of the shared band, drifted within while
    -- roaming; roamFor is this visit's length before it flies on
    self.band = { SKY_BAND[1], SKY_BAND[2] }
    self.altTarget = love.math.random(self.band[1], self.band[2])
    self.roamFor = 16 + love.math.random() * 16
    self.facing = "right"

    if leader then
      -- a flock member enters beside its leader, on the same heading
      self.px = math.max(0, math.min(self.mapW - 16,
                  leader.px + love.math.random(-28, 28)))
      self.py = math.max(0, math.min(self.mapH - 16,
                  leader.py + love.math.random(-28, 28)))
      self.heading = leader.heading or 0
      self.alt = math.max(self.band[1],
        (leader.alt or self.altTarget) + love.math.random(-8, 8))
      self.mode = "roam"
    else
      local roll = love.math.random()
      local perchX, perchY, perchAlt
      if roll < 0.2 then
        perchX, perchY, perchAlt = findPerchCell(ow, game)
      end
      if perchX then
        -- perched from the start, on a street cell or a rooftop;
        -- flushes when approached or when its rest runs out
        self.mode = "ground"
        self.px, self.py = perchX * 16, perchY * 16
        self.perchAlt = perchAlt or 0
        -- safe up on a roof, a bird lingers; street rests stay short
        self.groundT = self.perchAlt > 0 and love.math.random(14, 30)
          or love.math.random(6, 14)
        self.alt = self.perchAlt
        self.heading = love.math.random() < 0.5 and 0 or math.pi
      else
        -- airborne entry from just past the camera's near edge, heading
        -- into the view at a loose angle
        local margin = 24
        local dir = love.math.random() < 0.5 and 1 or -1
        local startX = dir == 1 and (cam.x - margin - 16)
          or (cam.x + vw + margin)
        self.px = math.max(0, math.min(self.mapW - 16, startX))
        self.py = math.max(0, math.min(self.mapH - 16,
                    cam.y + love.math.random(8, math.max(9, vh - 24))))
        -- a small map can clamp the "off-screen" entry right next to
        -- the player; refuse to materialize a bird on top of them
        if math.abs(math.floor((self.px + 8) / 16) - p.cellX)
           + math.abs(math.floor((self.py + 8) / 16) - p.cellY) < 5 then
          return nil
        end
        self.heading = (dir == 1 and 0 or math.pi)
          + (love.math.random() - 0.5) * math.rad(50)
        self.alt = self.altTarget
        self.mode = "roam"
      end
    end
    self.t = 0
    self.vx = math.cos(self.heading) * self.speed
    self.vy = math.sin(self.heading) * self.speed
    self.cellX = math.floor((self.px + 8) / 16)
    self.cellY = math.floor((self.py + 8) / 16)
    return self
  end

  -- one integration step at the current heading; ease scales speed.
  -- Facing follows the dominant axis, sticky so diagonals never strobe.
  function Flyer:step(dt, ease)
    self.vx = math.cos(self.heading) * self.speed * (ease or 1)
    self.vy = math.sin(self.heading) * self.speed * (ease or 1)
    self.px = self.px + self.vx * dt
    self.py = self.py + self.vy * dt
    local ax, ay = math.abs(self.vx), math.abs(self.vy)
    if self.facing == "up" or self.facing == "down" then
      ax = ax / 1.3
    else
      ay = ay / 1.3
    end
    if ax >= ay then
      self.facing = self.vx < 0 and "left" or "right"
    else
      self.facing = self.vy < 0 and "up" or "down"
    end
  end

  local function turnToward(self, want, maxTurn)
    local diff = (want - self.heading + math.pi) % (2 * math.pi) - math.pi
    if diff > maxTurn then diff = maxTurn
    elseif diff < -maxTurn then diff = -maxTurn end
    self.heading = self.heading + diff
  end

  -- gentle boids among same-species roamers: push apart up close, drift
  -- toward the group and its shared heading further out.  With two or
  -- three birds up this reads as a loose vee, never a swarm.
  local function flockHeading(self)
    local sepX, sepY, close = 0, 0, 0
    local cohX, cohY, avgSin, avgCos, near = 0, 0, 0, 0, 0
    for _, o in ipairs(flyers) do
      if o ~= self and not o.dead and o.species == self.species
         and o.mode == "roam" then
        local dx, dy = o.px - self.px, o.py - self.py
        local d = math.abs(dx) + math.abs(dy)
        if d < 14 then
          sepX, sepY, close = sepX - dx, sepY - dy, close + 1
        elseif d < 64 then
          cohX, cohY = cohX + dx, cohY + dy
          avgSin = avgSin + math.sin(o.heading or 0)
          avgCos = avgCos + math.cos(o.heading or 0)
          near = near + 1
        end
      end
    end
    if close > 0 then return math.atan2(sepY, sepX), 2.5 end
    if near > 0 then
      return math.atan2(cohY * 0.4 + avgSin * 24,
                        cohX * 0.4 + avgCos * 24), 0.8
    end
    return nil
  end

  -- a soft leash to the camera: birds that stray past the view plus a
  -- margin steer back, so the sky the player sees stays populated
  local function leashHeading(self, ow)
    local Game = require("src.core.Game")
    local cam = ow.camera
    local vw, vh = Game.renderer:worldViewSize()
    local cx, cy = cam.x + vw / 2, cam.y + vh / 2
    local dx, dy = cx - self.px, cy - self.py
    if math.abs(dx) > vw / 2 + 64 or math.abs(dy) > vh / 2 + 64 then
      return math.atan2(dy, dx)
    end
    return nil
  end

  function Flyer:tick(ow, dt)
    self.t = self.t + dt
    local p = ow.player
    -- a bird that cannot battle right now (shy, downtown, or inside the
    -- after-battle rest) never lets the player walk up to it
    local timid = not (self.bold and battleRest <= 0)
    local nearPlayer = p ~= nil
      and math.abs(p.cellX - self.cellX)
        + math.abs(p.cellY - self.cellY) <= FLUSH_CELLS

    if self.mode == "ground" then
      self.groundT = self.groundT - dt
      -- a rooftop percher is out of reach of anyone on foot: only an
      -- airborne player scares it off; walkers just pass underneath
      local reachable = (self.perchAlt or 0) <= 0 or playerAirborne(p)
      local near = nearPlayer and reachable
      if near or self.groundT <= 0 then
        self.mode = "rise"
        if near and p then
          -- flush away from the player
          self.heading = math.atan2(self.py - p.py, self.px - p.px)
        end
        self.altTarget = love.math.random(self.band[1], self.band[2])
      end
    elseif self.mode == "rise" then
      self.alt = math.min(self.altTarget, self.alt + CLIMB * dt)
      self:step(dt, 0.5)
      if self.alt >= self.altTarget then self.mode = "roam" end
    elseif self.mode == "toLand" and timid and nearPlayer
           and ((self.perchAlt or 0) <= 0 or playerAirborne(p)) then
      -- landing beside someone it wants no part of: abort and climb.
      -- A rooftop target stays fine: the walker below cannot reach it.
      self.mode = "roam"
      self.startleT = 1.6
      self.altTarget = self.band[2]
    elseif self.mode == "toLand" then
      local dx, dy = self.landX - self.px, self.landY - self.py
      local dist = math.abs(dx) + math.abs(dy)
      if dist > 5 then
        turnToward(self, math.atan2(dy, dx), TURN_MAX * 1.5 * dt)
        self:step(dt, math.min(1, dist / 40 + 0.35))
        -- sink toward the approach height on the way in
        local approach = (self.perchAlt or 0) + math.min(16, dist * 0.4)
        if self.alt > approach then
          self.alt = math.max(approach, self.alt - CLIMB * dt)
        end
      else
        self.px, self.py = self.landX, self.landY
        self.alt = self.alt - CLIMB * dt
        if self.alt <= (self.perchAlt or 0) then
          self.alt = self.perchAlt or 0
          self.mode = "ground"
          self.groundT = (self.perchAlt or 0) > 0
            and love.math.random(12, 26) or love.math.random(4, 10)
        end
      end
    elseif self.mode == "summon" then
      local dx, dy = self.summonX - self.px, self.summonY - self.py
      if math.abs(dx) + math.abs(dy) <= 8 then
        -- arrived: this bird is spoken for and leaves the sky here
        local sid = self.summonId
        self.summonId = nil
        self.dead = true
        battleRest = BATTLE_REST
        pcall(function()
          mod.events:emit("mod.wild_skies.flyer_summoned", {
            summonId = sid, species = self.species, level = self.level,
            cellX = self.cellX, cellY = self.cellY,
          })
        end)
      else
        turnToward(self, math.atan2(dy, dx), TURN_MAX * 2 * dt)
        self:step(dt, 1.35)
        if self.alt > 12 then
          self.alt = math.max(12, self.alt - CLIMB * dt)
        end
        if self.t > (self.summonBy or 0) then
          summonFail(self, "too slow")
        end
      end
    elseif self.mode == "leave" then
      -- straight out on the exit heading; gone once it clears the view
      self:step(dt, 1)
      local Game = require("src.core.Game")
      local cam = ow.camera
      local vw, vh = Game.renderer:worldViewSize()
      if self.px < cam.x - 48 or self.px > cam.x + vw + 48
         or self.py < cam.y - 48 or self.py > cam.y + vh + 48
         or self.t > (self.leaveBy or math.huge) then
        self.dead = true
      end
    else -- roam
      if timid and nearPlayer and (self.alt or 0) <= 28 then
        -- startle: break off whatever it was doing and climb away
        self.startleT = 1.6
        self.altTarget = self.band[2]
      end
      if (self.startleT or 0) > 0 then
        self.startleT = self.startleT - dt
        if p then
          turnToward(self, math.atan2(self.py - p.py, self.px - p.px),
                     TURN_MAX * 2 * dt)
        end
        self:step(dt, 1.25)
        self.alt = math.min(self.altTarget, self.alt + CLIMB * dt)
        self.cellX = math.floor((self.px + 8) / 16)
        self.cellY = math.floor((self.py + 8) / 16)
        if not ow.map:inBounds(self.cellX, self.cellY) then
          self.dead = true
        end
        return
      end
      -- wander: capped-turn jitter, then the flock pull and the leash
      local jitter = (love.math.random() * 2 - 1) * WANDER * dt
      self.heading = self.heading + math.max(-TURN_MAX * dt,
        math.min(TURN_MAX * dt, jitter))
      local want, weight = flockHeading(self)
      if want then turnToward(self, want, weight * dt) end
      local leash = leashHeading(self, ow)
      if leash then turnToward(self, leash, TURN_MAX * 1.2 * dt) end
      self:step(dt, 1)

      -- altitude roams too: fresh heights now and then, with the odd
      -- swoop low enough to meet a walking player
      if love.math.random() < dt / 6 then
        self.altTarget = love.math.random() < LOW_PASS
          and love.math.random(8, 14)
          or love.math.random(self.band[1], self.band[2])
      end
      if self.alt < self.altTarget then
        self.alt = math.min(self.altTarget, self.alt + DRIFT * dt)
      elseif self.alt > self.altTarget then
        self.alt = math.max(self.altTarget, self.alt - DRIFT * dt)
      end

      -- the occasional rest stop, street or rooftop
      if self.t > 4 and love.math.random() < dt / 18 then
        local Game = require("src.core.Game")
        local lx, ly, lAlt = findPerchCell(ow, Game)
        if lx then
          self.mode = "toLand"
          self.landX, self.landY = lx * 16, ly * 16
          self.perchAlt = lAlt or 0
        end
      end

      -- this visit is over: pick the nearest edge and fly on
      if self.t >= self.roamFor then
        self.mode = "leave"
        self.leaveBy = self.t + 14
        local cx = self.px + 8
        if math.min(self.py, self.mapH - self.py)
           < math.min(cx, self.mapW - cx) then
          self.heading = self.py > self.mapH / 2
            and math.pi / 2 or -math.pi / 2
        else
          self.heading = cx > self.mapW / 2 and 0 or math.pi
        end
      end
    end

    self.cellX = math.floor((self.px + 8) / 16)
    self.cellY = math.floor((self.py + 8) / 16)
    if not ow.map:inBounds(self.cellX, self.cellY) then
      self.dead = true
    end
  end

  -- the voxel pipeline live?  a rooftop percher then carries its roof
  -- height into pose() so the card sits on the mesh; flat 2D draws it
  -- on the tile art instead
  local function voxelOn()
    local ok, Pipelines = pcall(require, "src.render.Pipelines")
    return ok and Pipelines and Pipelines.level
      and (Pipelines.level("voxel") or 0) > 0
  end

  local function visualLift(self)
    if self.mode == "ground" then
      if (self.perchAlt or 0) > 0 and voxelOn() then return self.perchAlt end
      return 0
    end
    local bob = self.mode == "roam"
      and math.sin(self.t * 3) * self.bobAmp or 0
    return self.alt + bob
  end

  local function flapPhase(self)
    if self.mode == "ground" then
      -- a resting bird mostly stands, with the odd peck
      return (math.floor(self.t * 2) % 5 == 0) and 1 or 0
    end
    return math.floor(self.t * self.flap) % 2
  end

  -- the overworld entity loop calls this in the world pass
  local function spriteScale(self)
    local s = (self.scale or 1) * sizeMult()
    if self.scaleCap then s = math.min(s, self.scaleCap) end
    return s
  end

  function Flyer:draw(camX, camY)
    local s = spriteScale(self)
    local lift = visualLift(self)
    -- the shadow fades and tightens with height, a cheap depth cue
    local fade = math.max(0.35, 1 - lift / 90)
    local size = math.max(0.6, 1 - lift / 140)
    love.graphics.setColor(0, 0, 0, 0.3 * fade)
    love.graphics.ellipse("fill", self.px + 8 - camX, self.py + 14 - camY,
                          5 * s * size, 2 * s * size)
    love.graphics.setColor(1, 1, 1, 1)
    local facing = self.facing or (self.vx < 0 and "left" or "right")
    local sy = math.floor(self.py - lift + 0.5)
    if s ~= 1 then
      local fx = math.floor(self.px + 8 - camX)
      local fy = math.floor(sy + 12 - camY)
      love.graphics.push()
      love.graphics.translate(fx, fy)
      love.graphics.scale(s, s)
      love.graphics.translate(-fx, -fy)
    end
    self.sprite:draw(math.floor(self.px + 0.5), sy, camX, camY,
                     facing, flapPhase(self), false)
    if s ~= 1 then love.graphics.pop() end
  end

  -- same pose contract as NPC/Player, so render pipelines (voxel, tilt)
  -- can billboard a flyer without knowing what it is; the lift is baked
  -- into the returned y
  function Flyer:pose()
    return self.sprite, self.px, self.py - visualLift(self),
           self.facing or (self.vx < 0 and "left" or "right"),
           flapPhase(self), false, false
  end

  -- spawn one flyer on demand (scenario mods, tests): entry, height and
  -- behaviour roll as usual; the ambient caps and cooldowns are not
  -- consulted.  Returns the flyer id, or nil and a reason.
  mod.exports.spawnFlyer = function(species, level)
    local Game = require("src.core.Game")
    local ow = Game and Game.overworld
    if not (ow and ow.map and ow.player) then return nil, "no overworld" end
    local flyer = Flyer.new(Game, ow, { species = species, level = level })
    if not flyer then
      return nil, "no sprite or no clear entry for " .. tostring(species)
    end
    flyer.bold = true -- an explicitly requested bird is always touchable
    flyers[#flyers + 1] = flyer
    table.insert(ow.entities, flyer)
    return flyer.id
  end

  -- a sprite-source mod changed its settings (e.g. Wilds of Kanto's
  -- Sprite Style): live flyers re-dress in the new art immediately
  mod.events:on("mod.options_changed", function(payload)
    if not Sky.spriteSourceChanged(payload) then return end
    local Game = require("src.core.Game")
    for _, f in ipairs(flyers) do
      local sprite = mountFor(Game, f.species)
      if sprite then f.sprite = sprite end
    end
  end)

  local keepThroughSeam = false

  mod.events:on("map.exited", function()
    if keepThroughSeam then
      keepThroughSeam = false
      return
    end
    local Game = require("src.core.Game")
    clearAll(Game and Game.overworld)
    cooldown = 3
  end)

  mod.events:on("game.ready", function()
    local Game = require("src.core.Game")
    local OC = require("src.world.OverworldController")
    local MapDef = require("src.world.Map")
    local FieldDefaults = require("src.world.FieldDefaults")

    local bumpCooldown = 0

    local function skyTick(ow, dt)
      if not (ow and ow.map and ow.player) then return end
      dt = dt or 1 / 60
      battleRest = math.max(0, battleRest - dt)
      for i = #flyers, 1, -1 do
        local f = flyers[i]
        f:tick(ow, dt)
        if f.dead then
          if f.summonId then summonFail(f, "lost") end
          detach(ow, f)
          table.remove(flyers, i)
        end
      end

      -- a LOW bird can bump a grounded player into its battle; high
      -- flyers never touch anyone below them.  Airborne players are
      -- free_fly's interception's business, not this one's.
      bumpCooldown = math.max(0, bumpCooldown - dt)
      local p = ow.player
      if bumpCooldown <= 0 and p and not playerAirborne(p)
         and mod.options:get("bumps") then
        local f = flyerNear(p.cellX, p.cellY, 1)
        if f and (f.alt or 0) <= LOW_ALT then
          local db = mod.find("double_battles")
          if db and db.exports and db.exports.tagOrganic then
            pcall(db.exports.tagOrganic)
          end
          local okQ = mod.world:queueScript({
            { "start_battle", "wild", f.species, f.level or 5 },
          })
          if okQ then
            bumpCooldown = 2
            battleRest = BATTLE_REST
            -- the flock partner source keys off this record: the bump
            -- battle about to start may recruit a second bird
            lastBump = { species = f.species, level = f.level or 5,
                         at = love.timer.getTime() }
            pcall(function()
              require("src.core.Sound").playCry(Game.data, f.species)
            end)
            f.dead = true
            detach(ow, f)
            for i = #flyers, 1, -1 do
              if flyers[i] == f then table.remove(flyers, i) end
            end
            mod.log:info("bumped into %s!", tostring(f.species))
            pcall(function()
              mod.events:emit("mod.wild_skies.flyer_bumped", {
                species = f.species, level = f.level or 5,
                cellX = f.cellX, cellY = f.cellY,
              })
            end)
          end
        end
      end

      cooldown = cooldown - dt
      local d = density()
      -- ambient (slot-less) skies stay sparser than encounter-fed ones,
      -- and the forest canopy holds one bird at a time
      local cap = picksCache.ambient and math.max(1, d.cap - 1) or d.cap
      if picksCache.forest then cap = 1 end
      if cooldown > 0 or #flyers >= cap then return end
      local tod = ow.tod or "DAY"
      local def = ow.map.def
      local forest = def and def.tileset == "FOREST"
      local outside = def and (forest or MapDef.isOutside(def,
        FieldDefaults.field(Game.data, "outsideTilesets"))) or false
      -- a cave is dark at noon: its crepuscular slots (the Zubat line)
      -- fly at any hour, so Mt Moon's air is never empty by daylight
      local effTod = outside and tod or "NITE"
      local key = ow.map.id .. "#" .. effTod
      if picksCache.key ~= key then
        picksCache.key = key
        picksCache.ambient = false
        picksCache.picks = flyingSlots(Game, ow.map.id, effTod)
        picksCache.forest = forest or false
        picksCache.inside = not outside
        picksCache.levels = nil
        -- towns and cities get sky-life too, but as scenery only: every
        -- bird there is shy, so nothing ever starts a battle downtown.
        -- Cinnabar is an _ISLAND and the league gate a _PLATEAU; the
        -- outside gate keeps indoor lookalikes (Seafoam's cave floors)
        -- out of this bucket and their battles intact.
        local id = ow.map.id
        local town = outside and (id:find("_TOWN", 1, true) ~= nil
          or id:find("_CITY", 1, true) ~= nil
          or id:find("_ISLAND", 1, true) ~= nil
          or id:find("_PLATEAU", 1, true) ~= nil) or false
        picksCache.peaceful = town
        -- ambient skies where the game itself hosts wildlife (sea
        -- routes carry encounter tables) and over every town and city
        local encDef = Game.data.encounters
          and Game.data.encounters[ow.map.id]
        if #picksCache.picks == 0 and def and outside
           and (encDef or town) then
          -- water encounters and no grass means open sea
          local sea = not town and encDef and encDef.water ~= nil
            and not (encDef.grass and encDef.grass.slots
                     and #encDef.grass.slots > 0)
          local pool = tod == "NITE" and AMBIENT_NITE
            or sea and AMBIENT_SEA or AMBIENT_DAY
          for _, species in ipairs(pool) do
            picksCache.picks[#picksCache.picks + 1] = { species = species }
          end
          -- the map's own slot levels, so ambient birds match the local
          -- level curve rather than a flat roll
          local levels = {}
          if encDef then
            for _, tbl in ipairs({ encDef.grass, encDef.water }) do
              for _, slot in ipairs((tbl and tbl.slots) or {}) do
                if slot.level then levels[#levels + 1] = slot.level end
              end
            end
          end
          picksCache.levels = levels[1] and levels or nil
          picksCache.ambient = true
        end
      end
      local picks = picksCache.picks
      if #picks == 0 then
        cooldown = d.cooldown
        return
      end
      cooldown = d.cooldown * (picksCache.forest and 2.5
        or picksCache.ambient and 1.8 or 1) + love.math.random() * 6
      local pick = picks[love.math.random(#picks)]
      local ultra = false
      if not picksCache.inside and not picksCache.forest
         and not picksCache.peaceful
         and love.math.random(ULTRA_ODDS) == 1 then
        local u = ULTRA_RARES[love.math.random(#ULTRA_RARES)]
        pick = { species = u.species,
                 level = love.math.random(u.level[1], u.level[2]) }
        ultra = true
      end
      if not pick.level then
        -- roll one of the map's own slot levels; with no wildlife to
        -- read (towns), scale with the player's journey instead, one
        -- gym at a time (0 badges L3-8 up to 8 badges L43-56).  The
        -- species' band then holds either roll to believable numbers.
        local levels = picksCache.levels
        local base
        if levels then
          base = levels[love.math.random(#levels)]
        else
          local n = 0
          pcall(function()
            local Badges = require("src.inventory.Badges")
            n = Badges.count(Game.data, Game.save) or 0
          end)
          base = love.math.random(3 + n * 5, 8 + n * 6)
        end
        local band = AMBIENT_LEVELS[pick.species]
        local level = base
        if band then
          level = math.max(band[1], math.min(band[2], base or band[1]))
        end
        if level then
          pick = { species = pick.species, level = level }
        end
      end
      -- per-map manners: forests fly under the canopy, caves hug a low
      -- ceiling AND cap the draw scale, because a Dodrio at its full
      -- 1.6x dex size in a cramped corridor reads as a monster
      local function tuneForMap(f)
        if picksCache.forest then
          f.band = { 10, 16 }
          f.altTarget = math.min(f.altTarget, 16)
          f.alt = math.min(f.alt, 16)
        elseif picksCache.inside then
          f.band = { 10, 24 }
          f.altTarget = math.min(f.altTarget, 24)
          f.alt = math.min(f.alt, 24)
          f.scaleCap = 1.15
        end
        if picksCache.peaceful then f.bold = false end
        return f
      end

      local flyer = Flyer.new(Game, ow, pick)
      if flyer then
        tuneForMap(flyer)
        if ultra then flyer.bold = true end
        flyers[#flyers + 1] = flyer
        table.insert(ow.entities, flyer)
        if ultra then
          mod.log:info("the legendary %s (L%d) is crossing %s!",
                       tostring(flyer.species), flyer.level or 0, ow.map.id)
        else
          mod.log:info("%s (L%d) is roaming %s",
                       tostring(flyer.species), flyer.level or 0, ow.map.id)
        end
        -- sometimes company arrives: a loose flock of the same species,
        -- inside the cap; the boids pull them into formation.  A legend
        -- flies alone.
        if flyer.mode == "roam" and not ultra and not picksCache.forest then
          local room = cap - #flyers
          if room > 0 and love.math.random() < 0.4 then
            for _ = 1, math.min(room, love.math.random(1, 2)) do
              local wing = Flyer.new(Game, ow, pick, flyer)
              if wing then
                tuneForMap(wing)
                flyers[#flyers + 1] = wing
                table.insert(ow.entities, wing)
              end
            end
          end
        end
      end
    end

    -- the guard blocks pre-1.6.1 leftover wraps (a hot reload keeps
    -- them in the chain) from double-ticking mid-frame
    OC.__wildSkiesTick = function(ow, dt)
      if OC.__skyTicking then return end
      return skyTick(ow, dt)
    end
    Sky.ensureUpdateWrap(OC, "__wildSkiesTick", mod.hooks)

    -- birds survive seamless connection crossings: translate them by the
    -- same coordinate rebase the player gets, and re-attach them to the
    -- rebuilt entity list.  Out-of-bounds ones despawn naturally.
    if not OC.__wildSkiesSeamWrapped then
      OC.__wildSkiesSeamWrapped = true
      local origCross = OC.crossConnection
      OC.crossConnection = function(self, dir, conn)
        local carry = OC.__wildSkiesCarry
        if not carry then return origCross(self, dir, conn) end
        return carry(self, dir, conn, origCross)
      end
    end
    OC.__wildSkiesCarry = function(self, dir, conn, origCross)
      local p = self.player
      local beforeX, beforeY = p.px, p.py
      keepThroughSeam = #flyers > 0
      local crossed = origCross(self, dir, conn)
      if not crossed then
        keepThroughSeam = false
        return crossed
      end
      local dx, dy = p.px - beforeX, p.py - beforeY
      for _, f in ipairs(flyers) do
        f.px, f.py = f.px + dx, f.py + dy
        if f.landX then f.landX, f.landY = f.landX + dx, f.landY + dy end
        f.cellX = math.floor((f.px + 8) / 16)
        f.cellY = math.floor((f.py + 8) / 16)
        f.mapW = ((self.map.widthCells or (self.map.width or 10) * 2)) * 16
        f.mapH = ((self.map.heightCells or (self.map.height or 9) * 2)) * 16
        table.insert(self.entities, f)
      end
      return crossed
    end
  end)

  -- ------- doubles integration (double_battles, when present)

  -- which battles carry a partner this sky provided, and as what;
  -- weak-keyed so an abandoned battle never pins its record
  local skyPartner = setmetatable({}, { __mode = "k" })

  mod.events:on("game.ready", function()
    local db = mod.find("double_battles")
    local ex = db and db.exports
    if not ex then return end
    -- a legendary sighting stays strictly 1v1: a partner would spoil
    -- the catch, and the aimed-ball rule ends the battle on a capture
    if ex.registerDoubleVeto then
      ex.registerDoubleVeto({
        id = "wild_skies_legendary",
        veto = function(game, battle)
          local e = battle and battle.enemy
          return (e and e.mon and ULTRA_SET[e.mon.species]) and true
            or false
        end,
      })
    end
    -- a bumped bird brings its flockmate: the second foe of a bump
    -- battle comes from the same sky, ahead of the summoned-bird path
    if ex.registerPartnerSource then
      ex.registerPartnerSource({
        id = "wild_skies_flock",
        priority = 40,
        provide = function(game, battle)
          local bump = lastBump
          if not bump then return nil end
          if love.timer.getTime() - bump.at > 10 then return nil end
          local e = battle and battle.enemy
          if not (e and e.mon and e.mon.species == bump.species) then
            return nil
          end
          local p = game.overworld and game.overworld.player
          if not p then return nil end
          local mate = mod.exports.takeFlockmate(p.cellX, p.cellY, 8)
          if not mate then return nil end
          skyPartner[battle] = { species = mate.species }
          return mate.species, mate.level
        end,
      })
    end
  end)

  -- a summoned bird that became the second foe is sky property too
  mod.events:on("mod.double_battles.double_started", function(ev)
    local b = ev and ev.battle
    if b and ev.recruited and b.enemy2 and b.enemy2.mon then
      skyPartner[b] = { species = b.enemy2.mon.species }
    end
  end)

  -- a fight that ended without deciding the sky bird (the player ran,
  -- or caught the other one) puts the survivor back in the air
  mod.events:on("battle.ended", function(ev)
    local b = ev and ev.battle
    local rec = b and skyPartner[b]
    if not rec then return end
    skyPartner[b] = nil
    if ev.result ~= "run" and ev.result ~= "caught" then return end
    -- a caught battle keeps the caught mon healthy in the lead slot,
    -- so only the second slot can be the fleeing survivor there
    local pool = ev.result == "caught" and { b.enemy2 }
      or { b.enemy, b.enemy2 }
    for _, battler in ipairs(pool) do
      if battler and battler.mon and battler.mon.hp > 0
         and battler.mon.species == rec.species then
        pcall(mod.exports.spawnFlyer, battler.mon.species,
              battler.mon.level)
        return
      end
    end
  end)
end

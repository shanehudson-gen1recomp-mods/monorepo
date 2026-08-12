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

  -- crepuscular species only fly the night sky.  This hand list is a
  -- fallback: a dataset overhaul that exports a period-aware ecology
  -- (Crystal 251) teaches us its own night species automatically, and
  -- the Gen 2 ids here are inert until such a dataset registers them
  local NIGHT_ONLY = { ZUBAT = true, GOLBAT = true, CROBAT = true,
                       HOOTHOOT = true, NOCTOWL = true, MURKROW = true }

  -- FLYING-typed but flightless: the type exists for battle mechanics,
  -- the sky asks a different question.  The dex has Doduo and Dodrio
  -- running, and Natu hopping; none of them belongs overhead.
  local FLIGHTLESS = { DODUO = true, DODRIO = true, NATU = true }

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
  -- is never a hatchling and never an outlier (levels ride into battles).
  -- Species outside this list use the band the world itself deals them
  -- (their observed encounter-slot levels, gathered below).
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

  -- Derived skies: rather than hand-listing every generation's birds,
  -- the ambient pools grow from the world's own encounter tables.  Any
  -- FLYING species a dataset (vanilla, Crystal 251, a future overhaul)
  -- places in a wild slot earns the ambient sky: WATER/FLYING species
  -- patrol the sea pool, night species the night pool, the rest the
  -- day pool.  Weight follows how widely the world hosts the species,
  -- capped so the curated pools keep their flavor, and the observed
  -- slot levels become the species' believable band.
  local function derivedSky(data)
    local recs, order = {}, {}
    for _, row in ipairs(Sky.wildRows(data)) do
      for _, slot in ipairs(row.slots) do
        local s = slot.species
        if Sky.hasType(data, s, "FLYING") and not ULTRA_SET[s]
           and not FLIGHTLESS[s] then
          local rec = recs[s]
          if not rec then
            rec = { count = 0, lo = math.huge, hi = 0 }
            recs[s] = rec
            order[#order + 1] = s
          end
          rec.count = rec.count + 1
          if slot.level then
            rec.lo = math.min(rec.lo, slot.level)
            rec.hi = math.max(rec.hi, slot.level)
          end
        end
      end
    end
    table.sort(order)
    return recs, order
  end

  -- night knowledge: a dataset that exports a period-aware ecology
  -- (Crystal 251's `ecology.list()`) tells us which of its species fly
  -- only after dark -- present in a night table, absent from every
  -- morning and day one.  Probed by capability, never by mod id, so
  -- any overhaul speaking the same shape is understood.  The hand
  -- list keeps the Zubat line (and known Gen 2 owls) nocturnal when
  -- no ecology is exported.
  local function nightSet(game)
    local night = {}
    for s in pairs(NIGHT_ONLY) do night[s] = true end
    -- a period-aware dataset teaches its own night species without any
    -- probe: present in a night slot table and absent from every
    -- morning and day one.  Gold's tables carry periods natively; on
    -- Gen 1 an ecology export says the same thing through the exports
    -- scan below.
    local daylight, dark = {}, {}
    for _, row in ipairs(Sky.wildRows(game.data)) do
      for _, slot in ipairs(row.slots) do
        if row.period == "NITE" then
          dark[slot.species] = true
        elseif row.period ~= nil then
          daylight[slot.species] = true
        end
      end
    end
    for s in pairs(dark) do
      if not daylight[s] then night[s] = true end
    end
    local exports = game.mods and game.mods.exports or {}
    for _, ex in pairs(exports) do
      local eco = type(ex) == "table" and ex.ecology
      if type(eco) == "table" and type(eco.list) == "function" then
        local ok, rows = pcall(eco.list)
        if ok and type(rows) == "table" then
          local daylight = {}
          for _, row in ipairs(rows) do
            if row.period == "day" or row.period == "morning" then
              for _, slot in ipairs((row.group and row.group.slots) or {}) do
                daylight[slot.species] = true
              end
            end
          end
          for _, row in ipairs(rows) do
            if row.period == "night" then
              for _, slot in ipairs((row.group and row.group.slots) or {}) do
                if not daylight[slot.species] then
                  night[slot.species] = true
                end
              end
            end
          end
        end
      end
    end
    return night
  end

  -- a curated base pool plus every derived species that belongs in
  -- this air; base membership wins so the hand weighting stays intact
  local function ambientPool(data, extKey, night, recs, order)
    local base = extKey == "NITE" and AMBIENT_NITE
      or extKey == "SEA" and AMBIENT_SEA or AMBIENT_DAY
    local pool, inBase = {}, {}
    for _, s in ipairs(base) do
      pool[#pool + 1] = s
      inBase[s] = true
    end
    for _, s in ipairs(order) do
      if not inBase[s] then
        local bucket = night[s] and "NITE"
          or Sky.hasType(data, s, "WATER") and "SEA" or "DAY"
        if bucket == extKey then
          for _ = 1, math.min(recs[s].count, 3) do pool[#pool + 1] = s end
        end
      end
    end
    return pool
  end

  local flyers = {}
  -- Seam-neighbor maps are already resident in the engine and visible through
  -- ow.ghosts. Keep one local flock per resident map so a connection crossing
  -- promotes the birds the player could already see instead of rerolling the
  -- destination or translating the source flock into it.
  local residentFields, residentGhosts = {}, {}
  local residentGhostClock, residentGhostDt = 0, 1 / 60
  local sharedProvider, sharedProviderId
  local sharedActive, sharedAuthority = false, false
  local sharedMap, sharedRevision = nil, 0
  local sharedSnapshots, pendingSharedClaim = {}, nil
  local requestSharedContact -- forward: installed with the provider adapter
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

  -- the entity list is Gen 1 furniture: Gold's world rebuilds its own
  -- at will, never draws from it, and would count a low bird as a
  -- ledge-hop blocker, so flyers there live only in this mod's list
  -- and the drawPeople tail armed in skyTick
  local function attach(ow, flyer)
    if not Sky.goldWorld(ow) then table.insert(ow.entities, flyer) end
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
    if f then return { id = f.id, species = f.species, level = f.level,
      altitude = f.alt or 0 } end
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
    if sharedActive then requestSharedContact(f); return nil end
    local Game = require("src.core.Game")
    f.dead = true
    detach(Sky.liveOverworld(Game), f)
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
    if sharedActive and not sharedAuthority then return nil end
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
    detach(Sky.liveOverworld(Game), best)
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
    if sharedActive and not sharedAuthority then return nil, "shared replica" end
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
    if enc and enc.species and not (sharedActive and not sharedAuthority) then
      local Game = require("src.core.Game")
      local ow = Sky.liveOverworld(Game)
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
  local function flyingSlots(game, mapId, tod, nocturnal)
    nocturnal = nocturnal or NIGHT_ONLY
    local all, night = {}, {}
    for _, slot in ipairs(Sky.grassSlots(game.data, mapId, tod)) do
      if Sky.hasType(game.data, slot.species, "FLYING")
         and not FLIGHTLESS[slot.species] then
        local pick = { species = slot.species, level = slot.level }
        if nocturnal[slot.species] then
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
    local vw, vh = Sky.viewSize(game, ow)
    -- downtown birds live on the skyline: in towns they strongly prefer
    -- rooftops, elsewhere it is a coin flip
    local wantRoof = love.math.random()
      < (picksCache.peaceful and 0.85 or 0.5)
    -- rooftops (and treetops) are an outdoor idea; a cave wall is not
    -- furniture
    if wantRoof then
      wantRoof = map.def ~= nil and Sky.outsideMap(game.data, map.def)
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
    self.wildSkiesFlyer = true
    self.sprite = sprite
    self.species = pick.species
    self.level = pick.level or love.math.random(3, 10)
    self.passable = true
    self.bobAmp = profile.bob
    -- a True Size sheet already encodes the species' size
    self.scale = Sky.trueSized(sprite) and 1
      or Sky.dexScale(game.data, pick.species)
    -- big wings beat slower: the class rate eased by dex size
    self.flap = profile.flap / math.max(1, self.scale)
    self.speed = love.math.random(profile.speed[1], profile.speed[2])
    -- roughly a third of birds will meet a player head on; the rest are
    -- scenery to every battle seam and simply scatter
    self.bold = love.math.random() < 0.35

    local map, cam, p = ow.map, ow.camera, ow.player
    local vw, vh = Sky.viewSize(game, ow)
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
    local vw, vh = Sky.viewSize(Game, ow)
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
      local vw, vh = Sky.viewSize(Game, ow)
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

  local function isTownMap(mapId)
    local id = tostring(mapId or "")
    return id:find("_TOWN", 1, true) ~= nil
      or id:find("_CITY", 1, true) ~= nil
      or id:find("_ISLAND", 1, true) ~= nil
      or id:find("_PLATEAU", 1, true) ~= nil
  end

  local function residentProfile(game, map, tod)
    if not (game and game.data and map and map.id) then
      return { picks = {}, forest = false, inside = false, peaceful = false }
    end
    local def = map.def
    -- the same generation-agnostic reads the live sky uses: outdoors
    -- from the map record, wildlife and levels from whichever
    -- encounter shape the dataset speaks
    local forest = (def ~= nil and def.tileset == "FOREST")
      or tostring(map.id):find("_FOREST", 1, true) ~= nil
    local outside = forest or Sky.outsideMap(game.data, def)
    local effectiveTod = outside and tod or "NITE"
    local nocturnal = nightSet(game)
    local picks = flyingSlots(game, map.id, effectiveTod, nocturnal)
    local town = outside and isTownMap(map.id) or false
    local wild = Sky.mapWild(game.data, map.id)
    local profile = {
      picks = picks, forest = forest, inside = not outside,
      peaceful = town, ambient = false, levels = nil, bands = nil,
    }
    if #picks == 0 and def and outside and (wild or town) then
      local sea = not town and wild ~= nil and wild.water
        and not wild.grass
      local extKey = tod == "NITE" and "NITE" or sea and "SEA" or "DAY"
      local recs, order = derivedSky(game.data)
      local pool = ambientPool(game.data, extKey, nocturnal, recs, order)
      for _, species in ipairs(pool) do
        picks[#picks + 1] = { species = species }
      end
      local bands = {}
      for species, rec in pairs(recs) do
        if rec.lo <= rec.hi then bands[species] = { rec.lo, rec.hi } end
      end
      profile.bands = bands
      local levels = wild
        and Sky.slotLevels(game.data, map.id, effectiveTod) or {}
      profile.levels = levels[1] and levels or nil
      profile.ambient = true
    end
    return profile
  end

  local function residentPickLevel(game, pick, profile)
    if pick.level then return pick end
    local base
    if profile.levels then
      base = profile.levels[love.math.random(#profile.levels)]
    else
      local badges = Sky.badgeCount(game.data, game.save)
      base = love.math.random(3 + badges * 5, 8 + badges * 6)
    end
    local band = AMBIENT_LEVELS[pick.species]
      or (profile.bands and profile.bands[pick.species])
    if band then base = math.max(band[1], math.min(band[2], base or band[1])) end
    return { species = pick.species, level = base }
  end

  local function seedResidentField(game, ow, neighbor)
    local map = neighbor and neighbor.map
    if not (map and map.id) then return nil end
    if residentFields[map.id] then return residentFields[map.id] end
    local profile = residentProfile(game, map, ow.tod or "DAY")
    local picks = profile.picks
    local field = { map = map, flyers = {} }
    residentFields[map.id] = field
    if #picks == 0 then return field end

    local d = density()
    local count = math.max(1, math.min(profile.forest and 1 or d.cap, 3))
    local ox, oy = tonumber(neighbor.ox) or 0, tonumber(neighbor.oy) or 0
    local fake = {
      map = map, entities = {}, npcs = {}, ghosts = {}, neighbors = {},
      tod = ow.tod,
      camera = { x = (ow.camera and ow.camera.x or 0) - ox,
                 y = (ow.camera and ow.camera.y or 0) - oy },
      player = {
        px = (ow.player.px or ow.player.cellX * 16) - ox,
        py = (ow.player.py or ow.player.cellY * 16) - oy,
      },
    }
    fake.player.cellX = math.floor((fake.player.px + 8) / 16)
    fake.player.cellY = math.floor((fake.player.py + 8) / 16)

    local oldPeaceful = picksCache.peaceful
    picksCache.peaceful = profile.peaceful
    local attempts = 0
    while #field.flyers < count and attempts < count * 6 do
      attempts = attempts + 1
      local pick = residentPickLevel(game, picks[love.math.random(#picks)], profile)
      local f = Flyer.new(game, fake, pick)
      if f then
        if profile.forest then
          f.band = { 10, 16 }
          f.altTarget, f.alt = math.min(f.altTarget, 16), math.min(f.alt, 16)
        elseif profile.inside then
          f.band = { 10, 24 }
          f.altTarget, f.alt = math.min(f.altTarget, 24), math.min(f.alt, 24)
          f.scaleCap = 1.15
        end
        if profile.peaceful then f.bold = false end
        field.flyers[#field.flyers + 1] = f
        fake.entities[#fake.entities + 1] = f
      end
    end
    picksCache.peaceful = oldPeaceful
    return field
  end

  local function storeResidentField(map)
    if not (map and map.id) then return end
    residentFields[map.id] = { map = map, flyers = flyers }
    local prefix = tostring(map.id) .. ":"
    for key in pairs(residentGhosts) do
      if key:sub(1, #prefix) == prefix then residentGhosts[key] = nil end
    end
  end

  local function newResidentGhost(mapId, f)
    local ghost = setmetatable({
      id = f.id, sprite = f.sprite, species = f.species, level = f.level,
      wildSkiesFlyer = true, wildSkiesResidentGhost = true, passable = true,
      bobAmp = f.bobAmp, scale = f.scale, scaleCap = f.scaleCap,
      flap = f.flap, bold = f.bold, px = f.px, py = f.py, alt = f.alt,
      facing = f.facing, mode = f.mode, perchAlt = f.perchAlt, t = f.t or 0,
      vx = f.vx or 0, vy = f.vy or 0,
      mapW = f.mapW, mapH = f.mapH,
    }, Flyer)
    ghost.update = function(self)
      local dt = residentGhostDt
      self.t = (self.t or 0) + dt
      if self.mode ~= "ground" then
        local maxX = math.max(0, (self.mapW or 16) - 16)
        local maxY = math.max(0, (self.mapH or 16) - 16)
        self.px = self.px + (self.vx or 0) * dt
        self.py = self.py + (self.vy or 0) * dt
        if self.px <= 0 or self.px >= maxX then
          self.px = math.max(0, math.min(maxX, self.px))
          self.vx = -(self.vx or 0)
        end
        if self.py <= 0 or self.py >= maxY then
          self.py = math.max(0, math.min(maxY, self.py))
          self.vy = -(self.vy or 0)
        end
        local ax, ay = math.abs(self.vx or 0), math.abs(self.vy or 0)
        if ax >= ay then
          self.facing = (self.vx or 0) < 0 and "left" or "right"
        else
          self.facing = (self.vy or 0) < 0 and "up" or "down"
        end
      end
      self.cellX = math.floor((self.px + 8) / 16)
      self.cellY = math.floor((self.py + 8) / 16)
    end
    residentGhosts[tostring(mapId) .. ":" .. tostring(f.id)] = ghost
    return ghost
  end

  local function syncResidentGhosts(game, ow)
    if not (ow and type(ow.neighbors) == "table"
       and type(ow.ghosts) == "table") then return end
    -- Gold's ghost list is engine-internal: drawPeople draws its
    -- entries with the (ox, oy, scale) arity and rebuildPeople wipes
    -- injected rows at will, and its neighbors carry ids rather than
    -- map instances, so resident skies stay a Gen 1 surface for now
    if Sky.goldWorld(ow) then return end
    for i = #ow.ghosts, 1, -1 do
      if ow.ghosts[i].wildSkiesResidentGhost then table.remove(ow.ghosts, i) end
    end
    local live, residentMaps = {}, {}
    if ow.map and ow.map.id then residentMaps[ow.map.id] = true end
    for _, neighbor in ipairs(ow.neighbors) do
      local map = neighbor.map
      if map and map.id then residentMaps[map.id] = true end
      local field
      if map and sharedProvider then
        -- A session provider owns composition. Until its bounded snapshot
        -- arrives, show an empty shared sky rather than inventing a local one
        -- that will visibly reset on the next canonical echo.
        field = sharedSnapshots[map.id] and residentFields[map.id] or nil
      else
        field = map and seedResidentField(game, ow, neighbor)
      end
      local peers, entries = {}, {}
      for _, f in ipairs((field and field.flyers) or {}) do
        if not f.dead then
          local key = tostring(map.id) .. ":" .. tostring(f.id)
          live[key] = true
          local ghost = residentGhosts[key] or newResidentGhost(map.id, f)
          peers[#peers + 1], entries[#entries + 1] = ghost, ghost
        end
      end
      for _, ghost in ipairs(entries) do
        ow.ghosts[#ow.ghosts + 1] = {
          npc = ghost, map = map, ox = neighbor.ox, oy = neighbor.oy,
          peers = peers, wildSkiesResidentGhost = true,
        }
      end
    end
    for key in pairs(residentGhosts) do
      if not live[key] then residentGhosts[key] = nil end
    end
    for mapId in pairs(residentFields) do
      if not residentMaps[mapId] then residentFields[mapId] = nil end
    end
  end

  local function activateResidentField(game, ow, field)
    if not (ow and field) then return false end
    flyers = field.flyers or {}
    for i = #ow.entities, 1, -1 do
      if ow.entities[i].wildSkiesFlyer then table.remove(ow.entities, i) end
    end
    for _, f in ipairs(flyers) do
      if not f.dead then
        local ghost = residentGhosts[tostring(field.map.id) .. ":" .. tostring(f.id)]
        if ghost then
          f.px, f.py, f.alt = ghost.px, ghost.py, ghost.alt
          f.vx, f.vy, f.facing = ghost.vx, ghost.vy, ghost.facing
          f.speed = math.sqrt((f.vx or 0) ^ 2 + (f.vy or 0) ^ 2)
          if f.speed > 0 then f.heading = math.atan2(f.vy, f.vx) end
        end
        if f.sharedReplica then
          f.sharedEntryRevision = f._sharedRevision or 0
        end
        f.mapW = ((ow.map.widthCells or (ow.map.width or 10) * 2)) * 16
        f.mapH = ((ow.map.heightCells or (ow.map.height or 9) * 2)) * 16
        f.cellX = math.floor((f.px + 8) / 16)
        f.cellY = math.floor((f.py + 8) / 16)
        attach(ow, f)
      end
    end
    syncResidentGhosts(game, ow)
    return true
  end

  local function reconcileFlyerEntities(ow)
    if not (ow and ow.entities) then return end
    -- flyers stay out of Gold's entity list (it rebuilds at will,
    -- never draws from it, and counts entities as ledge blockers)
    if Sky.goldWorld(ow) then return end
    local wanted = {}
    for _, f in ipairs(flyers) do
      if f and not f.dead then wanted[f] = true end
    end
    for i = #ow.entities, 1, -1 do
      local entity = ow.entities[i]
      if entity and entity.wildSkiesFlyer and not wanted[entity] then
        table.remove(ow.entities, i)
      end
    end
    for _, f in ipairs(flyers) do
      if f and not f.dead then
        local found = false
        for _, entity in ipairs(ow.entities) do
          if entity == f then found = true; break end
        end
        if not found then ow.entities[#ow.entities + 1] = f end
      end
    end
  end

  local function removeFlyer(f)
    local Game = require("src.core.Game")
    f.dead = true
    detach(Sky.liveOverworld(Game), f)
    for i = #flyers, 1, -1 do
      if flyers[i] == f then table.remove(flyers, i) end
    end
  end

  -- ------- Gold resident skies
  -- Gold has no mod-facing ghost surface, so its neighbor flocks are
  -- ticked here against a translated stand-in world and drawn by the
  -- drawPeople tail at the seam offset; a connection crossing then
  -- swaps flocks instead of clearing, the same continuity the Gen 1
  -- ghost surface provides.  Gold's neighbor entries carry ids, not
  -- map instances, so a minimal map wrapper is built off the def.
  local goldSeamFrom

  local function goldNeighborMap(world, id)
    local def = world.maps and world.maps[id]
    if not def then return nil end
    local MapDef = require("src.world.Map")
    local w = (def.width or 10) * 2
    local h = (def.height or 9) * 2
    return {
      id = id, def = def, widthCells = w, heightCells = h,
      inBounds = function(_, x, y)
        return x >= 0 and y >= 0 and x < w and y < h
      end,
      isWalkableCell = function(_, x, y)
        return MapDef.defIsWalkableCell ~= nil
          and MapDef.defIsWalkableCell(def, x, y) == true
      end,
      isWaterCell = function(_, x, y)
        return MapDef.defIsWaterCell ~= nil
          and MapDef.defIsWaterCell(def, x, y) == true
      end,
      cellTile = function() return nil end,
    }
  end

  local function goldResidentTick(game, ow, dt)
    local live = { [ow.map.id] = true }
    for _, nb in ipairs(ow.neighbors or {}) do
      if nb.id and nb.id ~= ow.map.id then
        live[nb.id] = true
        local field = residentFields[nb.id]
        -- a sky that emptied out reseeds; one that seeded empty (no
        -- picks) stays cached rather than rescanning every tick
        if field and field.hadFlyers and #field.flyers == 0 then
          residentFields[nb.id] = nil
          field = nil
        end
        if not field then
          local map = goldNeighborMap(ow, nb.id)
          field = map and seedResidentField(game, ow,
            { map = map, ox = nb.ox, oy = nb.oy })
          if field then field.hadFlyers = #field.flyers > 0 end
        end
        if field then
          field.offset = { nb.ox or 0, nb.oy or 0 }
          local fake = field.standIn
          if not fake then
            fake = { map = field.map, entities = {}, npcs = {},
                     ghosts = {}, neighbors = {}, player = {},
                     camera = {} }
            field.standIn = fake
          end
          fake.tod = ow.tod
          fake.viewW, fake.viewH = ow.viewW, ow.viewH
          fake.camera.x = (ow.camera and ow.camera.x or 0)
            - field.offset[1]
          fake.camera.y = (ow.camera and ow.camera.y or 0)
            - field.offset[2]
          local p = ow.player
          fake.player.px = (p.px or p.cellX * 16) - field.offset[1]
          fake.player.py = (p.py or p.cellY * 16) - field.offset[2]
          fake.player.cellX = math.floor((fake.player.px + 8) / 16)
          fake.player.cellY = math.floor((fake.player.py + 8) / 16)
          for i = #field.flyers, 1, -1 do
            local f = field.flyers[i]
            f:tick(fake, dt)
            if f.dead then table.remove(field.flyers, i) end
          end
        end
      end
    end
    for id in pairs(residentFields) do
      if not live[id] then residentFields[id] = nil end
    end
  end

  local function faceVelocity(f, vx, vy)
    vx, vy = tonumber(vx) or 0, tonumber(vy) or 0
    if math.abs(vx) + math.abs(vy) < 0.5 then return end
    if math.abs(vx) >= math.abs(vy) then
      f.facing = vx < 0 and "left" or "right"
    else
      f.facing = vy < 0 and "up" or "down"
    end
  end

  local function newSharedFlyer(game, map, row)
    local sprite, profile = mountFor(game, row.species)
    if not sprite then return nil end
    local f = setmetatable({
      id = row.id, sprite = sprite, species = row.species, level = row.level,
      wildSkiesFlyer = true, passable = true, bobAmp = profile.bob,
      scale = Sky.trueSized(sprite) and 1
        or Sky.dexScale(game.data, row.species),
      flap = profile.flap, bold = row.bold == true,
      px = row.x, py = row.y, alt = row.alt,
      sharedX = row.x, sharedY = row.y, sharedAlt = row.alt,
      sharedVx = row.vx, sharedVy = row.vy,
      vx = row.vx, vy = row.vy,
      facing = row.facing, mode = row.mode, t = 1,
      mapW = ((map.widthCells or (map.width or 10) * 2) * 16),
      mapH = ((map.heightCells or (map.height or 9) * 2) * 16),
      sharedReplica = true, _sharedRevision = row._revision or 0,
    }, Flyer)
    f.cellX = math.floor((f.px + 8) / 16)
    f.cellY = math.floor((f.py + 8) / 16)
    faceVelocity(f, f.vx, f.vy)
    return f
  end

  local function promoteSharedAuthority(game, f, row)
    local sprite, profile = mountFor(game, row.species)
    if not sprite then return false end
    f.sprite, f.species, f.level = sprite, row.species, row.level
    f.bobAmp = profile.bob
    f.scale = Sky.trueSized(sprite) and 1
      or Sky.dexScale(game.data, row.species)
    f.flap = profile.flap / math.max(1, f.scale)
    f.speed = math.sqrt((row.vx or 0) ^ 2 + (row.vy or 0) ^ 2)
    if f.speed < 0.5 then
      f.speed = love.math.random(profile.speed[1], profile.speed[2])
    end
    f.band = { SKY_BAND[1], SKY_BAND[2] }
    f.altTarget = math.max(f.band[1], math.min(f.band[2], row.alt or 32))
    f.roamFor = math.max((f.t or 1) + 16, 20)
    f.vx, f.vy = row.vx or 0, row.vy or 0
    if math.abs(f.vx) + math.abs(f.vy) < 0.5 then
      f.heading = row.facing == "left" and math.pi or 0
      f.vx, f.vy = math.cos(f.heading) * f.speed,
                   math.sin(f.heading) * f.speed
    else
      f.heading = math.atan2(f.vy, f.vx)
    end
    faceVelocity(f, f.vx, f.vy)
    f.startleT, f.landX, f.landY, f.leaveBy = nil, nil, nil, nil
    f.summonId, f.summonX, f.summonY, f.summonBy = nil, nil, nil, nil
    if row.mode == "ground" then
      f.mode, f.perchAlt, f.groundT = "ground", row.alt or 0, 8
    elseif row.mode == "rise" then
      f.mode, f.perchAlt = "rise", row.alt or 0
    else
      f.mode, f.perchAlt, f.groundT = "roam", nil, nil
    end
    f.sharedReplica = false
    return true
  end

  local VALID_FACING = { up = true, down = true, left = true, right = true }
  local VALID_MODE = { roam = true, ground = true, rise = true,
    toLand = true, leave = true }
  local function finite(value)
    return type(value) == "number" and value == value
      and value > -math.huge and value < math.huge
  end

  local function normalizeSharedSnapshot(snapshot)
    if type(snapshot) ~= "table" or snapshot.domain ~= "SKY"
       or type(snapshot.map) ~= "string" or #snapshot.map > 96
       or not finite(snapshot.revision) or snapshot.revision < 0
       or type(snapshot.spawns) ~= "table" or #snapshot.spawns > 32 then
      return nil, "invalid SKY snapshot"
    end
    local out = { domain = "SKY", map = snapshot.map,
      revision = math.floor(snapshot.revision),
      localAuthority = snapshot.localAuthority == true, spawns = {} }
    local seen = {}
    for _, row in ipairs(snapshot.spawns) do
      if type(row) ~= "table" or type(row.id) ~= "string" or #row.id > 96
         or row.id == "" or seen[row.id]
         or type(row.species) ~= "string" or #row.species > 48
         or not finite(row.x) or not finite(row.y) or not finite(row.alt)
         or math.abs(row.x) > 65535 or math.abs(row.y) > 65535
         or row.alt < 0 or row.alt > 1024
         or (row.vx ~= nil and (not finite(row.vx) or math.abs(row.vx) > 256))
         or (row.vy ~= nil and (not finite(row.vy) or math.abs(row.vy) > 256))
         or not VALID_FACING[row.facing or "right"]
         or not VALID_MODE[row.mode or "roam"] then
        return nil, "invalid SKY spawn"
      end
      seen[row.id] = true
      out.spawns[#out.spawns + 1] = {
        id = row.id, map = snapshot.map, species = row.species,
        level = math.max(1, math.min(100, math.floor(tonumber(row.level) or 5))),
        x = row.x, y = row.y, alt = row.alt,
        vx = tonumber(row.vx) or 0, vy = tonumber(row.vy) or 0,
        facing = row.facing or "right", mode = row.mode or "roam",
        bold = row.bold == true, _revision = out.revision,
      }
    end
    table.sort(out.spawns, function(a, b) return a.id < b.id end)
    return out
  end

  local function reconcileSharedField(snapshot)
    local Game = require("src.core.Game")
    local ow = Sky.liveOverworld(Game)
    local current = ow and ow.map and ow.map.id == snapshot.map
    local field = current and { map = ow.map, flyers = flyers }
      or residentFields[snapshot.map]
    if not field then
      for _, neighbor in ipairs((ow and ow.neighbors) or {}) do
        if neighbor.map and neighbor.map.id == snapshot.map then
          field = { map = neighbor.map, flyers = {} }
          break
        end
      end
    end
    if not field then return true end

    local wanted, byId = {}, {}
    for _, row in ipairs(snapshot.spawns) do wanted[row.id] = row end
    for i = #field.flyers, 1, -1 do
      local f, row = field.flyers[i], wanted[field.flyers[i].id]
      if not row or row.species ~= f.species then
        if current then detach(ow, f) end
        table.remove(field.flyers, i)
      else
        byId[f.id] = f
      end
    end

    for _, row in ipairs(snapshot.spawns) do
      local f = byId[row.id]
      if not f then
        f = newSharedFlyer(Game, field.map, row)
        if f then field.flyers[#field.flyers + 1] = f end
      end
      if f then
        local preserveEntry = current and f.sharedEntryRevision ~= nil
          and snapshot.revision <= f.sharedEntryRevision
        local entryX, entryY, entryAlt = f.px, f.py, f.alt
        local entryVx, entryVy, entryFacing = f.vx, f.vy, f.facing
        if not preserveEntry then f.sharedEntryRevision = nil end
        f._sharedRevision = snapshot.revision
        f.bold, f.level = row.bold, row.level
        if snapshot.localAuthority then
          if f.sharedReplica then promoteSharedAuthority(Game, f, row) end
          if preserveEntry then
            f.px, f.py, f.alt = entryX, entryY, entryAlt
            f.vx, f.vy, f.facing = entryVx, entryVy, entryFacing
            f.speed = math.sqrt((f.vx or 0) ^ 2 + (f.vy or 0) ^ 2)
            if f.speed > 0 then f.heading = math.atan2(f.vy, f.vx) end
          end
        else
          f.sharedReplica = true
          if preserveEntry then
            f.sharedX, f.sharedY, f.sharedAlt = entryX, entryY, entryAlt
            f.sharedVx, f.sharedVy = entryVx or 0, entryVy or 0
          else
            f.sharedX, f.sharedY, f.sharedAlt = row.x, row.y, row.alt
            f.sharedVx, f.sharedVy = row.vx, row.vy
          end
          f.mode = row.mode
          faceVelocity(f, f.sharedVx, f.sharedVy)
        end
        f.cellX = math.floor((f.px + 8) / 16)
        f.cellY = math.floor((f.py + 8) / 16)
      end
    end
    residentFields[snapshot.map] = field
    if current then
      flyers = field.flyers
      reconcileFlyerEntities(ow)
    end
    syncResidentGhosts(Game, ow)
    return true
  end

  local function tickSharedReplicas(dt)
    for _, f in ipairs(flyers) do
      f.t = (f.t or 0) + dt
      local vx, vy = f.sharedVx or 0, f.sharedVy or 0
      f.sharedX = (f.sharedX or f.px) + vx * dt
      f.sharedY = (f.sharedY or f.py) + vy * dt
      f.px, f.py = f.px + vx * dt, f.py + vy * dt
      local k = math.min(1, dt * 10)
      f.px = f.px + ((f.sharedX or f.px) - f.px) * k
      f.py = f.py + ((f.sharedY or f.py) - f.py) * k
      f.alt = f.alt + ((f.sharedAlt or f.alt) - f.alt) * k
      faceVelocity(f, vx, vy)
      f.cellX = math.floor((f.px + 8) / 16)
      f.cellY = math.floor((f.py + 8) / 16)
    end
  end

  local function snapshotFromFlyers(mapId, list, revision, authority)
    local out = { domain = "SKY", map = mapId, revision = revision or 0,
      localAuthority = authority == true, spawns = {} }
    for _, f in ipairs(list or {}) do
      if not f.dead and not f.summonId then
        out.spawns[#out.spawns + 1] = {
          id = f.id, map = mapId, species = f.species, level = f.level or 5,
          x = math.max(0, math.floor((f.px or 0) + 0.5)),
          y = math.max(0, math.floor((f.py or 0) + 0.5)),
          alt = math.max(0, math.floor((f.alt or 0) + 0.5)),
          vx = math.max(-256, math.min(256, math.floor((f.vx or 0) + 0.5))),
          vy = math.max(-256, math.min(256, math.floor((f.vy or 0) + 0.5))),
          facing = f.facing or "right", mode = f.mode or "roam",
          bold = f.bold == true,
        }
      end
    end
    table.sort(out.spawns, function(a, b) return a.id < b.id end)
    return out
  end

  requestSharedContact = function(f)
    if not (sharedActive and sharedProvider and f and not pendingSharedClaim)
       or type(sharedProvider.requestClaim) ~= "function" then return false end
    local Game = require("src.core.Game")
    local owLive = Sky.liveOverworld(Game)
    local mapId = owLive and owLive.map and owLive.map.id
    local airborne = false
    local ff = mod.find("free_fly")
    local isFlying = ff and ff.exports and ff.exports.isFlying
    if isFlying then
      local ok, value = pcall(isFlying)
      airborne = ok and value == true
    end
    local ok, accepted = pcall(sharedProvider.requestClaim,
      mapId, f.id, { airborne = airborne, domain = "SKY" })
    if ok and accepted == true then
      pendingSharedClaim = { map = mapId, id = f.id, flyer = f,
        airborne = airborne }
      return true
    end
    return false
  end

  mod.exports.registerSharedSkyProvider = function(id, provider)
    if type(id) ~= "string" or id == "" or type(provider) ~= "table"
       or type(provider.requestClaim) ~= "function" then
      return false, "provider id and requestClaim function required"
    end
    if sharedProvider and sharedProviderId ~= id then
      mod.exports.clearSharedSkyField()
    end
    sharedProviderId, sharedProvider = id, provider
    local Game = require("src.core.Game")
    local owLive = Sky.liveOverworld(Game)
    if owLive then syncResidentGhosts(Game, owLive) end
    return true
  end

  mod.exports.unregisterSharedSkyProvider = function(id)
    if id ~= sharedProviderId then return false end
    sharedProviderId, sharedProvider = nil, nil
    mod.exports.clearSharedSkyField()
    return true
  end

  mod.exports.sharedSkyNeighborMaps = function()
    local Game = require("src.core.Game")
    local out = {}
    local owLive = Sky.liveOverworld(Game)
    for _, neighbor in ipairs((owLive and owLive.neighbors) or {}) do
      if neighbor.map and neighbor.map.id then out[#out + 1] = neighbor.map.id end
    end
    table.sort(out)
    return out
  end

  mod.exports.sharedSkyFieldSnapshot = function(mapId)
    local Game = require("src.core.Game")
    local ow = Sky.liveOverworld(Game)
    if type(mapId) ~= "string" or not (ow and ow.map) then return nil end
    if ow.map.id == mapId then
      local out = snapshotFromFlyers(mapId, flyers, sharedRevision,
        sharedAuthority)
      sharedSnapshots[mapId] = out
      return out
    end
    if sharedSnapshots[mapId] then return sharedSnapshots[mapId] end
    for _, neighbor in ipairs(ow.neighbors or {}) do
      if neighbor.map and neighbor.map.id == mapId then
        local field = seedResidentField(Game, ow, neighbor)
        local out = snapshotFromFlyers(mapId, field and field.flyers, 0, false)
        sharedSnapshots[mapId] = out
        return out
      end
    end
  end

  mod.exports.applySharedSkyFieldSnapshot = function(snapshot)
    if not sharedProvider then return false, "no shared SKY provider" end
    local normalized, err = normalizeSharedSnapshot(snapshot)
    if not normalized then return false, err end
    local previous = sharedSnapshots[normalized.map]
    if previous and normalized.revision < (previous.revision or 0) then
      return false, "stale SKY revision"
    end
    sharedSnapshots[normalized.map] = normalized
    local Game = require("src.core.Game")
    local ow = Sky.liveOverworld(Game)
    if ow and ow.map and ow.map.id == normalized.map then
      sharedActive, sharedAuthority = true, normalized.localAuthority
      sharedMap, sharedRevision = normalized.map, normalized.revision
    end
    reconcileSharedField(normalized)
    if pendingSharedClaim and normalized.map == pendingSharedClaim.map then
      local present = false
      for _, row in ipairs(normalized.spawns) do
        if row.id == pendingSharedClaim.id then present = true; break end
      end
      if not present then pendingSharedClaim = nil end
    end
    return true
  end

  mod.exports.removeSharedSkyFieldSpawn = function(id)
    for _, f in ipairs(flyers) do
      if f.id == id then removeFlyer(f); return true end
    end
    return true
  end

  mod.exports.grantSharedSkyFieldContact = function(mapId, id)
    local pending = pendingSharedClaim
    if not (pending and pending.map == mapId and pending.id == id) then
      return false
    end
    pendingSharedClaim = nil
    local f = pending.flyer
    if not f or f.dead then return false end
    local hit = { id = f.id, species = f.species, level = f.level or 5,
      altitude = f.alt or 0 }
    removeFlyer(f)
    battleRest = BATTLE_REST
    local Game = require("src.core.Game")
    local started = false
    if pending.airborne then
      local ff = mod.find("free_fly")
      local start = ff and ff.exports and ff.exports.startSharedSkyEncounter
      if start then
        local ok, result = pcall(start, hit)
        started = ok and result == true
      end
    end
    if not started then
      local db = mod.find("double_battles")
      if db and db.exports and db.exports.tagOrganic then
        pcall(db.exports.tagOrganic)
      end
      lastBump = { species = hit.species, level = hit.level,
        at = love.timer.getTime() }
      pcall(function()
        require("src.core.Sound").playCry(Game.data, hit.species)
      end)
      started = mod.world:queueScript({
        { "start_battle", "wild", hit.species, hit.level },
      }) == true
    end
    return started
  end

  mod.exports.denySharedSkyFieldContact = function(mapId, id)
    if not (pendingSharedClaim and pendingSharedClaim.map == mapId
       and pendingSharedClaim.id == id) then return false end
    pendingSharedClaim = nil
    return true
  end

  mod.exports.clearSharedSkyField = function()
    local Game = require("src.core.Game")
    clearAll(Sky.liveOverworld(Game))
    sharedActive, sharedAuthority, sharedMap = false, false, nil
    sharedRevision, pendingSharedClaim, cooldown = 0, nil, 3
    sharedSnapshots, residentFields, residentGhosts = {}, {}, {}
    local ow = Sky.liveOverworld(Game)
    if ow then syncResidentGhosts(Game, ow) end
    return true
  end

  -- spawn one flyer on demand (scenario mods, tests): entry, height and
  -- behaviour roll as usual; the ambient caps and cooldowns are not
  -- consulted.  Returns the flyer id, or nil and a reason.
  mod.exports.spawnFlyer = function(species, level)
    if sharedActive and not sharedAuthority then return nil, "shared replica" end
    local Game = require("src.core.Game")
    local ow = Sky.liveOverworld(Game)
    if not (ow and ow.map and ow.player) then return nil, "no overworld" end
    local flyer = Flyer.new(Game, ow, { species = species, level = level })
    if not flyer then
      return nil, "no sprite or no clear entry for " .. tostring(species)
    end
    flyer.bold = true -- an explicitly requested bird is always touchable
    flyers[#flyers + 1] = flyer
    attach(ow, flyer)
    return flyer.id
  end

  -- a sprite-source mod changed its settings (e.g. Wilds of Kanto's
  -- Sprite Style): live flyers re-dress in the new art immediately
  mod.events:on("mod.options_changed", function(payload)
    if not Sky.spriteSourceChanged(payload) then return end
    local Game = require("src.core.Game")
    for _, f in ipairs(flyers) do
      local sprite = mountFor(Game, f.species)
      if sprite then
        f.sprite = sprite
        f.scale = Sky.trueSized(sprite) and 1
          or Sky.dexScale(Game.data, f.species)
      end
    end
  end)

  local keepThroughSeam = false

  mod.events:on("map.exited", function()
    if keepThroughSeam then
      keepThroughSeam = false
      return
    end
    local Game = require("src.core.Game")
    local owNow = Sky.liveOverworld(Game)
    if Sky.goldWorld(owNow) and not (sharedProvider or sharedActive) then
      -- Gold: only map.entered knows whether this was a seam (its via
      -- says "connection"), so the flock is held for the swap there
      goldSeamFrom = (owNow.map and owNow.map.id) or true
      return
    end
    if sharedProvider or sharedActive then
      clearAll(Sky.liveOverworld(Game))
      sharedActive, sharedAuthority, sharedMap = false, false, nil
      sharedRevision, pendingSharedClaim, cooldown = 0, nil, 0
      residentFields, residentGhosts = {}, {}
      return
    end
    clearAll(Sky.liveOverworld(Game))
    local ow = Sky.liveOverworld(Game)
    if ow and ow.ghosts then
      for i = #ow.ghosts, 1, -1 do
        if ow.ghosts[i].wildSkiesResidentGhost then table.remove(ow.ghosts, i) end
      end
    end
    residentFields, residentGhosts = {}, {}
    cooldown = 3
  end)

  mod.events:on("map.entered", function(ev)
    local Game = require("src.core.Game")
    local ow = Sky.liveOverworld(Game)
    if not ow then return end
    if goldSeamFrom ~= nil and Sky.goldWorld(ow) then
      local from = goldSeamFrom
      goldSeamFrom = nil
      if ev and ev.via == "connection" and ow.map then
        -- seam: park the source flock under its own id and adopt the
        -- destination's resident one, positions intact
        if type(from) == "string" and from ~= ow.map.id then
          local parkedMap = goldNeighborMap(ow, from)
          if parkedMap then
            residentFields[from] = { map = parkedMap, flyers = flyers }
          end
        end
        local arriving = residentFields[ow.map.id]
        residentFields[ow.map.id] = nil
        flyers = (arriving and arriving.flyers) or {}
        for _, f in ipairs(flyers) do
          f.mapW = ((ow.map.widthCells or (ow.map.width or 10) * 2)) * 16
          f.mapH = ((ow.map.heightCells or (ow.map.height or 9) * 2)) * 16
          f.cellX = math.floor((f.px + 8) / 16)
          f.cellY = math.floor((f.py + 8) / 16)
        end
        cooldown = math.max(cooldown, 1)
      else
        clearAll(ow)
        residentFields = {}
        cooldown = 3
      end
      return
    end
    local cached = sharedProvider and ow.map and sharedSnapshots[ow.map.id]
    if cached then
      sharedActive, sharedAuthority = true, cached.localAuthority == true
      sharedMap, sharedRevision = cached.map, cached.revision
      reconcileSharedField(cached)
    else
      syncResidentGhosts(Game, ow)
    end
  end)

  mod.events:on("game.ready", function()
    local Game = require("src.core.Game")
    local OC = require("src.world.OverworldController")

    local bumpCooldown = 0

    -- Gold draws its people from world.npcs and never the entity list,
    -- so the flyers ride a tail on drawPeople; one scaled transform
    -- lets the Gen 1 draw path work unchanged
    local function drawFlyersGold(world, s)
      local cam = world.camera
      local G = love.graphics
      G.push("all")
      G.scale(s or 1, s or 1)
      for _, f in ipairs(flyers) do
        if not f.dead then f:draw(cam.x, cam.y) end
      end
      -- neighbor flocks show through the seam at their offset, the
      -- same reveal the Gen 1 ghost surface gives
      for id, field in pairs(residentFields) do
        local off = field.offset
        if off and id ~= (world.map and world.map.id) then
          for _, f in ipairs(field.flyers) do
            if not f.dead then
              f:draw(cam.x - off[1], cam.y - off[2])
            end
          end
        end
      end
      G.pop()
    end

    local function skyTick(ow, dt)
      if not (ow and ow.map and ow.player) then return end
      dt = dt or 1 / 60
      if Sky.goldWorld(ow) then
        Sky.ensureDrawTail(ow, "__wildSkiesDrawFlyers", drawFlyersGold)
        -- with a session provider, the provider owns composition and
        -- local seeding would fight its snapshots
        if not sharedProvider then goldResidentTick(Game, ow, dt) end
      end
      residentGhostDt = dt
      residentGhostClock = residentGhostClock + dt
      if residentGhostClock >= 0.5 then
        residentGhostClock = 0
        syncResidentGhosts(Game, ow)
      end
      reconcileFlyerEntities(ow)
      battleRest = math.max(0, battleRest - dt)
      if sharedActive and not sharedAuthority then
        tickSharedReplicas(dt)
      else
        for i = #flyers, 1, -1 do
          local f = flyers[i]
          f:tick(ow, dt)
          if f.dead then
            if f.summonId then summonFail(f, "lost") end
            detach(ow, f)
            table.remove(flyers, i)
          end
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
          if sharedActive then
            if requestSharedContact(f) then bumpCooldown = 2 end
            return
          end
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

      -- Replicas may request a canonical claim, but only an authority rolls
      -- new birds or advances private flock behavior.
      if sharedActive and not sharedAuthority then return end

      cooldown = cooldown - dt
      local d = density()
      -- ambient (slot-less) skies stay sparser than encounter-fed ones,
      -- and the forest canopy holds one bird at a time
      local cap = picksCache.ambient and math.max(1, d.cap - 1) or d.cap
      if picksCache.forest then cap = 1 end
      if cooldown > 0 or #flyers >= cap then return end
      local tod = ow.tod or "DAY"
      local def = ow.map.def
      -- Ilex Forest has no FOREST tileset, but its id says canopy
      local forest = (def ~= nil and def.tileset == "FOREST")
        or (ow.map.id or ""):find("_FOREST", 1, true) ~= nil
      local outside = forest or Sky.outsideMap(Game.data, def)
      -- a cave is dark at noon: its crepuscular slots (the Zubat line)
      -- fly at any hour, so Mt Moon's air is never empty by daylight
      local effTod = outside and tod or "NITE"
      local key = ow.map.id .. "#" .. effTod
      if picksCache.key ~= key then
        local nocturnal = nightSet(Game)
        picksCache.key = key
        picksCache.ambient = false
        picksCache.picks = flyingSlots(Game, ow.map.id, effTod, nocturnal)
        picksCache.forest = forest or false
        picksCache.inside = not outside
        picksCache.levels = nil
        picksCache.bands = nil
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
        local wild = Sky.mapWild(Game.data, ow.map.id)
        if #picksCache.picks == 0 and def and outside
           and (wild or town) then
          -- water encounters and no grass means open sea
          local sea = not town and wild ~= nil and wild.water
            and not wild.grass
          local extKey = tod == "NITE" and "NITE" or sea and "SEA" or "DAY"
          local recs, order = derivedSky(Game.data)
          local pool = ambientPool(Game.data, extKey, nocturnal, recs, order)
          for _, species in ipairs(pool) do
            picksCache.picks[#picksCache.picks + 1] = { species = species }
          end
          -- level bands the world itself taught us, for species the
          -- hand-tuned AMBIENT_LEVELS table has never heard of
          local bands = {}
          for s, rec in pairs(recs) do
            if rec.lo <= rec.hi then bands[s] = { rec.lo, rec.hi } end
          end
          picksCache.bands = bands
          -- the map's own slot levels, so ambient birds match the local
          -- level curve rather than a flat roll
          local levels = wild
            and Sky.slotLevels(Game.data, ow.map.id, effTod) or {}
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
          local n = Sky.badgeCount(Game.data, Game.save)
          base = love.math.random(3 + n * 5, 8 + n * 6)
        end
        local band = AMBIENT_LEVELS[pick.species]
          or (picksCache.bands and picksCache.bands[pick.species])
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
        attach(ow, flyer)
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
                attach(ow, wing)
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
    -- Populate the already-resident view on the first ready frame as well;
    -- the periodic refresh below is for movement and newly loaded neighbors,
    -- not the initial reveal.
    syncResidentGhosts(Game, Sky.liveOverworld(Game))

    -- Keep a distinct population for every engine-resident seam map. The
    -- destination flock is already visible through ow.ghosts and becomes the
    -- live flock without a reroll or position jump when the player crosses.
    -- Gen 1 seam only: Gold never calls this facade member and fires
    -- map.exited at every crossing instead, so its flyers simply clear
    -- at the seam and respawn on the far side.
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
      local sourceMap = self.map
      storeResidentField(sourceMap)
      -- Even an empty current sky may have a populated destination already
      -- visible through the seam; preserve the resident cache unconditionally.
      keepThroughSeam = true
      local crossed = origCross(self, dir, conn)
      keepThroughSeam = false
      if not crossed then
        return crossed
      end
      local destination = self.map and residentFields[self.map.id]
      if not destination then
        destination = { map = self.map, flyers = {} }
        residentFields[self.map.id] = destination
      end
      activateResidentField(Game, self, destination)
      if sharedProvider or sharedActive then
        local snapshot = sharedSnapshots[self.map.id]
        sharedActive, sharedMap = true, self.map.id
        sharedAuthority = snapshot and snapshot.localAuthority == true or false
        sharedRevision = snapshot and snapshot.revision or 0
        if snapshot then reconcileSharedField(snapshot) end
      end
      for _, neighbor in ipairs(self.neighbors or {}) do
        if not sharedProvider then seedResidentField(Game, self, neighbor) end
      end
      syncResidentGhosts(Game, self)
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

-- Free Fly: pick FREEFLY on a party member that knows FLY (outdoors, with
-- the THUNDERBADGE, same gate as vanilla FLY) and the player takes off.
-- Airborne you move over any terrain, doors and trainers ignore you, and
-- wild grass rolls are suppressed.  Press B over walkable ground to land.
--
-- Uses the internal seams the public API does not cover yet (player pose
-- lift, warp/trainer-sight gating), so the manifest declares
-- engine_internals.  Every wrap is guarded and keeps its live logic on the
-- module table so F5 hot reload swaps behavior without double-wrapping.
return function(mod)
  -- shared helpers, synced in as lib/shared/ by the monorepo's scripts
  local function loadShared(file)
    local src = mod:read("lib/shared/" .. file)
    if not src then return nil end
    return assert((loadstring or load)(src, "@free_fly/lib/shared/" .. file))()
  end
  local Sky = loadShared("skylib.lua")
  if not Sky then
    mod.log:error("lib/shared/skylib.lua is missing -- run scripts/dev.sh "
      .. "in the gen1recomp-mods repo to sync shared code; mod disabled")
    return
  end
  local function loadLib(file)
    local src = mod:read("lib/" .. file)
    if not src then return nil end
    local chunk, err = (loadstring or load)(src, "@free_fly/lib/" .. file)
    if not chunk then
      mod.log:error("could not load lib/%s: %s; mod disabled", file,
        tostring(err))
      return nil
    end
    local ok, result = pcall(chunk)
    if not ok then
      mod.log:error("could not initialize lib/%s: %s; mod disabled", file,
        tostring(result))
      return nil
    end
    return result
  end
  local FlightInput = loadLib("FlightInput.lua")
  local VoxelProvider = loadLib("VoxelProvider.lua")
  if not (FlightInput and VoxelProvider) then
    mod.log:error("Free Fly compatibility helpers are missing; reinstall the mod")
    return
  end
  local FollowerLanding = loadLib("FollowerLanding.lua")
  if not (type(FollowerLanding) == "table"
      and type(FollowerLanding.rebuild) == "function") then
    mod.log:error("could not initialize follower landing support; reinstall the mod")
    return
  end

  -- Gold is a second engine: content with no Gen 2 registry home (the
  -- Pallet map script) must not even register there, and a few reads
  -- split per generation below.  The loader's own generation is the
  -- authority at load time, before any world exists.
  local GEN2_BOOT = (function()
    local ok, GV = pcall(require, "src.core.GameVersion")
    if ok and GV and GV.generation and GV.generation() == 2 then
      return true
    end
    -- the loader's generation, probed through the arm it hands us: at
    -- load time the Gen 2 WorldAPI is nil (it materializes with the
    -- live game) and even materialized it never carries
    -- startWildBattle.  This also covers headless loads, where
    -- GameVersion still answers 1.
    local okW, world = pcall(function() return mod.world end)
    if not okW then return false end
    if world == nil then return true end
    return (type(world) == "table"
      and world.startWildBattle == nil) == true
  end)()

  local RISE_SPEED = 72       -- px/s takeoff and landing lerp

  mod.options:define({
    -- voxel extrudes a 6-row house to 48px, so MED clears rooftops
    { key = "altitude", label = "ALTITUDE", type = "choice", default = "med",
      choices = { { "LOW", "low" }, { "MED", "med" }, { "HIGH", "high" } } },
    { key = "speed", label = "FLY SPEED", type = "choice", default = "normal",
      choices = { { "NORMAL", "normal" }, { "FAST", "fast" }, { "TURBO", "turbo" } } },
    { key = "size", label = "SIZE", type = "choice", default = "normal",
      choices = { { "SMALL", "small" }, { "NORMAL", "normal" },
                  { "LARGE", "large" }, { "HUGE", "huge" } } },
    { key = "encounters", label = "AIR ENCOUNTERS", type = "toggle", default = true },
    { key = "spotted", label = "TRAINERS SPOT YOU", type = "toggle", default = false },
    { key = "gates", label = "STORY GATES", type = "toggle", default = true },
    -- vanilla badge requirements: THUNDERBADGE to fly, SOULBADGE to set
    -- down on water.  The Pallet gift bird is exempt from the fly check
    -- (never the surf one), so the quick start survives the option.
    { key = "badges", label = "BADGE CHECKS", type = "toggle", default = true },
    -- the Pallet Town gift Pidgeot; off leaves a fully vanilla start
    { key = "quickstart", label = "QUICK START", type = "toggle", default = true },
    -- the mount banks into turns, pitches with climbs and pulses at
    -- the wing beat, the same attitude wild_skies gives its birds
    { key = "motion", label = "FLIGHT MOTION", type = "toggle",
      default = true },
  })

  -- with jj_quick_select installed (and only then), a FLY WHISTLE key
  -- item appears in the bag: register it to a SELECT+direction slot and
  -- flight toggles like the bicycle does.  The optional dependency in
  -- the manifest orders this mod after quick select, so find() is
  -- authoritative here.
  local quickSelect = mod.find("jj_quick_select")
  if quickSelect then
    mod.content.items:register("FLY_WHISTLE", {
      id = "FLY_WHISTLE",
      name = "FLY WHISTLE",
      price = 0,
      keyItem = true,
      tossable = false,
    })
  end

  local ALTS = { low = 32, med = 56, high = 80 }
  local SPEEDS = { normal = 8, fast = 6, turbo = 4 }   -- frames per step; bike is 8
  local function cruiseAlt() return ALTS[mod.options:get("altitude")] or 56 end
  local function flyFrames() return SPEEDS[mod.options:get("speed")] or 8 end

  -- draw-time multiplier on the dex-height scale of the mon carrying
  -- the player.  Its ladder is tuned against the 16px rider figure, not
  -- wild_skies' bird sizes: the whole ladder sits above the old 1.0
  -- (SMALL is the pre-option look), and the steps stay tight enough
  -- that the rider still reads as seated.  Applied at draw so an
  -- option change re-sizes mid-flight.
  local SIZE_MULT = { small = 1, normal = 1.15, large = 1.35, huge = 1.55 }
  local function sizeMult()
    return SIZE_MULT[mod.options:get("size")] or 1.15
  end

  local GIFT_SPECIES = "PIDGEOT"
  local GIFT_LEVEL = 10
  -- legacy PIDGEY strings: the flag is in existing saves that already
  -- took the old Pidgey gift, so it must never change
  local GIFT_TAKEN = "MOD_FREE_FLY_PIDGEY_TAKEN"
  local GIFT_TEXT = "TEXT_FREE_FLY_PIDGEY"

  local state = { phase = "idle", alt = 0, bob = 0, giftNpcId = nil,
                  rider = nil }

  local function flying() return state.phase ~= "idle" end

  -- Dramatic Shape's maintained/original build and the battle-art fork expose
  -- the same public library seam under different mod ids.  Resolving only the
  -- original id leaves movement permissive but drops every visual half of
  -- flight under the fork: terrain height, lifted camera, first/third-person
  -- movement and cockpit presentation.
  local voxelLib = VoxelProvider.lib

  -- Is a battle screen present NOW?
  --
  -- The old answer was an event latch.  That is sufficient for an ordinary
  -- BattleState, whose enter/finish always emit a matched started/ended pair,
  -- but a co-op mod can replace or hold that state and own a battle screen of
  -- its own.  Seeing the ordinary start without its displaced finish leaves a
  -- historical latch true forever: FREEFLY appears in a menu built just before
  -- the event, refuses when selected, and then disappears from every later
  -- menu.  The stack is the authority because it answers the question being
  -- asked.  The latch remains a fallback for headless/older engines whose
  -- stack does not expose its state list.
  local function battleRunning(game)
    local stack = game and game.stack
    local screens = stack and stack.states
    if type(screens) ~= "table" then return state.inBattle == true end
    local ok, BattleState = pcall(require, "src.battle.BattleState")
    for _, screen in ipairs(screens) do
      if screen and (screen.isBattleScreen == true
          or type(screen.battle) == "table"
          or (ok and getmetatable(screen) == BattleState)) then
        return true
      end
    end
    -- A settled stack disproves a stale event latch.
    return false
  end

  -- Capture the semantic B edge before Input:step drains pressQueue.  The
  -- ordinary wasPressed edge remains the in-world fallback below, but this
  -- boundary is authoritative for a short keyboard tap (X/Backspace), a pad
  -- tap, and another mod's source-safe injected B alike.
  mod.hooks:wrap("input.step", function(nextFn, game, dt)
    local top = game and game.stack and game.stack:top()
    FlightInput.capture(game and game.input,
      flying() and (top == nil or top.isOverworld == true),
      function()
        state.landRequest = true
        mod.log:info("landing requested")
      end)
    return nextFn(game, dt)
  end, 1000)

  -- ------- public API
  -- Flight state for other mods; the takeoff/landed events below are
  -- the push-style counterpart.  Nothing here hands out internals.
  mod.exports.isFlying = function() return flying() end
  mod.exports.altitude = function() return flying() and state.alt or 0 end
  mod.exports.mount = function()
    local mon = flying() and state.mountMon or nil
    if not mon then return nil end
    return { species = mon.species, level = mon.level }
  end
  -- sprite packs with in-air art can register a source (shared/README
  -- in the repo documents the shape); this reaches only THIS mod's
  -- bundled resolver, so packs register with each mod they dress
  mod.exports.registerSpriteSource = Sky.registerSpriteSource
  mod.exports.unregisterSpriteSource = Sky.unregisterSpriteSource

  local function emitTakeoff(mon)
    pcall(function()
      mod.events:emit("mod.free_fly.takeoff",
        { species = mon and mon.species, level = mon and mon.level })
    end)
  end

  -- reason: "landed", "indoors", "blackout" or "save_loaded"; water is
  -- true when the landing handed the player straight into surfing
  local function emitLanded(reason, p, wet)
    pcall(function()
      mod.events:emit("mod.free_fly.landed", {
        reason = reason,
        x = p and p.cellX, y = p and p.cellY,
        water = (wet or (p ~= nil and p.surfing == true)) or nil,
      })
    end)
  end

  local function rebuildConvoyAfterLanding(game, ow, restoreEligibility)
    if Sky.goldWorld(ow) then
      -- Gold's own follower walked beneath the flight and can end up
      -- stacked on the landing cell, drawn over the player; its own
      -- map-entry placement puts it back a tile behind
      pcall(function()
        local Follower = require("src.world.gen2.Follower")
        if Follower and Follower.onMapEntered then
          Follower.onMapEntered(game, ow)
        end
      end)
      return
    end
    local ok, attempted, err = FollowerLanding.rebuild(
      mod, game, ow, restoreEligibility)
    if not ok then
      mod.log:warn("could not rebuild the follower convoy after landing: "
        .. tostring(err))
    elseif attempted then
      mod.log:info("rebuilt the follower convoy after landing")
    end
  end

  -- render pipelines (voxel, tilt) billboard every entity through pose();
  -- while flying the player's own card becomes the bird, and this ghost
  -- entity carries the player figure seated above it.  Invisible in the
  -- flat 2D view, where Player.draw composes the ride itself.
  local Rider = {}
  Rider.__index = Rider
  -- px/py/cellX/cellY are real fields, not conveniences: the overworld
  -- y-sorts entities on py and the voxel capture does arithmetic on it,
  -- so an entity without them crashes both passes
  function Rider.new(player)
    return setmetatable({ player = player, passable = true,
                          px = player.px, py = player.py,
                          cellX = player.cellX, cellY = player.cellY }, Rider)
  end
  function Rider:pose()
    local p = self.player
    local lift = math.floor((p.freeFlyAlt or 0) + 0.5)
    -- Thick voxel characters need more clearance than flat billboards or the
    -- mount's body hides the trainer completely.  This ghost exists only in
    -- pipeline rendering; the flat path composes its own seated rider.
    local clearance = 12
    -- always the WALKING sheet: while airborne p.sprite is the mount
    return p.freeFlyWalkSprite or p.sprite, p.px, p.py - lift - clearance,
           p.facing, 0, false, false
  end
  function Rider:draw() end

  local function knowsFly(mon) return Sky.knowsMove(mon, "FLY") end

  -- where the sky exists: outside maps, plus forest canopies, which
  -- read as open air even where the data classes them indoor
  local function skyAbove(game, mapDef, mapId)
    if not mapDef then return false end
    if Sky.outsideMap(game.data, mapDef) then return true end
    return mapDef.tileset == "FOREST"
      or tostring(mapId or ""):find("_FOREST", 1, true) ~= nil
  end

  -- HM02 compatibility: the species' tmhm list is the same one the
  -- machine-teach path checks, so eligibility exactly matches "could this
  -- mon legitimately learn FLY"
  local function canLearnFly(game, mon)
    local def = mon and game.data.pokemon[mon.species]
    for _, m in ipairs((def and def.tmhm) or {}) do
      if m == "FLY" then return true end
    end
    return false
  end

  -- who may field-use a move is the ENGINE'S question, not this mod's:
  -- OverworldState:partyKnows routes through the fieldmove.eligibility
  -- hook chain, so HM-relaxing mods (qol_toggles' FIELD MOVES ALL) and
  -- anything else wrapping that hook decide alongside the vanilla check.
  -- Returns the mon the chain nominates, or nil.
  local function fieldMoveUser(ow, moveId)
    if ow and ow.partyKnows then
      local ok, user = pcall(ow.partyKnows, ow, moveId)
      if ok then return user end
    end
    return nil
  end

  -- a mon qualifies when it IS the gift (the marker outlives whatever a
  -- randomizer does to its moves or its species' data), when it knows
  -- FLY (knowing the move is vanilla's own bar for field use; the
  -- species compat list can lie under randomizers), or when a mod has
  -- relaxed the field-move rules through the engine's own chain, where
  -- HM02 compatibility still gates as the machine-teach path would
  local function eligibleFlyer(game, ow, mon)
    if mon and mon.freeFlyGift then return true end
    if knowsFly(mon) then return true end
    if not canLearnFly(game, mon) then return false end
    local Runtime = require("src.mods.Runtime")
    return Runtime.wantsHook("fieldmove.eligibility")
      and fieldMoveUser(ow, "FLY") ~= nil
  end

  local function badgeOk(game, mon)
    if not mod.options:get("badges") or mon.freeFlyGift then return true end
    if GEN2_BOOT then
      -- Gold gates FLY on Chuck's STORMBADGE; read it the way its own
      -- field moves do
      local ok, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
      if ok and FieldMoves and FieldMoves.hasBadge then
        return FieldMoves.hasBadge(game.save, "STORM") == true
      end
      return true
    end
    return (game.save.inventory ~= nil
      and game.save.inventory.THUNDERBADGE) and true or false
  end

  -- riding state is a player field on Gen 1 and world state on Gold
  local function ridingBike(ow)
    if Sky.goldWorld(ow) then
      local ok, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
      return (ok and FieldMoves and FieldMoves.isBiking
        and FieldMoves.isBiking(ow.playerState) == true) == true
    end
    return ow ~= nil and ow.player ~= nil and ow.player.onBike == true
  end

  local function partyKnowsSurf(save)
    for _, mon in ipairs(save and save.party or {}) do
      if Sky.knowsMove(mon, "SURF") then return true end
    end
    return false
  end

  local function startFlight(game, mon)
    if flying() then return end
    -- the last line of defense: no route into flight is legal in battle,
    -- however the caller got here
    if battleRunning(game) then
      mod.log:warn("takeoff refused: a battle is running")
      return
    end
    local ow = mod.world and mod.world:overworld()
    if not (ow and ow.player) then
      mod.log:warn("no overworld to take off from; FREEFLY skipped")
      return
    end
    state.phase, state.alt, state.bob = "rising", 0, 0
    -- wild flyers climb on a diagonal; so does the mount
    state.riseGlide = 2
    if state.resolveMount then state.resolveMount(mon) end
    -- taking off from a surf dismounts into the air
    ow.player.surfing = nil
    if Sky.goldWorld(ow) and ow.applyPlayerState then
      pcall(function()
        local FieldMoves = require("src.world.gen2.FieldMoves")
        if FieldMoves.isSurfing(ow.playerState) then
          ow:applyPlayerState(FieldMoves.PLAYER_NORMAL)
        end
      end)
    end
    ow.player.freeFlying = true
    pcall(function()
      require("src.core.Sound").play(require("src.core.Game").data, "Fly")
    end)
    mod.log:info("took off; press B over walkable ground to land")
    emitTakeoff(mon)
  end

  -- a sprite-source mod changed its settings mid-flight: the mount
  -- re-dresses in the new art without landing
  mod.events:on("mod.options_changed", function(payload)
    if not Sky.spriteSourceChanged(payload) then return end
    if flying() and state.resolveMount then
      state.resolveMount(state.mountMon)
    end
  end)

  -- ------- public hooks, all pass-through unless airborne

  mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
    if flying() and ctx.mover and ctx.mover.freeFlying then
      -- very tall buildings stay walls even to a flyer, sealed rooftop
      -- plazas included: you ride up to the facade and bump
      local lm = state.landmark
      if lm and lm.cells and ctx.map and lm.mapId == ctx.map.id
         and lm.cells[ctx.toY * lm.w + ctx.toX] then
        ctx.reason = "tile"
        return false
      end
      if ctx.reason == "tile" or ctx.reason == "entity" then
        ctx.reason = nil
        return true
      end
    end
    return next(allowed, ctx)
  end)

  -- airborne you can only flush other flyers: the vanilla roll stands,
  -- but a non-FLYING result becomes no encounter at all
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    local enc = next(encDef, ctx)
    if not (enc and flying()) then return enc end
    if not mod.options:get("encounters") then return nil end
    local game = require("src.core.Game")
    if Sky.hasType(game.data, enc.species, "FLYING") then return enc end
    return nil
  end)

  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    if flying() then return math.min(frames, flyFrames()) end
    return next(frames, ctx)
  end)

  mod.hooks:wrap("save.write", function(next, game)
    if flying() then
      mod.log:warn("can't save mid-flight; land first (press B)")
      return false
    end
    return next(game)
  end)

  -- FREEFLY exists in exactly one place: the overworld party submenu,
  -- as the doorway into flight.  It is not a move (never in game.data),
  -- so no summary screen, Pokedex or PC can ever list it; these guards
  -- keep the menu entry itself out of every other party-menu context.
  mod.events:on("battle.started", function() state.inBattle = true end)
  mod.events:on("battle.ended", function() state.inBattle = nil end)

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local out = next(game, items, mon, ctx)
    if type(out) ~= "table" then return out end
    -- the battle switch menu also runs through this hook; taking off
    -- from there would unwind the battle screen itself
    if (ctx and ctx.battle) or battleRunning(game) then return out end
    local ow = ctx and ctx.overworld
    if not (ow and ow.map and ow.map.def) or flying() then return out end
    if not (eligibleFlyer(game, ow, mon) and badgeOk(game, mon)) then return out end
    if ridingBike(ow) then return out end
    if not skyAbove(game, ow.map.def, ow.map.id) then return out end
    table.insert(out, 1, { label = "FREEFLY", onSelect = function(m, g)
      -- a stale entry (menu built before a battle started) must not
      -- unwind the battle screen below it
      if battleRunning(g) then return end
      -- unwind party menu / start menu back to the overworld, then lift off
      local stack = g.stack
      while stack:top() and not stack:top().isOverworld do stack:pop() end
      startFlight(g, m)
    end })
    return out
  end)

  -- ------- the Pallet Town Pidgeot: a quick way to get a FLY user

  -- after give_pokemon lands the gift, put FLY in its move list; PIDGEY
  -- stays accepted for anything replaying against an older save
  mod.content.commands:register("free_fly:teach_fly", {
    foreground = true,
    fn = function(ctx)
      local function teach(mon, anySpecies)
        if not mon then return false end
        if not anySpecies
           and mon.species ~= GIFT_SPECIES and mon.species ~= "PIDGEY" then
          return false
        end
        -- marks the gift so the BADGE CHECKS option exempts its flights;
        -- rides the mon table, so it survives in the save
        mon.freeFlyGift = true
        for _, mv in ipairs(mon.moves or {}) do
          if mv.id == "FLY" then return true end
        end
        local flyDef = ctx.game.data.moves.FLY
        local slot = { id = "FLY", pp = flyDef and flyDef.pp or 15 }
        mon.moves = mon.moves or {}
        if #mon.moves >= 4 then
          mon.moves[#mon.moves] = slot
        else
          table.insert(mon.moves, slot)
        end
        return true
      end
      for i = #ctx.save.party, 1, -1 do
        if teach(ctx.save.party[i]) then return end
      end
      for _, box in ipairs(ctx.save.boxes or {}) do
        for _, mon in ipairs(box) do
          if teach(mon) then return end
        end
      end
      -- no bird by name: a randomizer swapped the gift's species.  This
      -- command only runs right after give_pokemon, so the newest party
      -- member IS the gift; it gets FLY and the marker all the same
      local newest = ctx.save.party[#ctx.save.party]
      if teach(newest, true) then
        mod.log:info("gift became %s; taught FLY anyway",
                     tostring(newest.species))
        return
      end
      mod.log:warn("gift %s not found; FLY not taught", GIFT_SPECIES)
    end,
  })

  mod.content.commands:register("free_fly:pidgey_taken", {
    foreground = true,
    fn = function()
      if state.giftNpcId then
        mod.world:removeNpc(state.giftNpcId)
        state.giftNpcId = nil
      end
    end,
  })

  -- the YES branch of the sea-crossing confirm; remembered per save so
  -- each map asks once
  mod.content.commands:register("free_fly:allow_crossing", {
    foreground = true,
    fn = function(_, mapId)
      local ok = mod.save:get("dangerOk")
      if type(ok) ~= "table" then ok = {} end
      ok[mapId] = true
      mod.save:set("dangerOk", ok)
    end,
  })

  if not GEN2_BOOT then mod.content.map_scripts:register("PALLET_TOWN", {
    talk = {
      [GIFT_TEXT] = {
        { "check_flag", GIFT_TAKEN },
        { "jump_if_true", "end" },
        { "show_text", "The tag on this\nPIDGEOT's neck\nsays it can fly\nanywhere without\na badge!\fUse only if\nyou dare" },
        { "choice", { "TAKE IT", "LEAVE IT" } },
        { "jump_if_false", "refused" },
        { "set_flag", GIFT_TAKEN },
        { "give_pokemon", GIFT_SPECIES, GIFT_LEVEL },
        { "free_fly:teach_fly" },
        { "free_fly:pidgey_taken" },
        { "show_text", "PIDGEOT is glad to\ncarry you!\fPick FREEFLY in\nits party menu." },
        { "jump", "end" },

        { "label", "refused" },
        { "show_text", "PIDGEOT tilts its\nhead." },
      },
    },
  }) end

  -- ids of our runtime gift NPCs already living in the map def (the
  -- legacy FREE_FLY_PIDGEY name spans both species):
  -- spawnNpc persists into def.objects, so they outlive the visit that
  -- spawned them and come back on every later map load
  local function giftObjectIds(game)
    local ids = {}
    local def = game.data.maps and game.data.maps.PALLET_TOWN
    for _, obj in ipairs(def and def.objects or {}) do
      if obj.runtime and obj.name == "FREE_FLY_PIDGEY" then
        ids[#ids + 1] = "PALLET_TOWN_obj_" .. obj.index
      end
    end
    return ids
  end

  local function spawnGift()
    local ow = mod.world and mod.world:overworld()
    if not (ow and ow.map and ow.map.id == "PALLET_TOWN") then return end
    local game = require("src.core.Game")
    local taken = game.save and game.save.flags and game.save.flags[GIFT_TAKEN]
    local wanted = mod.options:get("quickstart") and not taken

    -- adopt the survivor from an earlier visit instead of spawning a
    -- twin; retire it (and any twins already accumulated) when the gift
    -- is taken or the option is off
    local existing = giftObjectIds(game)
    for i = #existing, wanted and 2 or 1, -1 do
      mod.world:removeNpc(existing[i])
      table.remove(existing, i)
    end
    if existing[1] then
      state.giftNpcId = existing[1]
      return
    end
    if not wanted then return end
    -- first free walkable cell near the town center
    local Collision = require("src.world.Collision")
    local spots = { { 10, 10 }, { 9, 10 }, { 11, 10 }, { 10, 11 },
                    { 12, 9 }, { 8, 10 }, { 9, 11 }, { 12, 10 } }
    for _, s in ipairs(spots) do
      local x, y = s[1], s[2]
      if ow.map:isWalkableCell(x, y)
         and not Collision.occupied(ow.entities, x, y, nil) then
        state.giftNpcId = mod.world:spawnNpc("PALLET_TOWN", {
          name = "FREE_FLY_PIDGEY",
          sprite = "SPRITE_BIRD",
          movement = "STAY",
          range = "DOWN",
          text = GIFT_TEXT,
          x = x, y = y,
        })
        return
      end
    end
    mod.log:warn("no free cell for the PALLET_TOWN gift this visit")
  end

  -- ------- the New Bark Town Noctowl: Gold's quick start
  -- Gold has no map_scripts home, so the gift is a runtime NPC plus
  -- the world.interacted event, with the ceremony on Gold's own
  -- showText / askYesNo pair (the cart's yesorno pattern: the choice
  -- stacks over the standing text box).  The grant uses Gold's own
  -- Mon factory; the same QUICK START option and the same badge-exempt
  -- marker apply.
  local GOLD_GIFT_SPECIES = "NOCTOWL"
  local GOLD_GIFT_LEVEL = 10
  local GOLD_GIFT_NAME = "FREE_FLY_GIFT"

  local function goldGiftTaken()
    return mod.save:get("goldGiftTaken") == true
  end

  local function goldGiftObjectIds(ow)
    local ids = {}
    local def = ow and ow.maps and ow.maps.NEW_BARK_TOWN
    for _, obj in ipairs((def and def.objects) or {}) do
      if obj.runtime and obj.name == GOLD_GIFT_NAME then
        ids[#ids + 1] = "NEW_BARK_TOWN_obj_" .. obj.index
      end
    end
    return ids
  end

  local function spawnGoldGift()
    if not GEN2_BOOT then return end
    local ow = mod.world and mod.world:overworld()
    if not (ow and ow.map and ow.map.id == "NEW_BARK_TOWN") then return end
    -- the species' own art through the same resolver the sky birds
    -- use; PORTRAIT forces the species-true front pic, and speciesId
    -- lets Stadium voxel worlds model it
    local function dressGoldGift()
      for _, npc in ipairs(ow.npcs or {}) do
        if npc.def and npc.def.name == GOLD_GIFT_NAME then
          npc.speciesId = GOLD_GIFT_SPECIES
          local game = require("src.core.Game")
          local sprite = Sky.mountSprite(game.data, GOLD_GIFT_SPECIES,
            "free_fly_gift", { skyArt = "portrait" })
          if sprite then
            npc.sprite = sprite
            if rawget(sprite, "draw") ~= nil then
              -- a pic renderer draws through its own overworld-sized
              -- path; Gold calls draw(self, ox, oy, scale), the Gen 1
              -- camera math scaled by s
              npc.draw = function(self2, ox, oy, sc)
                local G = love.graphics
                sc = sc or 1
                G.push("all")
                G.scale(sc, sc)
                sprite:draw(self2.px, self2.py,
                  -(ox or 0) / sc, -(oy or 0) / sc,
                  self2.facing or "down",
                  math.floor(love.timer.getTime() * 2) % 2)
                G.pop()
              end
            end
          end
          return
        end
      end
    end
    local wanted = mod.options:get("quickstart") and not goldGiftTaken()
    -- adopt a survivor from an earlier visit instead of spawning a
    -- twin; retire it when the gift is taken or the option is off
    local existing = goldGiftObjectIds(ow)
    for i = #existing, wanted and 2 or 1, -1 do
      mod.world:removeNpc(existing[i])
      table.remove(existing, i)
    end
    if existing[1] then
      state.goldGiftNpcId = existing[1]
      dressGoldGift()
      return
    end
    if not wanted then return end
    local okC, Collision = pcall(require, "src.world.Collision")
    local spots = { { 8, 9 }, { 7, 9 }, { 9, 9 }, { 8, 10 }, { 7, 10 },
                    { 9, 10 }, { 6, 9 }, { 10, 9 } }
    for _, spot in ipairs(spots) do
      local x, y = spot[1], spot[2]
      if ow.map:isWalkableCell(x, y)
         and not (okC and Collision.occupied
                  and Collision.occupied(ow.entities, x, y, nil)) then
        state.goldGiftNpcId = mod.world:spawnNpc("NEW_BARK_TOWN", {
          name = GOLD_GIFT_NAME,
          sprite = "SPRITE_BIRD",
          movement = 6,               -- SPRITEMOVEDATA STANDING_DOWN
          radius = { x = 0, y = 0 },
          sight = 0,
          hours = { -1, -1 },         -- visible at any hour
          eventFlag = 65535,          -- and under no event flag
          palette = 0, type = 0,
          x = x, y = y,
        }) or nil
        dressGoldGift()
        return
      end
    end
    mod.log:warn("no free cell for the NEW_BARK_TOWN gift this visit")
  end

  local function grantGoldGift(game)
    local save = game and game.save
    if not save then return false, "Not now." end
    save.party = save.party or {}
    if #save.party >= 6 then
      return false, "Your party is\nfull!"
    end
    local okM, Mon = pcall(require, "src.battle.gen2.Mon")
    if not (okM and Mon and Mon.new) then return false, "Not now." end
    local mon = Mon.new(game.data, GOLD_GIFT_SPECIES, GOLD_GIFT_LEVEL,
                        { happiness = 120 })
    if not mon then return false, "Not now." end
    -- marks the gift so the BADGE CHECKS option exempts its flights
    mon.freeFlyGift = true
    mon.moves = mon.moves or {}
    local knows = false
    for _, mv in ipairs(mon.moves) do
      if (type(mv) == "table" and mv.id or mv) == "FLY" then
        knows = true
      end
    end
    if not knows then
      local flyDef = game.data.moves and game.data.moves.FLY
      local slot = { id = "FLY", pp = flyDef and flyDef.pp or 15 }
      if #mon.moves >= 4 then
        mon.moves[#mon.moves] = slot
      else
        table.insert(mon.moves, slot)
      end
    end
    table.insert(save.party, mon)
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen[GOLD_GIFT_SPECIES] = true
    save.pokedex.caught[GOLD_GIFT_SPECIES] = true
    return true
  end

  -- Gold answers an A-press by consulting the facade's talkTo seam
  -- BEFORE its script arms, and a script-less runtime NPC matches no
  -- arm at all, so the ceremony lives on that seam (installed at
  -- game.ready).  showText / askYesNo is the cart's own yesorno
  -- pattern: the choice stacks over the standing text box.
  local function goldGiftCeremony(ow, npc)
    local def = npc and npc.def
    if not (def and def.name == GOLD_GIFT_NAME) then return false end
    if not (ow and ow.showText and ow.askYesNo) then return false end
    local game = require("src.core.Game")
    if goldGiftTaken() then
      ow:showText("NOCTOWL hoots\nsoftly.", function() end)
      return true
    end
    ow:showText("The NOCTOWL has\nbeen watching you.\f"
      .. "It can fly you\nanywhere, badge\for no badge.\nClimb on?",
      function()
        ow:askYesNo(function(yes)
          if not yes then
            ow:showText("The NOCTOWL\nturns away.", function() end)
            return
          end
          local granted, why = grantGoldGift(game)
          if not granted then
            ow:showText(why or "Not now.", function() end)
            return
          end
          mod.save:set("goldGiftTaken", true)
          pcall(function()
            require("src.core.Sound").playCry(game.data,
              GOLD_GIFT_SPECIES)
          end)
          ow:showText("NOCTOWL joined\nyour party!\f"
            .. "Pick FREEFLY in\nits party menu.", function() end)
          if state.goldGiftNpcId then
            mod.world:removeNpc(state.goldGiftNpcId)
            state.goldGiftNpcId = nil
          end
        end)
      end)
    return true
  end

  mod.events:on("map.entered", function(ev)
    state.giftNpcId = nil
    state.goldGiftNpcId = nil
    if ev and ev.mapId == "PALLET_TOWN" then spawnGift() end
    if ev and ev.mapId == "NEW_BARK_TOWN" then spawnGoldGift() end
    -- hard guarantee: there is no indoor flight.  Whatever path leads
    -- into a cave or building while airborne, the flight ends on arrival.
    if flying() then
      local ow = mod.world and mod.world:overworld()
      if ow and ow.map and ow.map.def then
        local game = require("src.core.Game")
        if not skyAbove(game, ow.map.def, ow.map.id) then
          state.phase, state.alt = "idle", 0
          mod.log:info("indoors; flight over")
          emitLanded("indoors", ow.player)
        end
      end
    end
  end)

  -- a blackout wakes you at the heal point on solid ground, not mid-air;
  -- the next tick sees the idle phase and clears the player's flags/rider
  -- first person hides the player's card, and the mount is that card; a
  -- rider still expects to see their bird, so draw it into the HUD pass:
  -- bottom-center, back-facing, flapping, like a cockpit view
  local hudQuads = {}
  local hudLogged = false
  mod.hooks:wrap("render.hud", function(next, game, vp)
    local out = next(game, vp)
    if not flying() then return out end
    local ok, err = pcall(function()
      -- resolved once, not per frame
      if state.fpRef == nil then
        state.fpRef = false
        local V = voxelLib(game)
        local okFP, fp = pcall(function() return V and V.require("FirstPerson") end)
        if okFP and fp then state.fpRef = fp end
      end
      local FP = state.fpRef
      -- hidePlayer() is true exactly when the first-person eye hides the
      -- player's card -- the one situation a rider needs a cockpit view
      -- (third person keeps showing the mount card itself)
      if not (FP and FP.hidePlayer and FP.hidePlayer()) then
        if not hudLogged then
          hudLogged = true
          mod.log:info("cockpit idle (%s)",
            not FP and "no compatible voxel lib"
            or not FP.hidePlayer and "no hidePlayer api" or "card visible")
        end
        return
      end
      if not hudLogged then
        hudLogged = true
        mod.log:info("cockpit view active")
      end
      local Player = require("src.world.Player")
      local mount = Player.__freeFlyMount or Player.__freeFlyBird
      local img = mount and mount.image
      if not img then return end
      local SR = require("src.render.SpriteRenderer")
      local t = love.timer.getTime()
      local frame = (math.floor(t * 6) % 2 == 0) and SR.STAND.up or SR.WALK.up
      local key = tostring(img) .. "#" .. frame
      if not hudQuads[key] then
        local iw, ih = img:getDimensions()
        hudQuads[key] = love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih)
      end
      local s = (vp.scale or 4) * 2.2 * (Player.__freeFlyMountScale or 1)
                * sizeMult()
      local x = vp.gameX + vp.gameWidth / 2 - 8 * s
      local y = vp.gameY + vp.gameHeight - 10 * s + math.sin(t * 3) * 3
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, hudQuads[key], x, y, 0, s, s)
    end)
    if not ok and not hudLogged then
      hudLogged = true
      mod.log:warn("cockpit overlay failed: %s", tostring(err))
    end
    return out
  end)

  -- flight never survives into a loaded save (saving is vetoed mid-air),
  -- so a save swap always grounds the state machine; a stale "flying"
  -- phase could otherwise follow the player into a fresh save
  mod.events:on("save.loaded", function()
    local wasFlying = flying()
    state.phase, state.alt = "idle", 0
    if wasFlying then emitLanded("save_loaded", nil) end
  end)

  mod.events:on("world.blacked_out", function()
    if flying() then
      state.phase, state.alt = "idle", 0
      mod.log:info("blacked out; flight over")
      emitLanded("blackout", nil)
    end
  end)

  -- ------- engine wiring

  mod.events:on("game.ready", function()
    local Game = require("src.core.Game")
    local Player = require("src.world.Player")
    local OC = require("src.world.OverworldController")
    local Collision = require("src.world.Collision")
    local MapDef = require("src.world.Map")

    -- per-frame flight state, called from the guarded update wrap below
    local Pipelines = require("src.render.Pipelines")

    -- the ground height the voxel scene will ADD back under the card; 0
    -- whenever the voxel pipeline is off or its lib is unreachable.  This
    -- runs every fixed step, so everything resolvable once is resolved
    -- once and the answer is cached per (map, cell)
    local hasVoxel = Pipelines.get and Pipelines.get("voxel") ~= nil
    local tileShape        -- nil = not tried, false = unavailable
    local ghCache = {}
    -- the shape profile's height for one cell, or nil when the voxel
    -- lib is unreachable
    local function tileHeightAt(map, cx, cy)
      if tileShape == nil then
        tileShape = false
        local V = voxelLib(Game)
        if V and V.require then
          local ok, ts = pcall(V.require, "TileShape")
          if ok and ts and ts.forMap then tileShape = ts end
        end
      end
      if not tileShape then return nil end
      local ok, got = pcall(function()
        if not map:inBounds(cx, cy) then return 0 end
        local s = tileShape.forMap(map)[map:cellTile(cx, cy)]
        if not s or s.art == "stair" then return 0 end
        return s.h > 0 and s.h or 0
      end)
      return ok and got or 0
    end

    -- the shape profile's art class for one cell, or nil when the voxel
    -- lib is unreachable
    local function tileArtAt(map, cx, cy)
      if tileShape == nil then tileHeightAt(map, cx, cy) end
      if not tileShape then return nil end
      local ok, got = pcall(function()
        if not map:inBounds(cx, cy) then return nil end
        local s = tileShape.forMap(map)[map:cellTile(cx, cy)]
        return s and s.art or "none"
      end)
      return ok and got or nil
    end

    -- returns gh, voxelActive
    local function voxelGroundHeight(ow, p)
      if not hasVoxel or Pipelines.level("voxel") <= 0 then return 0, false end
      if ghCache.map == ow.map and ghCache.x == p.cellX
         and ghCache.y == p.cellY then
        return ghCache.h, true
      end
      local h = tileHeightAt(ow.map, p.cellX, p.cellY) or 0
      ghCache.map, ghCache.x, ghCache.y, ghCache.h = ow.map, p.cellX, p.cellY, h
      return h, true
    end

    -- does the badge-gate data forbid an airborne crossing into mapId?
    -- Reads the same field.badgeGates the walking checkpoints enforce, so
    -- any mod that adds its own gates is respected automatically.
    local function storyGateBlocks(mapId)
      local field = Game.data.field
      local entry = field and field.badgeGates and field.badgeGates[mapId]
      if not entry then return false end
      local save = Game.save
      local flags = (save and save.flags) or {}
      local bag = (save and save.inventory) or {}
      if flags[entry.passedFlag or ("PASSED_" .. tostring(mapId))] then
        return false
      end
      if entry.badge then return not bag[entry.badge] end
      for _, guard in ipairs(entry.guards or {}) do
        if not (flags[guard.event] or (guard.badge and bag[guard.badge])) then
          return true
        end
      end
      return false
    end

    local function windBack()
      if (state.windCooldown or 0) > 0 then return end
      state.windCooldown = 3
      pcall(function()
        require("src.core.Sound").play(Game.data, "Collision")
      end)
      mod.world:queueScript({
        { "show_text", "A fierce wind\nblows you back!" },
      })
    end

    local function dropRider(ow)
      if not state.rider then return end
      for i = #ow.entities, 1, -1 do
        if ow.entities[i] == state.rider then table.remove(ow.entities, i) end
      end
      state.rider = nil
    end

    local function syncRider(ow, p)
      local r = state.rider
      if not r or r.player ~= p then
        dropRider(ow)
        r = Rider.new(p)
        state.rider = r
      end
      r.px, r.py = p.px, p.py
      r.cellX, r.cellY = p.cellX, p.cellY
      for _, e in ipairs(ow.entities) do
        if e == r then return end
      end
      -- setMap rebuilds the entity list on every seam crossing, so the
      -- rider re-attaches here each time it goes missing
      table.insert(ow.entities, r)
    end

    local goldBoot = GEN2_BOOT

    local MapField = not goldBoot and require("src.world.FieldDefaults")
      or nil
    local MapLoader = not goldBoot and require("src.world.MapLoader")
      or nil

    -- the whole outdoor world is small (36 maps, under a megabyte of
    -- block data, renderers draw windowed), so a flyer keeps ALL of it
    -- resident: trim() treats the outdoor set as protected, and every
    -- outdoor map is warmed once at one load per tick (~half a second).
    -- Seam crossings then never load anything.  Indoor maps keep the
    -- engine's normal LRU.
    local outdoorSet = {}
    if not goldBoot then
      local outside = MapField.field(Game.data, "outsideTilesets")
      for id, def in pairs(Game.data.maps) do
        if MapDef.isOutside(def, outside) then outdoorSet[id] = true end
      end
    end

    if MapLoader and not MapLoader.__freeFlyWrapped then
      MapLoader.__freeFlyWrapped = true
      local origTrim = MapLoader.trim
      MapLoader.trim = function(protected)
        local policy = MapLoader.__freeFlyTrimPolicy
        if policy then return policy(protected, origTrim) end
        return origTrim(protected)
      end
    end
    -- indoor maps keep their FULL vanilla cache budget: the resident
    -- outdoor world never counts against the engine's cap, and eviction
    -- only happens when indoor maps alone would have exceeded it anyway
    if MapLoader then MapLoader.__freeFlyTrimPolicy = function(protected, origTrim)
      local indoor = 0
      for id in pairs(Game.data.maps) do
        if not outdoorSet[id] and MapLoader.cached(id) then
          indoor = indoor + 1
        end
      end
      if indoor <= 32 then return end
      protected = protected or {}
      for id in pairs(outdoorSet) do protected[id] = true end
      return origTrim(protected)
    end end

    state.prefetchQueue = {}
    for id in pairs(outdoorSet) do
      if MapLoader and not MapLoader.cached(id) then
        state.prefetchQueue[#state.prefetchQueue + 1] = id
      end
    end

    local function mesherBusy()
      if state.mesherRef == nil then
        state.mesherRef = false
        local V = voxelLib(Game)
        local ok, cm = pcall(function() return V and V.require("ChunkMesher") end)
        if ok and cm and cm.pending then state.mesherRef = cm end
      end
      if not state.mesherRef then return false end
      local ok, n = pcall(state.mesherRef.pending)
      return ok and (n or 0) > 0
    end

    local function tickPrefetch()
      if #state.prefetchQueue == 0 then return end
      -- throttled, and it always yields the frame to the voxel mesher:
      -- its arrival builds matter more than our cache warm
      state.prefetchTick = ((state.prefetchTick or 0) + 1) % 6
      if state.prefetchTick ~= 0 or mesherBusy() then return end
      local id = table.remove(state.prefetchQueue)
      if not (id and MapLoader) then return end
      local okLoad = pcall(MapLoader.load, Game.data, id)
      if not okLoad then state.prefetchQueue = {} end
    end

    -- takeoff with the first eligible partner: the FLY WHISTLE's action,
    -- same gates as the FREEFLY menu entry.  Returns ok, failure text.
    local function partnerTakeoff(ow)
      local save = Game.save
      if battleRunning(Game) then
        return false, "This isn't the\ntime to use that!"
      end
      if not (save and ow.map and ow.map.def) then
        return false, "Not here."
      end
      if ridingBike(ow) then
        return false, "Not while riding\nthe BICYCLE!"
      end
      if not skyAbove(Game, ow.map.def, ow.map.id) then
        return false, "There's no open\nsky here!"
      end
      for _, mon in ipairs(save.party or {}) do
        if eligibleFlyer(Game, ow, mon) and badgeOk(Game, mon) then
          -- unwind any menus so the takeoff starts on the overworld
          while Game.stack:top() and not Game.stack:top().isOverworld do
            Game.stack:pop()
          end
          startFlight(Game, mon)
          return true
        end
      end
      return false, "No party member\ncan carry you!"
    end

    if quickSelect then
      -- the whistle's behavior lives in the item-use path, so the bag,
      -- quick select's slots and any other caller all agree
      local ItemEffects = require("src.inventory.ItemEffects")
      if not ItemEffects.__freeFlyWrapped then
        ItemEffects.__freeFlyWrapped = true
        local origUse = ItemEffects.use
        ItemEffects.use = function(data, save, itemId, target, battle, moveIndex, ow)
          local impl = ItemEffects.__freeFlyUse
          if impl then
            local kind, messages = impl(itemId, battle)
            if kind then return kind, messages end
          end
          return origUse(data, save, itemId, target, battle, moveIndex, ow)
        end
      end
      ItemEffects.__freeFlyUse = function(itemId, battle)
        if itemId ~= "FLY_WHISTLE" then return nil end
        if battle then
          return "failed", { "This isn't the\ntime to use that!" }
        end
        if flying() then
          state.landRequest = true
          return "kept", {}
        end
        local ow = mod.world and mod.world:overworld()
        if not ow then
          return "failed", { "This isn't the\ntime to use that!" }
        end
        local ok, why = partnerTakeoff(ow)
        if ok then return "kept", {} end
        return "failed", { why }
      end

      -- the whistle rides the save's bag; hand one over once per save
      local function grantWhistle()
        local save = Game.save
        if save and save.inventory and not save.inventory.FLY_WHISTLE then
          require("src.inventory.Bag").add(save, "FLY_WHISTLE", 1, Game.data)
          mod.log:info("FLY WHISTLE added to the bag (quick select found)")
        end
      end
      grantWhistle()
      mod.events:on("save.loaded", grantWhistle)

      -- With no BICYCLE in the bag, tap-SELECT means flight: Quick
      -- Select's tap is hardcoded to the bicycle and would only print
      -- "You don't have a BICYCLE".  This wrapper runs OUTER on the same
      -- hook (priority 600 vs its 500), takes over the SELECT gesture
      -- for exactly that case, blinds the inner chain to SELECT so Quick
      -- Select never arms, and hands hold+direction slots back through
      -- its public exports.  Own a bicycle and this is fully transparent.
      local DIRS = { "up", "down", "left", "right" }
      local function consumeQueued(input, buttons)
        local drop = {}
        for _, b in ipairs(buttons) do drop[b] = true end
        local kept = {}
        for _, b in ipairs(input.pressQueue or {}) do
          if not drop[b] then kept[#kept + 1] = b end
        end
        input.pressQueue = kept
      end

      mod.hooks:wrap("input.step", function(nextFn, game, dt)
        local input = game and game.input
        local inv = game and game.save and game.save.inventory
        local top = game and game.stack and game.stack:top()
        -- outdoors only: inside, quick select behaves exactly as stock
        local takeover = input and inv and (inv.BICYCLE or 0) <= 0
          and top ~= nil and top.isOverworld
        if takeover then
          local ow = top
          takeover = ow.map and skyAbove(game, ow.map.def, ow.map.id)
        end
        if not takeover then
          state.qsArmed, state.qsHeld = nil, nil
          return nextFn(game, dt)
        end

        local down = input:isDown("select")
        local was = state.qsHeld
        state.qsHeld = down
        if down and not was then
          state.qsArmed = true
          -- consume the press edge immediately: quick select arms off the
          -- raw press queue (not the blinded methods), and an armed state
          -- with no direction is exactly its "You don't have a BICYCLE"
          -- path on release
          consumeQueued(input, { "select" })
        end

        local slotDir
        if state.qsArmed and down then
          for _, d in ipairs(DIRS) do
            if input:wasPressed(d) then slotDir = d break end
          end
        end
        local tap = was and not down and state.qsArmed
        if slotDir or tap then state.qsArmed = nil end

        -- consume BEFORE the inner chain runs: quick select's
        -- between-steps branch reads the raw press queue directly, which
        -- method blinding cannot hide, and it was still answering the tap
        -- with "You don't have a BICYCLE"
        if slotDir then
          consumeQueued(input, { "select", slotDir })
        elseif tap then
          consumeQueued(input, { "select" })
        end

        local origDown, origWas = input.isDown, input.wasPressed
        input.isDown = function(self, b)
          if b == "select" then return false end
          return origDown(self, b)
        end
        input.wasPressed = function(self, b)
          if b == "select" then return false end
          return origWas(self, b)
        end
        local ok, err = pcall(nextFn, game, dt)
        input.isDown, input.wasPressed = origDown, origWas
        if not ok then error(err, 0) end

        if slotDir then
          pcall(function() quickSelect.exports.activate(game, slotDir) end)
        elseif tap then
          local impl = ItemEffects.__freeFlyUse
          if impl then
            local kind, msgs = impl("FLY_WHISTLE", false)
            if kind == "failed" and msgs and msgs[1] then
              game.stack:push(mod.ui.TextBox.new(game, msgs[1]))
            end
          end
        end
      end, 600)
    end

    -- "tall" is derived from the game's own data, never an authored
    -- list: an exterior door whose interior spans three or more floor
    -- maps (the dept store, Silph Co, the tower, the mansion) marks its
    -- building's solid footprint as a no-fly wall.  Anything smaller
    -- stays fly-over, and modded towers qualify automatically.
    local function floorFamilySize(destId)
      if type(destId) ~= "string" then return 0 end
      local base = destId:gsub("_B?%d+F$", ""):gsub("_ROOF$", "")
      if base == destId then return 1 end
      -- caves are terrain, not towers: Seafoam or Victory Road go deep
      -- and stay flyable no matter how many maps they span
      local destDef = Game.data.maps[destId]
      if destDef and destDef.tileset == "CAVERN" then return 1 end
      -- only floors ABOVE ground make a building tall; basements don't
      local n = 0
      for id in pairs(Game.data.maps) do
        if (id == base or id:find("^" .. base .. "_"))
           and not id:find("_B%d+F$") then
          n = n + 1
        end
      end
      return n
    end

    local function landmarkCellsFor(ow)
      local map = ow.map
      local w = map.widthCells or ((map.def and map.def.width or 0) * 2)
      local cells = {}
      -- four or more floors above ground is a tower (dept store, Silph,
      -- Pokemon Tower, Celadon Mansion).  Three is a big house whose
      -- small drawn exterior stays fly-over: Cinnabar's mansion.
      for _, warp in ipairs((map.def and map.def.warps) or {}) do
        if floorFamilySize(warp.destMap) >= 4 then
          -- flood the solid footprint starting above the door, bounded
          -- so it can never wander off into the border-tree ring
          -- the footprint floods through BUILDING cells only.  In the
          -- shape profile, building walls are "upright"; trees are
          -- "cylinder", fences "post", signs "billboard" (measured over
          -- Saffron), so those never chain the wall into a neighbour.
          local function buildingCell(cx, cy)
            if not map:inBounds(cx, cy) or map:isWalkableCell(cx, cy) then
              return false
            end
            local art = tileArtAt(map, cx, cy)
            return art == nil or art == "upright"
          end
          local queue = { { warp.x, warp.y - 1 } }
          local seen, budget = {}, 400
          while #queue > 0 and budget > 0 do
            local cell = table.remove(queue)
            local cx, cy = cell[1], cell[2]
            local key = cy * w + cx
            local dx, dy = cx - warp.x, cy - warp.y
            -- generous bounds: the fence exclusion is what stops spill
            -- into neighbours, so the box only needs to contain the
            -- biggest tower (Silph) in every direction from its door
            if not seen[key]
               and math.abs(dx) <= 12 and dy >= -12 and dy <= 1
               and buildingCell(cx, cy) then
              seen[key] = true
              cells[key] = true
              budget = budget - 1
              queue[#queue + 1] = { cx + 1, cy }
              queue[#queue + 1] = { cx - 1, cy }
              queue[#queue + 1] = { cx, cy + 1 }
              queue[#queue + 1] = { cx, cy - 1 }
            end
          end

          -- seal enclosed walkable pockets (the dept store's rooftop
          -- plaza): walkable cells inside the footprint's box that can't
          -- be walked into from the box border are part of the building
          -- while airborne.  Streets crossing near the complex reach the
          -- border and are never touched.
          local minx, maxx = warp.x - 12, warp.x + 12
          local miny, maxy = warp.y - 12, warp.y + 1
          local open, oq = {}, {}
          local function seed(cx, cy)
            local key = cy * w + cx
            if not open[key] and map:inBounds(cx, cy)
               and map:isWalkableCell(cx, cy) then
              open[key] = true
              oq[#oq + 1] = { cx, cy }
            end
          end
          for cx = minx, maxx do seed(cx, miny); seed(cx, maxy) end
          for cy = miny, maxy do seed(minx, cy); seed(maxx, cy) end
          while #oq > 0 do
            local c = table.remove(oq)
            local cx, cy = c[1], c[2]
            for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
              local nx, ny = cx + d[1], cy + d[2]
              if nx >= minx and nx <= maxx and ny >= miny and ny <= maxy then
                seed(nx, ny)
              end
            end
          end
          for cy = miny, maxy do
            for cx = minx, maxx do
              local key = cy * w + cx
              if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
                 and not open[key] then
                cells[key] = true
              end
            end
          end
        end
      end
      return { mapId = map.id, w = w, cells = cells }
    end

    local DIRV = { up = { 0, -1 }, down = { 0, 1 },
                   left = { -1, 0 }, right = { 1, 0 } }

    local function aheadCell(p)
      local d = DIRV[p.facing] or DIRV.down
      return p.cellX + d[1], p.cellY + d[2]
    end

    local function surfAllowed(ow)
      if Sky.goldWorld(ow) then
        -- Gold: the engine's own move user, gated on Morty's FOGBADGE
        -- the way its field moves gate SURF
        local knows = partyKnowsSurf(Game.save)
          or (ow.partyMoveUser ~= nil and ow:partyMoveUser("SURF") ~= nil)
        if not knows then return false end
        if not mod.options:get("badges") then return true end
        local ok, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
        return (ok and FieldMoves and FieldMoves.hasBadge
          and FieldMoves.hasBadge(Game.save, "FOG")) == true
      end
      return (fieldMoveUser(ow, "SURF") ~= nil or partyKnowsSurf(Game.save))
        and (not mod.options:get("badges")
             or (Game.save.inventory and Game.save.inventory.SOULBADGE))
    end

    -- safe for an auto-glide step to pass over: in bounds, no sealed
    -- tower facade, no doormat to hover on
    local function glideOk(ow, cx, cy)
      local map = ow.map
      local lm = state.landmark
      if not map:inBounds(cx, cy) then return false end
      if lm and lm.mapId == map.id and lm.cells[cy * lm.w + cx] then
        return false
      end
      if map:warpAtCell(cx, cy) then return false end
      return true
    end

    local function landableCell(ow, p, cx, cy, allowWater)
      local map = ow.map
      if not glideOk(ow, cx, cy)
         or Collision.occupied(ow.entities, cx, cy, p) then
        return nil
      end
      if map:isWalkableCell(cx, cy) then return "ground" end
      if allowWater and map:isWaterCell(cx, cy) then return "water" end
      return nil
    end

    -- Assisted landing: breadth-first from the rider over flyable cells
    -- (anything in bounds that isn't a sealed tower facade) to the
    -- nearest cell you could set down on.  Dry land wins over water,
    -- doormats and occupied cells are skipped, and south is tried first
    -- so hovering over a building tends to land at its entrance.
    local APPROACH_RANGE = 12
    local APPROACH_DIRS = { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }

    local function findLandingPath(ow, p)
      local map = ow.map
      local lm = state.landmark
      local w = map.widthCells
      local function facade(cx, cy)
        return lm and lm.mapId == map.id and lm.cells[cy * lm.w + cx]
      end
      local allowWater = surfAllowed(ow)
      local function landable(cx, cy)
        return landableCell(ow, p, cx, cy, allowWater)
      end
      local sx, sy = p.cellX, p.cellY
      local startKey = sy * w + sx
      local seen, parent = { [startKey] = true }, {}
      local queue, qi = { { sx, sy, 0 } }, 1
      local function pathTo(key)
        local path = {}
        while key and key ~= startKey do
          table.insert(path, 1, { key % w, math.floor(key / w) })
          key = parent[key]
        end
        return path[1] and path or nil
      end
      local waterKey
      while queue[qi] do
        local cx, cy, depth = queue[qi][1], queue[qi][2], queue[qi][3]
        qi = qi + 1
        if depth > 0 then
          local kind = landable(cx, cy)
          if kind == "ground" then return pathTo(cy * w + cx) end
          if kind == "water" and not waterKey then waterKey = cy * w + cx end
        end
        if depth < APPROACH_RANGE then
          for _, d in ipairs(APPROACH_DIRS) do
            local nx, ny = cx + d[1], cy + d[2]
            local key = ny * w + nx
            if not seen[key] and map:inBounds(nx, ny)
               and not facade(nx, ny) then
              seen[key] = true
              parent[key] = cy * w + cx
              queue[#queue + 1] = { nx, ny, depth + 1 }
            end
          end
        end
      end
      return waterKey and pathTo(waterKey) or nil
    end

    -- wilds of kanto walks party mons behind the player through its own
    -- update wrap, so the PF gate never sees those followers.  Its
    -- per-mon "stay" flag is a data seam every one of its follower
    -- shapes honours (trailer packs and the stock single follower
    -- alike): while airborne, ground-bound mons and the mount itself
    -- stay put.  Only mons this mod flagged are released on landing, so
    -- a player's own STAY choices survive the flight.
    -- a follower mod that declares exports.freeFlyAware = true handles
    -- flight itself (watching the mod.free_fly.takeoff and landed
    -- events, or the isFlying/altitude exports); every follower hand
    -- of ours stays off while any such mod is loaded
    local function followerModAware()
      local declared = Game.mods and Game.mods.exports
      if not declared then return false end
      for _, ex in pairs(declared) do
        if type(ex) == "table" and ex.freeFlyAware == true then
          return true
        end
      end
      return false
    end

    -- while the trail flies, the foreign engine's ground rules would
    -- still pin it: fences, ledges and water reject its step goals, so
    -- an airborne trailer snags on scenery.  Its pathing has a single
    -- cell gate; wrap it once (installed lazily, gated on flight, never
    -- removed, per our own INTEGRATION.md rules) so a mon trailer may
    -- take any in-bounds cell while airborne.  The trainer trailer is
    -- a person and keeps walking by the ground rules.
    local function wildsEngine()
      local wilds = mod.find("overworld_wild_spawns")
      local follower = wilds and wilds.exports and wilds.exports.follower
      return follower and follower.control or nil
    end
    local function openWildsSkyLanes()
      local engine = wildsEngine()
      if not engine or engine.__freeFlySkyLanes
         or type(engine.isFollowerCellAllowed) ~= "function" then
        return
      end
      engine.__freeFlySkyLanes = true
      local origAllowed = engine.isFollowerCellAllowed
      engine.isFollowerCellAllowed = function(self, game, ow, entity, x, y, context)
        if flying() and ow and ow.map and ow.map:inBounds(x, y) then
          local role = (context and context.role)
            or (entity and entity.pokepcTrailerKind == "trainer"
                and "trainer_trailer")
          if role ~= "trainer_trailer" then return true end
        end
        return origAllowed(self, game, ow, entity, x, y, context)
      end
    end

    local wildsGrounded = {}
    local trailersFlown = false
    local function syncWildsFollowers(airborne)
      local party = Game.save and Game.save.party or {}
      if airborne then
        for _, mon in ipairs(party) do
          if not mon.stopFollowing
             and (mon == state.mountMon
                  or not Sky.hasType(Game.data, mon.species, "FLYING")) then
            mon.stopFollowing = true
            wildsGrounded[mon] = true
          end
        end
        return
      end
      for mon in pairs(wildsGrounded) do
        mon.stopFollowing = nil
        wildsGrounded[mon] = nil
      end
    end

    OC.__freeFlyTick = function(ow, dt)
      -- the shared wrap is mid-frame through an older leftover wrap:
      -- the outermost runs this tick once when the frame unwinds
      if OC.__skyTicking then return end
      -- the follower gate on PF.update gets clobbered by the same
      -- foreign restores as OC.update; re-arm it from here, since this
      -- tick itself rides the healed wrap
      local PFmod = package.loaded["src.world.PikachuFollower"]
      local ensurePF = PFmod and PFmod.__freeFlyEnsureWrap
      if ensurePF then ensurePF() end
      local p = ow.player
      if not p then return end
      if ow.map and (not state.landmark
                     or state.landmark.mapId ~= ow.map.id
                     or state.landmark.retry) then
        local ok, lm = pcall(landmarkCellsFor, ow)
        -- never cache a failed scan for the whole visit: a landmark
        -- computed on a bad frame (mid-transition) would silently strip
        -- the tower facades and let landings drop through roofs
        state.landmark = ok and lm
          or { mapId = ow.map.id, w = 1, cells = {}, retry = true }
      end
      if not flying() then
        if p.freeFlyAlt then p.freeFlyAlt, p.freeFlying = nil, nil end
        p._stadiumSkyRideLift = nil
        if Sky.goldWorld(ow) and ow.camera then
          ow.camera.__freeFlyLift = 0
        end
        if p.freeFlyWalkSprite then
          p.sprite, p.freeFlyWalkSprite = p.freeFlyWalkSprite, nil
        end
        if state.placedCam and state.v3dRef
           and state.v3dRef.camera == state.placedCam then
          state.v3dRef.camera = nil
        end
        dropRider(ow)
        syncWildsFollowers(false)
        local ground = PFmod and PFmod.__freeFlyGround
        if ground and type(ow.pokepcTrailers) == "table" then
          for _, npc in ipairs(ow.pokepcTrailers) do
            if npc then ground(npc) end
          end
        end
        -- a trailer that landed mid-fence (its sky lane closed under
        -- it) is stranded by ground rules; let the engine notice and
        -- reseed the trail behind the player
        if trailersFlown then
          trailersFlown = false
          local engine = wildsEngine()
          if engine and type(ow.pokepcTrailers) == "table" then
            for _, npc in ipairs(ow.pokepcTrailers) do
              local okCell = true
              pcall(function()
                okCell = engine:isFollowerCellAllowed(Game, ow, npc,
                  npc.cellX, npc.cellY, {}) ~= false
              end)
              if not okCell then
                pcall(function() engine:removeTrailers(ow) end)
                break
              end
            end
          end
        end
        return
      end
      p.freeFlying = true
      if not followerModAware() then
        syncWildsFollowers(true)
        -- the FLYING-type trailers still walking below get the same air
        -- dress as the engine follower, at the player's own altitude.
        -- This runs after the foreign engine's frame (this tick is the
        -- outermost layer), so its land and swim sprite swaps lose to
        -- the flying sheet every frame, sea included.
        openWildsSkyLanes()
        local dress = PFmod and PFmod.__freeFlyDress
        if dress and type(ow.pokepcTrailers) == "table" then
          for _, npc in ipairs(ow.pokepcTrailers) do
            local species = npc and npc.pokepcMon and npc.pokepcMon.species
            if species then
              dress(npc, Game, species, state.alt)
              trailersFlown = true
            end
          end
        end
      end
      -- Gold re-follows the player's ground anchor every draw and has
      -- no Renderer camera seam, but its camera is a live instance:
      -- follow() wraps once per camera and reads the lift each call,
      -- so the view tracks the airborne mount instead of pinning it
      -- to the top edge.
      if Sky.goldWorld(ow) and ow.camera then
        local cam = ow.camera
        if not cam.__freeFlyWrapped then
          cam.__freeFlyWrapped = true
          local origFollow = cam.follow
          cam.follow = function(self2, x, y, vw, vh)
            return origFollow(self2, x,
              y - (self2.__freeFlyLift or 0), vw, vh)
          end
        end
        cam.__freeFlyLift = state.alt
      end

      -- Gold's engine follower is not flight-aware.  A companion that
      -- can fly trails through the air in its own species' art at the
      -- player's altitude; one that cannot sits the flight out.  Its
      -- engine re-adds it every frame and this tick runs after that,
      -- so the removal holds for the drawn frame; landing re-places it
      -- through the engine's own map-entry path.
      if Sky.goldWorld(ow) then
        local okF, Follower = pcall(require, "src.world.gen2.Follower")
        local fnpc = okF and Follower and Follower.current
          and Follower.current(ow) or nil
        if fnpc then
          local lead = Game.save and Game.save.party
            and Game.save.party[1] or nil
          if lead and Sky.hasType(Game.data, lead.species, "FLYING") then
            if state.goldFollowerSpecies ~= lead.species then
              state.goldFollowerSpecies = lead.species
              local sprite = Sky.mountSprite(Game.data, lead.species,
                "free_fly_follower")
              -- only a stock-shaped renderer: a pic renderer's own
              -- draw speaks the Gen 1 signature Gold's Npc never uses
              state.goldFollowerSprite =
                (sprite and rawget(sprite, "draw") == nil) and sprite
                or nil
            end
            if state.goldFollowerSprite then
              fnpc.sprite = state.goldFollowerSprite
            end
            if not fnpc.__freeFlyGoldDress then
              fnpc.__freeFlyGoldDress = true
              local origDraw = fnpc.draw
              fnpc.draw = function(self2, ox, oy, sc)
                local lift = (self2.__freeFlyLift or 0) * (sc or 1)
                return origDraw(self2, ox, oy - lift, sc)
              end
            end
            fnpc.__freeFlyLift = state.alt
          else
            for i = #(ow.npcs or {}), 1, -1 do
              if ow.npcs[i] == fnpc then table.remove(ow.npcs, i) end
            end
            for i = #(ow.entities or {}), 1, -1 do
              if ow.entities[i] == fnpc then
                table.remove(ow.entities, i)
              end
            end
          end
        end
      end

      -- the mount IS the player's sheet while airborne, so every renderer
      -- (voxel first/third person frame remaps included) shows it; the
      -- walking sheet is stashed for the rider overlay and the landing
      local mount = Player.__freeFlyMount or Player.__freeFlyBird
      if mount and p.sprite ~= mount then
        p.freeFlyWalkSprite = p.freeFlyWalkSprite or p.sprite
        p.sprite = mount
      end
      syncRider(ow, p)
      -- wings work harder in transitions than on the cruise, same as
      -- the wild flyers' flap profiles; big mounts beat slower
      p.freeFlyFlapRate = (state.phase == "flying" and 8 or 12)
        / math.max(1, Player.__freeFlyMountScale or 1)
      dt = dt or 1 / 60
      local groundOk = ow.map:isWalkableCell(p.cellX, p.cellY)
      -- SURF availability goes through the same engine chain, so
      -- HM-relaxing mods unlock water landings exactly as they unlock
      -- the SURF field move itself
      local waterOk = not groundOk and ow.map:isWaterCell(p.cellX, p.cellY)
        and surfAllowed(ow)
      local canLand = not p.moving and (groundOk or waterOk)
        and not Collision.occupied(ow.entities, p.cellX, p.cellY, p)
      p.freeFlyCanLand = state.phase == "flying" and canLand or false

      if state.phase == "rising" then
        local cruise = cruiseAlt()
        state.alt = math.min(cruise, state.alt + RISE_SPEED * dt)
        -- diagonal climb, like the wild flyers: a short forward drift,
        -- dropped the moment the player steers or anything's in the way
        local steering = Game.input:isDown("up") or Game.input:isDown("down")
          or Game.input:isDown("left") or Game.input:isDown("right")
        if steering then state.riseGlide = 0 end
        if (state.riseGlide or 0) > 0 and not p.moving then
          local cx, cy = aheadCell(p)
          if glideOk(ow, cx, cy) then
            local result = p:tryMove(p.facing, ow.map, ow.entities)
            if result == "moved" then
              state.riseGlide = state.riseGlide - 1
            elseif result == "blocked" then
              state.riseGlide = 0
            end
          else
            state.riseGlide = 0
          end
        end
        if state.alt >= cruise then state.phase = "flying" end
      elseif state.phase == "landing" then
        -- the last pixel waits for the step to finish, so a swoop skims
        -- the ground on its final cell instead of dismounting mid-step
        state.alt = math.max(p.moving and 1 or 0,
                             state.alt - RISE_SPEED * dt)
        -- swoop: a land press on the wing keeps the heading for a
        -- couple of cells on the way down, like the wild flyers' glide
        -- in to a perch
        if (state.glide or 0) > 0 and state.alt > 20 and not p.moving then
          local cx, cy = aheadCell(p)
          if landableCell(ow, p, cx, cy, surfAllowed(ow)) then
            local result = p:tryMove(p.facing, ow.map, ow.entities)
            if result == "moved" then
              state.glide = state.glide - 1
            elseif result == "blocked" then
              state.glide = 0
            end
          else
            state.glide = 0
          end
        end
        if state.alt <= 0 and not p.moving then
          local landableHere = (ow.map:isWalkableCell(p.cellX, p.cellY)
                                or ow.map:isWaterCell(p.cellX, p.cellY))
            and not Collision.occupied(ow.entities, p.cellX, p.cellY, p)
          if not landableHere then
            -- the ground can change under a swoop (an NPC wanders in);
            -- pull up and hand back rather than landing on them
            state.phase = "flying"
          else
            state.phase = "idle"
            -- setting down on water hands you straight to a SURF-knower
            local wetLanding = ow.map:isWaterCell(p.cellX, p.cellY)
            if wetLanding then
              if Sky.goldWorld(ow) then
                -- the same state change Gold's own SurfStartStep runs
                local okFM, FieldMoves = pcall(require,
                  "src.world.gen2.FieldMoves")
                local surfer = ow.partyMoveUser
                  and ow:partyMoveUser("SURF") or nil
                if okFM and FieldMoves and ow.applyPlayerState then
                  pcall(ow.applyPlayerState, ow,
                    FieldMoves.surfType(surfer))
                end
              else
                p.surfing = true
              end
              mod.log:info("landed on the water; surfing")
            else
              mod.log:info("landed")
            end
            p.freeFlying, p.freeFlyAlt, p.freeFlyCanLand = nil, nil, nil
            p._stadiumSkyRideLift = nil
            if p.freeFlyWalkSprite then
              p.sprite, p.freeFlyWalkSprite = p.freeFlyWalkSprite, nil
            end
            rebuildConvoyAfterLanding(Game, ow, function()
              syncWildsFollowers(false)
            end)
            emitLanded("landed", p, wetLanding)
            return
          end
        end
      elseif state.phase == "flying" then
        -- an ALTITUDE option change applies mid-flight
        state.alt = state.alt + (cruiseAlt() - state.alt) * math.min(1, dt * 2)

        if Game.input:wasPressed("b") or state.landRequest then
          state.landRequest = nil
          if canLand then
            state.phase, state.glide = "landing", 0
          elseif p.moving and p.targetX
                 and landableCell(ow, p, p.targetX, p.targetY,
                                  surfAllowed(ow)) then
            -- pressed on the wing over good ground: swoop in along the
            -- current heading instead of stopping dead
            state.phase, state.glide = "landing", 2
          else
            -- assisted landing: glide to the nearest landable cell (in
            -- front of the building you're hovering over) and set down
            local path = findLandingPath(ow, p)
            if path then
              state.phase = "approach"
              state.approachPath = path
              mod.log:info("gliding to a landing spot")
            else
              pcall(function()
                require("src.core.Sound").play(Game.data, "Collision")
              end)
              mod.log:info("nowhere to land nearby")
            end
          end
        end

        -- aerial interception: brushing a wild_skies flyer starts that
        -- exact battle, through its exports rather than its internals
        if (state.interceptCooldown or 0) > 0 then
          state.interceptCooldown = state.interceptCooldown - dt
        elseif mod.options:get("encounters") then
          if state.skiesTake == nil then
            local skies = mod.find("wild_skies")
            state.skiesTake = (skies and skies.exports
                               and skies.exports.takeFlyer) or false
          end
          local take = state.skiesTake
          if take then
            local ok, hit = pcall(take, p.cellX, p.cellY, 1)
            if ok and hit and hit.species then
              state.interceptCooldown = 2
              state.expectBattle = 4
              pcall(function()
                require("src.core.Sound").playCry(Game.data, hit.species)
              end)
              mod.log:info("intercepted %s!", tostring(hit.species))
              -- the flock partner source keys off this record: the
              -- battle about to start may recruit a second bird
              state.lastIntercept = { species = hit.species,
                                      at = love.timer.getTime() }
              local db = mod.find("double_battles")
              if db and db.exports and db.exports.tagOrganic then
                pcall(db.exports.tagOrganic)
              end
              mod.world:queueScript({
                { "start_battle", "wild", hit.species, hit.level or 5 },
              })
            end
          end
        end
      elseif state.phase == "approach" then
        state.alt = state.alt + (cruiseAlt() - state.alt) * math.min(1, dt * 2)
        -- the glide is autopilot, so ANY steering or another land press
        -- hands control straight back
        local steering = Game.input:isDown("up") or Game.input:isDown("down")
          or Game.input:isDown("left") or Game.input:isDown("right")
        local cancel = steering or Game.input:wasPressed("b")
          or state.landRequest
        state.landRequest = nil
        if cancel or not state.approachPath then
          state.phase, state.approachPath = "flying", nil
        elseif not p.moving then
          local nextCell = state.approachPath[1]
          if not nextCell then
            state.approachPath = nil
            -- recheck on arrival: an NPC may have wandered onto the spot
            state.phase = canLand and "landing" or "flying"
            state.glide = 0
          else
            local dir
            if nextCell[1] > p.cellX then dir = "right"
            elseif nextCell[1] < p.cellX then dir = "left"
            elseif nextCell[2] > p.cellY then dir = "down"
            elseif nextCell[2] < p.cellY then dir = "up" end
            if not dir then
              table.remove(state.approachPath, 1)
            else
              local result = p:tryMove(dir, ow.map, ow.entities)
              if result == "moved" then
                table.remove(state.approachPath, 1)
              elseif result == "blocked" then
                state.phase, state.approachPath = "flying", nil
              end
            end
          end
        end
      end
      tickPrefetch()
      state.expectBattle = (state.expectBattle and state.expectBattle > dt)
        and (state.expectBattle - dt) or nil
      state.windCooldown = math.max(0, (state.windCooldown or 0) - dt)
      -- TURN BACK is never remembered: once this expires the next push
      -- into the seam asks again, until the player says CROSS
      state.askCooldown = math.max(0, (state.askCooldown or 0) - dt)
      state.bob = (state.bob + dt * 4) % (2 * math.pi)
      -- mount attitude: heading from the facing, altitude from the
      -- flight state; the shared math does the leaning
      local HEADINGS = { right = 0, down = math.pi / 2,
                         left = math.pi, up = -math.pi / 2 }
      state.motion = state.motion or { flap = 8 }
      state.motion.heading = HEADINGS[p.facing] or 0
      state.motion.alt = state.alt
      state.motion.facing = p.facing
      state.motion.mode = flying() and "roam" or "ground"
      state.motion.t = (state.motion.t or 0) + dt
      Sky.flightAttitude(state.motion, dt)
      local hover = state.phase == "flying" and math.sin(state.bob) * 2 or 0
      -- altitude is absolute: the voxel scene adds the ground height back
      -- under the card, so standing geometry eats into the visual lift
      -- instead of stacking on top of it (min 10 keeps clearance)
      local lift = state.alt + hover
      local gh, voxelOn = voxelGroundHeight(ow, p)
      local camLift
      if voxelOn then
        -- constant 52px TOTAL ride: the scene's building volumes cap at
        -- 48px from the ground plane (their mesher's MAX_ROWS), so this
        -- clears every small building everywhere with no climbs at all.
        -- The per-cell gh subtraction stays INSTANT, which is what keeps
        -- fences from reading as hops.  Towers are facade-blocked.
        local total = math.max(lift * 0.75, 52)
        -- takeoff and landing ramp the constant ride in and out, so the
        -- voxel mount climbs and descends like the wild flyers instead
        -- of popping to cruise height (mid-flight ALTITUDE lerps are
        -- exempt or they'd read as a dive)
        if state.phase == "rising" or state.phase == "landing" then
          total = total * math.min(1, state.alt / math.max(1, cruiseAlt()))
        end
        p.freeFlyAlt = math.max(0, total - gh)
        -- the camera follows the constant TOTAL, never the varying
        -- per-cell part: roofs mix zero-height flat-class cells into
        -- their upper rows, and a camera tracking freeFlyAlt lurched
        -- there while the card itself stayed level.  The follow factor
        -- scales with the rung's PITCH, read live from the voxel mod's
        -- own angle table (the ladder is OFF/FULL/15/35/50/75/1ST/3RD).
        -- The engine camera is a GROUND-PLANE point, so it can express
        -- forward but never height; the 75-degree orbit gets its height
        -- through the scene's placed-camera seam below instead.
        local FOLLOW_BY_DEG = { [15] = 0.65, [35] = 0.65,
                                [50] = 0.78, [75] = 0.65 }
        local rung = Pipelines.level("voxel") or 0
        if state.voxelStateRef == nil then
          state.voxelStateRef = false
          local V = voxelLib(Game)
          local okV, vs = pcall(function()
            return V and V.require("VoxelState")
          end)
          if okV and vs and vs.ANGLES_DEG then state.voxelStateRef = vs end
        end
        local deg = state.voxelStateRef
          and state.voxelStateRef.ANGLES_DEG[rung + 1] or 0
        camLift = total * (FOLLOW_BY_DEG[deg] or 0.65)
        state.placeWanted = deg == 75
          and not (state.voxelStateRef.isFirstPerson
                   and state.voxelStateRef.isFirstPerson(rung))
          and not (state.voxelStateRef.isThirdPerson
                   and state.voxelStateRef.isThirdPerson(rung))
        state.placeHeight = (p.freeFlyAlt or 0) + gh
      else
        -- 2D flies steady: a 2px integer-quantized hover reads as
        -- jitter, and the wing flap already carries the life
        p.freeFlyAlt = state.alt
        camLift = state.alt
      end
      if not Sky.goldWorld(ow) then
        ow.camera:follow(p.px, p.py - camLift,
                         Game.renderer:worldViewSize())
      end
      -- Stadium 2's Gold voxel worlds read this render-only lift for
      -- non-mount airborne entities; harmless everywhere else
      p._stadiumSkyRideLift = (p.freeFlyAlt or 0) > 0
        and p.freeFlyAlt or nil
      -- the 75-degree orbit, lifted to the rider through the scene's
      -- placed-camera seam (the battle-camera mechanism): same centre,
      -- same pitch, same fov, focus raised to flight height.  Never
      -- touches a camera someone else placed (battles, first person).
      local vsRef = state.voxelStateRef
      if state.v3dRef == nil then
        state.v3dRef = false
        local V = voxelLib(Game)
        local okV3, v3 = pcall(function()
          return V and V.require("Voxel3D")
        end)
        if okV3 and v3 then state.v3dRef = v3 end
      end
      local V3 = state.v3dRef
      if state.placeWanted and vsRef and V3
         and (V3.camera == nil or V3.camera == state.placedCam) then
        local ok = pcall(function()
          local vw, vh = Game.renderer:worldViewSize()
          local ccx = ow.camera.x + vw / 2
          local ccy = ow.camera.y + vh / 2
          local a = vsRef.angle or math.rad(75)
          local focal = vsRef.FOCAL or 1.2
          local distC = focal * vh
          local L = state.placeHeight or 0
          local cam = state.placedCam or {}
          cam.fov = 2 * math.atan(1 / (2 * focal))
          cam.focus = { ccx, L, ccy }
          cam.eye = { ccx, L + distC * math.cos(a), ccy + distC * math.sin(a) }
          cam.up = { 0, math.sin(a), -math.cos(a) }
          state.placedCam = cam
          V3.camera = cam
        end)
        if not ok then state.placeWanted = false end
      elseif not state.placeWanted and V3 and state.placedCam
             and V3.camera == state.placedCam then
        V3.camera = nil
      end
    end

    -- the shared self-healing wrap: survives wilds of kanto's follower
    -- engine restoring OC.update from a pre-wrap snapshot, and shares
    -- one tag with wild_skies so the two watchdogs never fight
    Sky.ensureUpdateWrap(OC, "__freeFlyTick", mod.hooks)

    if not OC.__freeFlyWrapped then
      OC.__freeFlyWrapped = true

      -- doors and edge warps must not swallow a bird passing over them
      local origTakeWarp = OC.takeWarp
      OC.takeWarp = function(self, ...)
        if self.player and self.player.freeFlying then return end
        return origTakeWarp(self, ...)
      end

      -- trainers don't spot what flies over their head (unless the
      -- hardcore option says they do); the gate is swappable so hot
      -- reload always runs the latest logic
      local origSight = OC.checkTrainerSight
      OC.checkTrainerSight = function(self, ...)
        local gate = OC.__freeFlySightGate
        if gate and gate(self) then return end
        return origSight(self, ...)
      end
    end

    OC.__freeFlySightGate = function(ow)
      local p = ow.player
      return p and p.freeFlying and not mod.options:get("spotted")
    end

    if goldBoot then
      local okW, World2 = pcall(require, "src.world.gen2.World")
      if okW and World2 and not World2.__freeFlyMoveWrapped then
        World2.__freeFlyMoveWrapped = true
        local origWarp = World2.takeWarp
        World2.takeWarp = function(self, ...)
          if self.player and self.player.freeFlying then return end
          return origWarp(self, ...)
        end
        local origSight = World2.checkTrainerBattle
        World2.checkTrainerBattle = function(self, ...)
          if self.player and self.player.freeFlying
             and not mod.options:get("spotted") then
            return
          end
          return origSight(self, ...)
        end
        local origLedge = World2.tryLedgeJump
        World2.tryLedgeJump = function(self, ...)
          if self.player and self.player.freeFlying then return false end
          return origLedge(self, ...)
        end
        local origCarpet = World2.checkCarpetWhileStanding
        World2.checkCarpetWhileStanding = function(self, ...)
          if self.player and self.player.freeFlying then return false end
          return origCarpet(self, ...)
        end
        -- seams: tryConnection validates the landing tile with
        -- destMap:isWalkable, outside the movement.collision hook, so
        -- an airborne crossing only worked where a walker could cross.
        -- While flying the check runs in a permissive window (the same
        -- pattern the Gen 1 FreeMove wrap uses): any in-bounds strip
        -- tile carries a flyer, trees and sea included.
        local origTry = World2.tryConnection
        World2.tryConnection = function(self, dir)
          local gate = World2.__freeFlySeamGate
          if not (gate and gate(self)) then return origTry(self, dir) end
          local okM, Map2 = pcall(require, "src.world.gen2.Map")
          if not (okM and Map2 and Map2.isWalkable) then
            return origTry(self, dir)
          end
          local orig = Map2.isWalkable
          Map2.isWalkable = function(m, x, y) return m:inBounds(x, y) end
          local ok, crossed = pcall(origTry, self, dir)
          Map2.isWalkable = orig
          if not ok then error(crossed, 0) end
          return crossed
        end
      end
      if okW and World2 then
        -- outside the once-guard, so a hot reload swaps the gate
        World2.__freeFlySeamGate = function(world)
          return world.player ~= nil and world.player.freeFlying == true
        end
      end
      -- the facade's talkTo seam: Gold consults it before its script
      -- arms, which is what makes a script-less gift NPC answerable.
      -- A false return falls through to the normal dispatch.
      if not OC.__freeFlyTalkWrapped then
        OC.__freeFlyTalkWrapped = true
        local prev = OC.talkTo
        OC.talkTo = function(owT, npc)
          local gate = OC.__freeFlyGiftTalk
          if gate then
            local ok, handled = pcall(gate, owT, npc)
            if ok and handled then return true end
          end
          if type(prev) == "function" then return prev(owT, npc) end
          return false
        end
      end
      OC.__freeFlyGiftTalk = goldGiftCeremony
    end

    local function dangerAllowed(mapId)
      local ok = mod.save:get("dangerOk")
      return type(ok) == "table" and ok[mapId] == true
    end

    -- the seams that count as setting out to sea, listed explicitly
    -- ("from>to").  Just the classic departure for now; Cinnabar's and
    -- Fuchsia's coasts are candidates once this one feels right.
    local SEA_SEAMS = {
      ["PALLET_TOWN>ROUTE_21"] = true,
    }

    -- leaving the coast for open sea: confirm once per map, per save.
    -- \v scrolls the third line in, \f page-breaks before the mount's
    -- moment; names stay inside the 18-column box (10-char cap + 7)
    local function dangerAsk(destMapId)
      if (state.askCooldown or 0) > 0 then return end
      state.askCooldown = 2
      local name = Sky.monName(Game.data, state.mountMon)
      mod.world:queueScript({
        { "show_text", "You usually need\nthe SOULBADGE to\vcross here...\fBut "
            .. name .. " is\nfeeling brave!" },
        { "choice", { "CROSS", "TURN BACK" } },
        { "jump_if_false", "no" },
        { "free_fly:allow_crossing", destMapId },
        { "show_text", "You brace against\nthe sea wind!" },
        { "jump", "end" },
        { "label", "no" },
        { "show_text", "You circle back." },
      })
    end

    -- story gates and the sea-crossing confirm share the seam chokepoint.
    -- v2 guard flag: the 0.7.0 wrapper did not pass `dir`, so a hot reload
    -- from it installs this one and retires the old gate key.
    if not OC.__freeFlyCrossWrapped3 then
      OC.__freeFlyCrossWrapped3 = true
      local origCross = OC.crossConnection
      OC.crossConnection = function(self, dir, conn)
        local gate = OC.__freeFlyCrossGate2
        if gate and conn and gate(self, dir, conn.map) then return false end
        local crossed = origCross(self, dir, conn)
        local after = OC.__freeFlyCrossAfter
        if crossed and after then after(self) end
        return crossed
      end
    end
    OC.__freeFlyCrossGate = nil

    -- the seam step crossConnection kicks off bypasses tryMove, so it
    -- would run at walking pace mid-flight (a visible hitch at every
    -- seam); the rider ghost also needs re-attaching the same frame the
    -- entity list is rebuilt, not a tick later
    OC.__freeFlyCrossAfter = function(ow)
      local p = ow.player
      if not (p and p.freeFlying) then return end
      p.stepFramesCur = flyFrames()
      if state.rider then
        state.rider.px, state.rider.py = p.px, p.py
        state.rider.cellX, state.rider.cellY = p.cellX, p.cellY
        table.insert(ow.entities, state.rider)
      end
    end

    -- forced-movement tiles (Cycling Road's mount-or-refuse, forced surf
    -- currents) don't grab what flies over them; landing brings the
    -- vanilla check straight back.  Own guard flag so a hot reload from
    -- an older version still installs it.
    if not OC.__freeFlyForcedWrapped then
      OC.__freeFlyForcedWrapped = true
      local origForced = OC.checkForcedMovement
      OC.checkForcedMovement = function(self, ...)
        if self.player and self.player.freeFlying then return false end
        return origForced(self, ...)
      end
    end

    -- other mods (overworld_encounters' ground roamers above all) start
    -- wild battles by ground-cell collision and know nothing about
    -- altitude.  While airborne, the only wild battle allowed to start is
    -- one this mod just asked for (interception); everything else is a
    -- ground creature the flyer passes over.
    if goldBoot then
      -- Gold constructs and pushes a battle in one call; gate the
      -- World class itself, wild battles only, and answer the way its
      -- own no-stack refusal does
      local okW, World2 = pcall(require, "src.world.gen2.World")
      if okW and World2 then
        if not World2.__freeFlyWildWrapped then
          World2.__freeFlyWildWrapped = true
          local origStart = World2.startBattle
          World2.startBattle = function(self, opts, onDone)
            local gate = World2.__freeFlyWildGate
            if gate and gate(opts) then
              if onDone then onDone("win") end
              return false
            end
            return origStart(self, opts, onDone)
          end
        end
        World2.__freeFlyWildGate = function(opts)
          return flying() and not state.expectBattle
            and type(opts) == "table" and opts.wild ~= nil
            and opts.trainer == nil
        end
      end
    else
      local installWildGate = function(BS)
        if not BS.__freeFlyWrapped then
          BS.__freeFlyWrapped = true
          local origNewWild = BS.newWild
          BS.newWild = function(...)
            local gate = BS.__freeFlyGate
            if gate and gate() then return nil end
            return origNewWild(...)
          end
        end
        BS.__freeFlyGate = function()
          return flying() and not state.expectBattle
        end
      end
      installWildGate(require("src.battle.BattleState"))
    end

    mod.events:on("battle.started", function()
      state.expectBattle = nil
    end)

    -- neutralize stale border wraps from a hot reload of the previous
    -- build; the border draws normally everywhere again
    local TileRenderer = require("src.render.TileRenderer")
    TileRenderer.__freeFlySkip = nil
    pcall(function()
      local V = voxelLib(Game)
      local CM = V and V.require("ChunkMesher")
      if CM then CM.__freeFlyBodyOnly = nil end
    end)

    -- a flyer crossing a ledge just crosses it: the vanilla hop would
    -- hijack the step and stack its arc on top of the flight lift
    if not OC.__freeFlyLedgeWrapped then
      OC.__freeFlyLedgeWrapped = true
      local origLedge = OC.checkLedgeHop
      OC.checkLedgeHop = function(self, ...)
        if self.player and self.player.freeFlying then return false end
        return origLedge(self, ...)
      end
    end

    -- completed-step reactions (locked-door step scripts, gate guards,
    -- spinner tiles, poison ticks) belong to walkers; an airborne step
    -- touches nothing, and landing brings them all straight back
    -- completed-step reactions are a Gen 1 seam (Gold has none; its
    -- step effects stay live while airborne for now), so the install
    -- takes the controller as a plain argument
    local function installStepGate(controller)
      if controller.__freeFlyStepWrapped then return end
      controller.__freeFlyStepWrapped = true
      local origStep = controller.onStepComplete
      if not origStep then return end
      controller.onStepComplete = function(self, ...)
        if self.player and self.player.freeFlying then
          -- the Safari Game's step economy still ticks mid-air (the
          -- FOREST-tileset rule makes its zones flyable, and flight must
          -- not grant unlimited safari time); no-op outside the safari
          pcall(function() self:safariStep() end)
          return
        end
        return origStep(self, ...)
      end
    end
    if not goldBoot then installStepGate(OC) end

    OC.__freeFlyCrossGate2 = function(ow, dir, destMapId)
      if not flying() then return false end
      if mod.options:get("gates") and storyGateBlocks(destMapId) then
        windBack()
        return true
      end
      -- the confirm belongs to the listed sea seams only, judged by the
      -- seam itself rather than any cell: Pallet's fence-line lands on
      -- Route 21's dry rim and Pallet's own inlet puts water under the
      -- flyer, so cell-local tests let one path or the other slip
      -- through.  The per-map memory keeps a repeat from re-asking, and
      -- a party that could already SURF this stretch is never asked.
      if SEA_SEAMS[(ow.map and ow.map.id or "") .. ">" .. tostring(destMapId)]
         and not dangerAllowed(destMapId) and not surfAllowed(ow) then
        dangerAsk(destMapId)
        return true
      end
      return false
    end

    -- thin wraps install once; the implementations live on the Player
    -- table and are reassigned on every load, so F5 hot reload always
    -- runs the latest logic
    if not Player.__freeFlyWrapped then
      Player.__freeFlyWrapped = true

      local origPose = Player.pose
      Player.pose = function(self)
        local impl = Player.__freeFlyPoseImpl
        if impl then return impl(self, origPose) end
        return origPose(self)
      end

      local origDraw = Player.draw
      Player.draw = function(self, camX, camY)
        local impl = Player.__freeFlyDrawImpl
        if impl then return impl(self, camX, camY, origDraw) end
        return origDraw(self, camX, camY)
      end
    end

    -- lift rides pose so every renderer (flat, tilt, pipelines) sees it;
    -- airborne the card itself becomes the flapping bird, and the Rider
    -- ghost entity above carries the player figure
    Player.__freeFlyPoseImpl = function(self, origPose)
      local sprite, px, py, facing, phase, flip, hopping = origPose(self)
      local lift = self.freeFlyAlt
      if lift and lift > 0 then
        py = py - math.floor(lift + 0.5)
        local mount = Player.__freeFlyMount or Player.__freeFlyBird
        if mount then
          sprite = mount
          phase = math.floor(love.timer.getTime()
                             * (self.freeFlyFlapRate or 8)) % 2
          flip = false
        end
      end
      return sprite, px, py, facing, phase, flip, hopping
    end

    -- airborne the player rides: the bird sheet as the mount, the
    -- player's own top half seated on its back.  Both images come out
    -- of the player's imported cache, so nothing ships.
    Player.__freeFlyDrawImpl = function(self, camX, camY, origDraw)
      local lift = self.freeFlyAlt
      local bird = Player.__freeFlyMount or Player.__freeFlyBird
      if not (lift and lift > 0 and bird) then
        return origDraw(self, camX, camY)
      end
      -- the shadow shrinks with height and turns green over landable
      -- ground, so B-to-land reads at a glance; it stays flat below
      -- the attitude transform
      if self.freeFlyCanLand then
        love.graphics.setColor(0.1, 0.45, 0.15, 0.45)
      else
        love.graphics.setColor(0, 0, 0, 0.35)
      end
      local s = (Player.__freeFlyMountScale or 1) * sizeMult()
      local r = math.max(3, 7 - lift / 16) * s
      love.graphics.ellipse("fill", self.px + 8 - camX, self.py + 13 - camY,
                            r, r * 0.4)
      love.graphics.setColor(1, 1, 1, 1)
      local angle, squash = 0, 1
      if mod.options:get("motion") and state.motion then
        angle, squash = Sky.flightTransform(state.motion)
      end
      local spun = angle ~= 0 or squash ~= 1
      if spun then
        local ax = math.floor(self.px + 8 - camX)
        local ay = math.floor(self.py - lift + 8 - camY)
        love.graphics.push()
        love.graphics.translate(ax, ay)
        love.graphics.rotate(angle)
        love.graphics.scale(1, squash)
        love.graphics.translate(-ax, -ay)
      end
      local ry = self.py - math.floor(lift + 0.5)
      local flap = math.floor(love.timer.getTime()
                              * (self.freeFlyFlapRate or 8)) % 2
      -- rider FIRST, tucked low, then the mount over it: the mount's body
      -- hides the crop line, so the figure reads as seated behind its
      -- neck instead of a head floating above it
      local walk = self.freeFlyWalkSprite or self.sprite
      walk:draw(self.px, ry - math.floor(1 + 2 * s + 0.5),
                camX, camY, self.facing, 0, false, true)
      if s ~= 1 then
        local fx = math.floor(self.px + 8 - camX)
        local fy = math.floor(ry + 12 - camY)
        love.graphics.push()
        love.graphics.translate(fx, fy)
        love.graphics.scale(s, s)
        love.graphics.translate(-fx, -fy)
      end
      bird:draw(self.px, ry, camX, camY, self.facing, flap, false)
      if s ~= 1 then love.graphics.pop() end
      if spun then love.graphics.pop() end
    end

    local SpriteRenderer = require("src.render.SpriteRenderer")
    if Game.data.sprites.SPRITE_BIRD then
      Player.__freeFlyBird = SpriteRenderer.new(Game.data.sprites.SPRITE_BIRD,
                                                "free_fly_mount")
    end

    -- mount identity: the chosen mon's party-icon class maps onto a real
    -- walker sheet where one exists (bird/monster/seel/fairy), sized by
    -- its dex height.  Icon-only classes keep the bird; on Gold the
    -- shared resolver deals the species' own art the same way the sky
    -- birds get theirs.
    state.resolveMount = function(mon)
      state.mountMon = mon
      local species = mon and mon.species
      Player.__freeFlyMount = (species
        and Sky.mountSprite(Game.data, species, "free_fly"))
        or Player.__freeFlyBird
      local sprite = Player.__freeFlyMount
      Player.__freeFlyMountScale = (sprite and Sky.trueSized(sprite))
        and 1 or (species and Sky.dexScale(Game.data, species) or 1)
    end

    -- Gold's player is src.world.gen2.Player, a class the Gen 1 wraps
    -- above never touch; the same lift and mount composite ride it
    -- directly.  Gold draws people as draw(self, ox, oy, scale), which
    -- is the Gen 1 camera math scaled by s, so the flat composite runs
    -- under one scaled transform.
    if goldBoot then
      local okP2, Player2 = pcall(require, "src.world.gen2.Player")
      if okP2 and Player2 then
        if not Player2.__freeFlyWrapped then
          Player2.__freeFlyWrapped = true
          local origPose = Player2.pose
          Player2.pose = function(self)
            local impl = Player2.__freeFlyPoseImpl
            if impl then return impl(self, origPose) end
            if origPose then return origPose(self) end
            return self.sprite, self.px, self.py, self.facing, 0, false
          end
          local origDraw = Player2.draw
          Player2.draw = function(self, ox, oy, sc)
            local impl = Player2.__freeFlyDrawImpl
            if impl then return impl(self, ox, oy, sc, origDraw) end
            return origDraw(self, ox, oy, sc)
          end
        end
        Player2.__freeFlyPoseImpl = function(p, origPose)
          local sprite, px, py, facing, phase, flip, hop
          if origPose then
            sprite, px, py, facing, phase, flip, hop = origPose(p)
          else
            sprite, px, py, facing, phase, flip =
              p.sprite, p.px, p.py, p.facing, 0, false
          end
          local lift = p.freeFlyAlt
          if lift and lift > 0 then
            py = py - math.floor(lift + 0.5)
            local mount = Player.__freeFlyMount or Player.__freeFlyBird
            if mount then
              sprite = mount
              phase = math.floor(love.timer.getTime()
                * (p.freeFlyFlapRate or 8)) % 2
              flip = false
            end
          end
          return sprite, px, py, facing, phase, flip, hop
        end
        Player2.__freeFlyDrawImpl = function(p, ox, oy, sc, origDraw)
          local lift = p.freeFlyAlt
          if not (lift and lift > 0) then
            return origDraw(p, ox, oy, sc)
          end
          local G = love.graphics
          local scale = sc or 1
          G.push("all")
          G.scale(scale, scale)
          Player.__freeFlyDrawImpl(p, -(ox or 0) / scale,
            -(oy or 0) / scale, origDraw)
          G.pop()
        end
      end
    end

    -- crossConnection re-validates the landing tile on the neighbor map
    -- with Map.defPassable, outside the movement.collision hook; a flyer
    -- crosses any seam, water included
    local MapMod = require("src.world.Map")
    if not MapMod.__freeFlyWrapped then
      MapMod.__freeFlyWrapped = true
      local origPassable = MapMod.defPassable
      MapMod.defPassable = function(...)
        local active = MapMod.__freeFlyActive
        if active and active() then return true end
        return origPassable(...)
      end
    end
    MapMod.__freeFlyActive = function() return flying() end

    -- ------- followers while airborne
    -- The engine follower (and PokePC Followers riding it) knows bike and
    -- surf, not flight, so it kept walking under the flyer, water and all.
    -- A FLYING-type follower now trails through the air a little below
    -- the mount; any other follower sits the flight out and walks back in
    -- through the engine's own mid-map respawn path on landing.
    local PF = require("src.world.PikachuFollower")

    local function followerMon(game)
      local pokepc = mod.find("PokePCFollowers_VoxelMerge")
      if pokepc and pokepc.exports and pokepc.exports.activeMon then
        local ok, mon = pcall(pokepc.exports.activeMon, game)
        if ok and mon then return mon end
      end
      -- without a follower mod the engine follower is Yellow's Pikachu
      for _, m in ipairs(game.save and game.save.party or {}) do
        if m.species == "PIKACHU" and (m.hp or 0) > 0 then return m end
      end
    end

    local function removeFollower(ow)
      for i = #(ow.npcs or {}), 1, -1 do
        local n = ow.npcs[i]
        if n.pikachuFollower then
          table.remove(ow.npcs, i)
          for j = #(ow.entities or {}), 1, -1 do
            if ow.entities[j] == n then table.remove(ow.entities, j) end
          end
        end
      end
    end

    local FOLLOWER_FLAP = 6

    -- airborne the follower wears the same art the mount resolver picks
    -- (levitates sheet or the generic bird), sized by the same dex
    -- scale, so the pair reads as one style; its own follower sprite is
    -- stashed and handed back on landing
    local function dressFollower(npc, game, species, lift)
      npc.__freeFlyLift = lift
      if npc.__freeFlyAirSpecies ~= species then
        npc.__freeFlyAirSpecies = species
        npc.__freeFlyAirSprite =
          (Sky.mountSprite(game.data, species, "free_fly_follower"))
      end
      npc.__freeFlyAirScale = Sky.dexScale(game.data, species) * sizeMult()
      if npc.__freeFlyAirSprite then
        -- stash only a sprite that isn't ours: a foreign engine may
        -- re-dress the follower mid-air (land/swim sheets) every few
        -- frames, and stashing our own air sheet would lose the ground
        -- one for the landing
        if npc.sprite ~= npc.__freeFlyAirSprite then
          npc.__freeFlyGroundSprite = npc.sprite
        end
        npc.sprite = npc.__freeFlyAirSprite
      end
      if npc.__freeFlyDressed then return end
      npc.__freeFlyDressed = true
      local NPCMod = require("src.world.NPC")
      local basePhase = npc.walkPhase -- the follower's idle-aware phase
      npc.walkPhase = function(self)
        if (self.__freeFlyLift or 0) > 0 then
          return math.floor(love.timer.getTime() * FOLLOWER_FLAP) % 2
        end
        return basePhase(self)
      end
      -- the lift rides pose(), so the 2D draw and voxel billboards agree
      npc.pose = function(self)
        local sprite, px, py, facing, phase, flip, hop = NPCMod.pose(self)
        return sprite, px, py - (self.__freeFlyLift or 0), facing, phase,
               flip, hop
      end
      npc.draw = function(self, camX, camY)
        local l = self.__freeFlyLift or 0
        if l <= 0 then return NPCMod.draw(self, camX, camY) end
        local s = self.__freeFlyAirScale or 1
        local fade = math.max(0.35, 1 - l / 90)
        love.graphics.setColor(0, 0, 0, 0.3 * fade)
        love.graphics.ellipse("fill", self.px + 8 - camX,
                              self.py + 14 - camY, 5 * s, 2 * s)
        love.graphics.setColor(1, 1, 1, 1)
        if s ~= 1 then
          local fx = math.floor(self.px + 8 - camX)
          local fy = math.floor(self.py - l + 12 - camY)
          love.graphics.push()
          love.graphics.translate(fx, fy)
          love.graphics.scale(s, s)
          love.graphics.translate(-fx, -fy)
        end
        NPCMod.draw(self, camX, camY)
        if s ~= 1 then love.graphics.pop() end
      end
    end

    local function groundFollower(npc)
      npc.__freeFlyLift = 0
      if npc.__freeFlyGroundSprite then
        npc.sprite = npc.__freeFlyGroundSprite
        npc.__freeFlyGroundSprite = nil
        npc.__freeFlyAirSpecies = nil
      end
    end

    -- the overworld tick dresses foreign follower trailers with these
    -- (they live on PF because it is required in both scopes)
    PF.__freeFlyDress, PF.__freeFlyGround = dressFollower, groundFollower

    -- wilds of kanto's follower engine wraps and restores PF.update the
    -- same way it does OC.update: a restore from a snapshot taken before
    -- this dispatcher existed silently drops the flight gate, and a
    -- grounded-only follower trails the player into the sky.  Tagged and
    -- re-armed from the flight tick, which itself rides the healed
    -- OC.update wrap.
    PF.__freeFlyEnsureWrap = function()
      if PF.update == PF.__freeFlyDispatch then return end
      local orig = PF.update
      PF.__freeFlyDispatch = function(game, ow, ...)
        -- an outer copy of this dispatcher is mid-gate: stay vanilla
        if PF.__freeFlyInGate then return orig(game, ow, ...) end
        local tick = PF.__freeFlyTick
        if not tick then return orig(game, ow, ...) end
        PF.__freeFlyOrigUpdate = orig
        PF.__freeFlyInGate = true
        local ok, r = pcall(tick, game, ow, ...)
        PF.__freeFlyInGate = nil
        if not ok then error(r, 0) end
        return r
      end
      PF.update = PF.__freeFlyDispatch
    end
    PF.__freeFlyEnsureWrap()
    PF.__freeFlyTick = function(game, ow, ...)
      local orig = PF.__freeFlyOrigUpdate
      -- Gold's own follower engine keeps its ground rules for now
      if Sky.goldWorld(ow) then return orig(game, ow, ...) end
      local npc = ow and PF.current(ow)
      if not (ow and flying()) then
        if npc then groundFollower(npc) end
        return orig(game, ow, ...)
      end
      if followerModAware() then return orig(game, ow, ...) end
      local mon = followerMon(game)
      -- the mon carrying you cannot also trail you
      if not mon or mon == state.mountMon
         or not Sky.hasType(game.data, mon.species, "FLYING") then
        removeFollower(ow)
        return
      end
      -- hand the ground sprite back before the follower mod's own sync
      -- runs, so it never sees our air sprite and rebuilds against it
      if npc and npc.__freeFlyGroundSprite then
        npc.sprite = npc.__freeFlyGroundSprite
      end
      local r = orig(game, ow, ...)
      npc = PF.current(ow)
      if npc then
        dressFollower(npc, game, mon.species, state.alt)
      end
      return r
    end

    -- Voxel-style first/third-person FreeMove (DRAMATIC_SHAPE and its
    -- forks, e.g. Battle Art's) does its own collision
    -- (Map:isWalkableCell + Collision.occupied directly, never
    -- Collision.canMove), so the airborne pass-through above never
    -- reaches it.  Any loaded mod exporting a lib that serves a
    -- FreeMove module gets its tick wrapped, opening a permissive
    -- window scoped to exactly that call while the player flies.
    do
      local declared = Game.mods and Game.mods.exports or {}
      for _, ex in pairs(declared) do
        local V = type(ex) == "table" and ex.lib or nil
        local okFM, FreeMove = pcall(function()
          return V and V.require and V.require("FreeMove") or nil
        end)
        if okFM and FreeMove and FreeMove.tick then
          if not MapMod.__freeFlyWalkWrapped then
            MapMod.__freeFlyWalkWrapped = true
            local origWalkable = MapMod.isWalkableCell
            MapMod.isWalkableCell = function(self, cx, cy)
              if MapMod.__freeFlyPermissive then return self:inBounds(cx, cy) end
              return origWalkable(self, cx, cy)
            end
            local origOccupied = Collision.occupied
            Collision.occupied = function(...)
              if MapMod.__freeFlyPermissive then return false end
              return origOccupied(...)
            end
          end
          if not FreeMove.__freeFlyWrapped then
            FreeMove.__freeFlyWrapped = true
            local origTick = FreeMove.tick
            FreeMove.tick = function(fmState, ...)
              local p = fmState and fmState.player
              if not (p and p.freeFlying) then return origTick(fmState, ...) end
              MapMod.__freeFlyPermissive = true
              local ok, err = pcall(origTick, fmState, ...)
              MapMod.__freeFlyPermissive = false
              if not ok then error(err, 0) end
            end
          end
        end
      end
    end

    -- saves from before 0.9.0 have a taken gift but no marker on the mon;
    -- re-mark the first FLY-knowing bird of the gift line so BADGE CHECKS
    -- keeps exempting it (runs on load and on every save swap).  The whole
    -- line matches so an old gift PIDGEY that evolved stays exempt too.
    local function migrateGiftMarker()
      local save = Game.save
      if not (save and save.flags and save.flags[GIFT_TAKEN]) then return end
      local lists = { save.party }
      for _, box in ipairs(save.boxes or {}) do lists[#lists + 1] = box end
      for _, list in ipairs(lists) do
        for _, mon in ipairs(list or {}) do
          if mon.freeFlyGift then return end
        end
      end
      -- prefer a FLY knower; failing that take the first of the line
      -- anyway (a randomizer may have stripped the move), since the
      -- taken flag proves the gift was collected
      local fallback
      for _, list in ipairs(lists) do
        for _, mon in ipairs(list or {}) do
          if mon.species == "PIDGEY" or mon.species == "PIDGEOTTO"
             or mon.species == GIFT_SPECIES then
            if knowsFly(mon) then
              mon.freeFlyGift = true
              mod.log:info("marked the gift %s from an older save",
                           mon.species)
              return
            end
            fallback = fallback or mon
          end
        end
      end
      if fallback then
        fallback.freeFlyGift = true
        mod.log:info("marked the gift %s from an older save (FLY missing)",
                     fallback.species)
      end
    end
    migrateGiftMarker()
    mod.events:on("save.loaded", migrateGiftMarker)

    -- a save loaded while already standing in the gift's town gets its
    -- bird too, on either generation
    spawnGift()
    spawnGoldGift()
  end)

  -- ------- doubles integration (double_battles, when present)

  mod.events:on("game.ready", function()
    local db = mod.find("double_battles")
    local ex = db and db.exports
    if not ex then return end
    -- mid-air, the mon carrying you is the one fighting beside your
    -- lead: the ally slot prefers the mount over the bench order
    if ex.registerAllySource then
      ex.registerAllySource({
        id = "free_fly_mount",
        priority = 50,
        provide = function(game, battle)
          if not flying() then return nil end
          return state.mountMon
        end,
      })
    end
    -- an intercepted bird defends with its flockmate: the second foe
    -- of an aerial battle comes from the surrounding sky
    if ex.registerPartnerSource then
      ex.registerPartnerSource({
        id = "free_fly_flock",
        priority = 40,
        provide = function(game, battle)
          local it = state.lastIntercept
          if not it then return nil end
          if love.timer.getTime() - it.at > 10 then return nil end
          local e = battle and battle.enemy
          if not (e and e.mon and e.mon.species == it.species) then
            return nil
          end
          local skies = mod.find("wild_skies")
          local flock = skies and skies.exports
            and skies.exports.takeFlockmate
          if not flock then return nil end
          local p = game.overworld and game.overworld.player
          if not p then return nil end
          local ok, mate = pcall(flock, p.cellX, p.cellY, 8)
          if not (ok and mate) then return nil end
          return mate.species, mate.level
        end,
      })
    end
  end)
end

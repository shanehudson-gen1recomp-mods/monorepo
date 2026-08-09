-- Regression: wilds of kanto's follower ControlEngine (1.12.x) restores
-- OC.update wholesale from a snapshot taken before this mod wrapped it,
-- which used to drop the sky tick silently (birds vanish, no error).
-- The shared render.compose watchdog must re-arm the wrap; a chain a
-- foreign restore leaves holding two of our wraps must tick exactly
-- once per frame; and the shared tag must keep a second family mod's
-- watchdog from rewrapping every frame (the free_fly fight).
--
-- Also pinned: OC.draw is never replaced.  gen1_modern_ui compares the
-- overworld's draw against the shipped renderer and falls back to
-- classic menus for the whole session when it differs; the pre-1.6.2
-- draw-pass watchdog broke it that way.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data"); Data:load()

package.loaded["src.core.Game"] = {
  data = Data,
  overworld = { entities = {} },
  renderer = { worldViewSize = function() return 160, 144 end },
}

local OC = {}
local vanillaCalls = 0
local function vanilla(self, dt) vanillaCalls = vanillaCalls + 1 end
OC.update = vanilla
OC.draw = function(self) end
local shippedDraw = OC.draw
package.loaded["src.world.OverworldController"] = OC

-- a composed frame, the watchdog's ride; the vanilla fn mirrors the
-- renderer's default (no mod took over composition)
local function compose()
  Runtime.call("render.compose", function() return false end)
end
package.loaded["src.world.Map"] = { isOutside = function() return true end }
package.loaded["src.world.FieldDefaults"] = { field = function() return {} end }

-- the foreign engine installs first, snapshotting vanilla: the exact
-- ordering the bug needs
local kSnapshot = OC.update
local kCalls = 0
local function kInstall()
  local inner = OC.update
  kSnapshot = inner
  OC.update = function(self, dt)
    kCalls = kCalls + 1
    return inner(self, dt)
  end
end
local function kRestore()
  -- 1.12.1 style: unconditional, no equality guard
  OC.update = kSnapshot
end
kInstall()

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")
run.loader.events:emit("game.ready")

T.check(OC.__skyUpdateWrap ~= nil, "shared update wrap tagged")
T.eq(OC.update, OC.__skyUpdateWrap, "wrap installed on top")
T.eq(OC.draw, shippedDraw,
  "OC.draw keeps its shipped identity (gen1_modern_ui fingerprints it)")
T.check(OC.__skyDrawWrapped == true,
  "legacy draw-wrap flag pre-claimed so an old sibling skylib stands down")

-- count ticks through the dynamic slots the wrap dispatches to; the
-- second key stands in for free_fly sharing the same wrap
local ticks, flyTicks = 0, 0
OC.__wildSkiesTick = function() ticks = ticks + 1 end
OC.__skyTickKeys[#OC.__skyTickKeys + 1] = "__freeFlyTick"
OC.__freeFlyTick = function() flyTicks = flyTicks + 1 end

local function frame()
  local v0, t0, f0 = vanillaCalls, ticks, flyTicks
  OC.update({}, 1 / 60)
  OC.draw({})
  compose()
  return vanillaCalls - v0, ticks - t0, flyTicks - f0
end

local v, t, f = frame()
T.eq(v, 1, "healthy chain: vanilla runs once")
T.eq(t, 1, "healthy chain: sky tick runs once")
T.eq(f, 1, "healthy chain: the second mod's tick rides along")

-- the tag matches, so composed frames must never grow the chain: this
-- is the two-watchdog fight that broke free_fly
local settled = OC.update
compose(); compose(); compose()
T.eq(OC.update, settled, "watchdog is stable while the tag holds")

-- the foreign restore snaps back to bare vanilla, dropping our wrap;
-- the very next drawn frame must heal it
kRestore()
local vLost, tLost = vanillaCalls, ticks
OC.update({}, 1 / 60)
T.eq(ticks, tLost, "clobbered: the tick is gone")
T.eq(vanillaCalls, vLost + 1, "clobbered: vanilla still runs")
compose()
T.eq(OC.update, OC.__skyUpdateWrap, "watchdog re-armed the wrap")
v, t, f = frame()
T.eq(v, 1, "healed: vanilla runs once")
T.eq(t, 1, "healed: sky tick runs once")
T.eq(f, 1, "healed: the second mod's tick came back too")

-- the engine wraps on top again; the watchdog re-tags above it, leaving
-- two of our wraps in the chain, and the guard keeps everything single
kInstall()
compose()
local k0 = kCalls
v, t, f = frame()
T.eq(v, 1, "stacked wraps: vanilla runs once")
T.eq(t, 1, "stacked wraps: sky tick runs once")
T.eq(f, 1, "stacked wraps: second tick runs once")
T.eq(kCalls, k0 + 1, "stacked wraps: the foreign wrap still runs")

-- this restore resurrects our older wrap from the snapshot; still single
kRestore()
compose()
v, t, f = frame()
T.eq(v, 1, "resurrected wrap: vanilla runs once")
T.eq(t, 1, "resurrected wrap: sky tick runs once")
T.eq(f, 1, "resurrected wrap: second tick runs once")

T.eq(OC.draw, shippedDraw,
  "OC.draw still untouched after every clobber and heal")

run.release()
T.finish("wild_skies_wrap_heal")

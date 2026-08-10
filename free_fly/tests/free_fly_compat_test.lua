package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local root = os.getenv("MOD_DIR") or "mods/free_fly"
local FlightInput = assert(loadfile(root .. "/lib/FlightInput.lua"))()
local VoxelProvider = assert(loadfile(root .. "/lib/VoxelProvider.lua"))()

local requested = 0
local input = { pressQueue = { "up", "b" } }
T.check(FlightInput.capture(input, true, function() requested = requested + 1 end),
  "semantic B queue edge requests landing")
T.eq(requested, 1, "landing callback runs once")
T.eq(#input.pressQueue, 2, "capture leaves the engine input edge intact")
T.check(not FlightInput.capture({ pressQueue = { "x" } }, true, function() end),
  "physical keys are not confused with semantic actions")
T.check(not FlightInput.capture(input, false, function() requested = 99 end),
  "grounded input cannot request landing")
T.eq(requested, 1, "grounded B does not run the callback")

local original = { require = function() end }
local fork = { require = function() end }
T.eq(VoxelProvider.lib({ mods = { exports = {
  DRAMATIC_SHAPE = { lib = original },
} } }), original, "original Dramatic Shape provider resolves")
T.eq(VoxelProvider.lib({ mods = { exports = {
  BATTLE_ART_VOXEL_FORK = { lib = fork },
} } }), fork, "battle-art fork provider resolves")
T.eq(VoxelProvider.lib({ mods = { exports = {
  DRAMATIC_SHAPE = { lib = original },
  BATTLE_ART_VOXEL_FORK = { lib = fork },
} } }), original, "original provider wins when both are active")
T.eq(VoxelProvider.lib({}), nil, "missing voxel provider is safe")

T.finish("free_fly_compat")

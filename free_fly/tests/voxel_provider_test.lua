-- VoxelProvider discovery: known ids are trusted on shape, unknown
-- exports must prove family membership on the marker module, and a
-- lib.require that serves other things (Wilds of Kanto exports one)
-- is not membership.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local MOD_DIR = os.getenv("MOD_DIR") or "mods/free_fly"
local M = assert(loadfile(MOD_DIR .. "/lib/VoxelProvider.lua"))()

local voxelLib = { require = function(name)
  if name == "VoxelState" then return { ANGLES_DEG = {} } end
end }
local otherLib = { require = function(name)
  if name == "variable_size" then return {} end
end }
local knownLib = { require = function() end }

T.eq(M.lib({ mods = { exports = {
  SOME_FUTURE_FORK = { lib = voxelLib },
} } }), voxelLib, "an unknown fork is admitted by capability")

T.eq(M.lib({ mods = { exports = {
  overworld_wild_spawns = { lib = otherLib },
} } }), nil, "a lib serving other modules is not a voxel provider")

T.eq(M.lib({ mods = { exports = {
  overworld_wild_spawns = { lib = otherLib },
  DRAMATIC_SHAPE = { lib = knownLib },
} } }), knownLib, "a known id is trusted on shape and wins")

T.eq(M.lib(nil), nil, "no game answers nil")
T.eq(M.lib({ mods = { exports = {} } }), nil, "no exports answers nil")

T.finish("voxel_provider")

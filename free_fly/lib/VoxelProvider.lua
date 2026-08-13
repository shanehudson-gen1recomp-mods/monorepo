-- Voxel library discovery.  Dramatic Shape, the battle-art fork and
-- the Gen 2 Stadium mod publish the same library contract (exports.lib
-- with a require serving the voxel module family) under different mod
-- ids, and future forks will too.  Known ids are preferred for
-- determinism; any other export is admitted by capability, probed on a
-- marker module every member of the family serves.
local M = {}

local KNOWN = { "DRAMATIC_SHAPE", "BATTLE_ART_VOXEL_FORK",
                "STADIUM2_OVERWORLD_MODELS" }

local function libShaped(lib)
  return type(lib) == "table" and type(lib.require) == "function"
end

-- unknown ids must also PROVE the family membership: plenty of mods
-- export a lib.require of their own (Wilds of Kanto does), and the
-- marker module is one every voxel family member serves
local function servesVoxel(lib)
  if not libShaped(lib) then return false end
  local ok, state = pcall(lib.require, "VoxelState")
  return ok and state ~= nil
end

function M.lib(game)
  local exports = game and game.mods and game.mods.exports
  if not exports then return nil end
  for _, id in ipairs(KNOWN) do
    local ex = exports[id]
    local lib = type(ex) == "table" and ex.lib or nil
    if libShaped(lib) then return lib end
  end
  for _, ex in pairs(exports) do
    local lib = type(ex) == "table" and ex.lib or nil
    if servesVoxel(lib) then return lib end
  end
  return nil
end

return M

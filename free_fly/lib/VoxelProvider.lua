-- Dramatic Shape and the battle-art fork publish the same library contract
-- under different mod ids.
local M = {}

function M.lib(game)
  local exports = game and game.mods and game.mods.exports
  local provider = exports and
    (exports.DRAMATIC_SHAPE or exports.BATTLE_ART_VOXEL_FORK)
  return provider and provider.lib or nil
end

return M

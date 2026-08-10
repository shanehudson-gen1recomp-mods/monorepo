-- Landing compatibility for follower mods that own persistent trailer state.
--
-- Free Fly deliberately lets flight-capable followers trail in the air. A
-- seam crossed during flight can leave the follower owner's old trailer
-- objects in the previous transition space, so a completed landing asks that
-- owner to reconstruct from its authoritative party state.
local M = {}

function M.rebuild(mod, game, overworld, restoreEligibility)
  -- Flight temporarily marks ground-bound party members as not following.
  -- Clear those marks before asking the follower owner to enumerate the
  -- authoritative party; otherwise it materializes only the airborne subset.
  if type(restoreEligibility) == "function" then
    local restored, restoreErr = pcall(restoreEligibility)
    if not restored then return false, false, restoreErr end
  end
  local wilds = mod and mod.find and mod.find("overworld_wild_spawns")
  local syncAll = wilds and wilds.exports and wilds.exports.syncAll
  if type(syncAll) ~= "function" then return true, false end
  local ok, result = pcall(syncAll, game, overworld)
  if not ok then return false, true, result end
  return true, true, result
end

return M

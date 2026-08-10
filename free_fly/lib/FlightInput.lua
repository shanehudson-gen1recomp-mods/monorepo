-- Pure input-boundary helpers.  A physical key/button has already been
-- translated to a Game Boy action by the time it reaches pressQueue.
local M = {}

function M.queued(input, button)
  for _, pressed in ipairs((input and input.pressQueue) or {}) do
    if pressed == button then return true end
  end
  return false
end

function M.capture(input, airborne, request)
  if not airborne or not M.queued(input, "b") then return false end
  request()
  return true
end

return M

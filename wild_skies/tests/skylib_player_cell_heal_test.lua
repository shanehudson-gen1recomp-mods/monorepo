-- Sky.healPlayerCell: the engine's Player:update multiplies cellX/cellY
-- bare on every moving frame, so a nil cell (left behind by a foreign
-- landing/free-move/warp path) crashes the game.  The shared update
-- wrap repairs it from the pixel position before the engine runs.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local MOD_DIR = os.getenv("MOD_DIR") or "mods/wild_skies"
local Sky = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()

T.eq(Sky.healPlayerCell(nil), false, "no player: nothing to do")
local fine = { cellX = 3, cellY = 4, px = 48, py = 64, moving = true,
               targetX = 4, targetY = 4, progress = 5 }
T.eq(Sky.healPlayerCell(fine), false, "a healthy player is untouched")
T.eq(fine.moving, true, "healthy: step state kept")
T.eq(fine.targetX, 4, "healthy: target kept")

-- the crash shape: mid-step, cell cleared, pixels still valid
local p = { cellX = nil, cellY = 7, px = 100, py = 112, moving = true,
            targetX = 6, targetY = 7, progress = 3, facing = "right" }
T.eq(Sky.healPlayerCell(p), true, "nil cellX is repaired")
T.eq(p.cellX, 6, "cell comes from the pixel position (nearest cell)")
T.eq(p.cellY, 7, "the intact axis is kept")
T.eq(p.px, 96, "pixels snap to the cell")
T.eq(p.py, 112, "pixels snap to the cell (y)")
T.eq(p.moving, false, "grounded: not moving")
T.eq(p.targetX, nil, "grounded: no target")
T.eq(p.progress, 0, "grounded: progress reset")

-- no pixels either: the step target is the next best guess, then 0
local q = { cellX = nil, cellY = nil, targetX = 9, targetY = 2 }
T.eq(Sky.healPlayerCell(q), true, "both axes nil is repaired")
T.eq(q.cellX, 9, "no px: falls back to the step target")
T.eq(q.cellY, 2, "no py: falls back to the step target")
local r = {}
T.eq(Sky.healPlayerCell(r), true, "an empty player is repaired")
T.eq(r.cellX, 0, "nothing to go on: origin")
T.eq(r.cellY, 0, "nothing to go on: origin (y)")

-- through the wrap: the engine's update must see a whole player
local OC = {}
local seen
OC.update = function(self, dt) seen = self.player.cellX * 16 end
Sky.ensureUpdateWrap(OC, "__testTick", nil)
local ow = { player = { cellX = nil, cellY = 1, px = 40, py = 16,
                        moving = true, targetX = 3, targetY = 1 } }
local ok = pcall(OC.update, ow, 1 / 60)
T.eq(ok, true, "wrap: the engine update no longer throws")
T.eq(seen, 48, "wrap: the engine saw the repaired cell")
T.eq(ow.player.moving, false, "wrap: the player was grounded")

T.finish("skylib_player_cell_heal")

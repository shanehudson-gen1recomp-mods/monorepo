-- Sky.headingRow / smoothFacing / headingFacing: headings map to the
-- eight PMD rows with sticky sector boundaries, and facing changes
-- sweep one 45-degree notch at a time the short way around.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local MOD_DIR = os.getenv("MOD_DIR") or "mods/wild_skies"
local Sky = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()
local pi = math.pi

T.eq(Sky.headingRow(0), 2, "east is the right row")
T.eq(Sky.headingRow(pi / 4), 1, "southeast is downright")
T.eq(Sky.headingRow(pi / 2), 0, "south is down")
T.eq(Sky.headingRow(pi), 6, "west is left")
T.eq(Sky.headingRow(-pi / 4), 3, "northeast is upright")
T.eq(Sky.headingRow(-pi / 2), 4, "north is up")
T.eq(Sky.headingRow(-3 * pi / 4), 5, "northwest is upleft")
T.eq(Sky.headingRow(5 * pi / 2), 0, "unwrapped headings still land")

-- sticky: a nudge past a sector boundary keeps the old row, a real
-- turn switches
T.eq(Sky.headingRow(pi / 8 + math.rad(4), 2), 2,
  "a nudge past the boundary sticks")
T.eq(Sky.headingRow(pi / 4, 2), 1, "a real turn switches")

-- smoothFacing: one notch per interval, catching up over time
local e = {}
T.eq(Sky.smoothFacing(e, "right", 0), "right", "starts on target")
T.eq(Sky.smoothFacing(e, "left", 0), "right", "no time yet, no turn")
T.eq(Sky.smoothFacing(e, "left", 0.06), "downright",
  "one notch after one interval")
T.eq(Sky.smoothFacing(e, "left", 0.25), "left",
  "catches up over enough time")
T.eq(Sky.smoothFacing(e, "up", 0.31), "upleft",
  "a new turn goes the short way around")
T.eq(Sky.smoothFacing(e, "up", 0.36), "up", "and lands")

-- headingFacing glues the two together, with a fallback for callers
-- that have no heading to offer
local f = {}
T.eq(Sky.headingFacing(f, pi / 2, "right"), "down",
  "heading drives the row")
T.eq(Sky.headingFacing(f, nil, "right"), "right", "no heading, fallback")

T.finish("skylib_facing")

-- Loads dev-hook-inspector through the headless loader and asserts the
-- load is clean: no loader errors and its hooks registered without firing.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/dev-hook-inspector",
  { data = Data })
-- discovery finding nothing also reports zero errors, so a vacuous run
-- must fail here rather than pass silently (MOD_DIR must be relative)
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")
run.release()
T.finish("dev-hook-inspector")

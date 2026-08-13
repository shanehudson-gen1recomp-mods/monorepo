-- Loads wild_skies as if Gold were the running game: the manifest's
-- games declaration must admit the mod and the load must stay clean.
-- A gate skip is not an error, so the state is asserted, not just the
-- error count.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies",
                          { generation = 2 })
T.check(run.mod ~= nil, "mod discovered")
T.eq(run.mod and run.mod.state, "loaded", "loads on a Gen 2 boot")
T.eq(#run.errors, 0, "loads clean")
local api = run.loader.exports.wild_skies
T.check(api ~= nil, "exports registered")
T.check(type(api.flyerAt) == "function", "inter-mod exports served")
T.check(type(api.takeFlyer) == "function", "takeFlyer served")
T.eq(api.flyerAt(0, 0, 99), nil, "flyerAt nil-safe with no world")
run.release()
T.finish("wild_skies_gen2")

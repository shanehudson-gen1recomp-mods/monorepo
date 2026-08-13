-- Loads double_battles as if Gold were the running game: the
-- manifest's games declaration must admit the mod, the load must stay
-- clean, and the Gold arm must be the one that armed (the Gen 1
-- machinery registers exports, the Gold arm deliberately does not).
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/double_battles",
                          { generation = 2 })
T.check(run.mod ~= nil, "mod discovered")
T.eq(run.mod and run.mod.state, "loaded", "loads on a Gen 2 boot")
T.eq(#run.errors, 0, "loads clean")
local api = run.loader.exports.double_battles or {}
T.eq(api.registerPartnerSource, nil,
     "the Gen 1 machinery stayed out of a Gold boot")
run.release()
T.finish("double_battles_gen2_load")

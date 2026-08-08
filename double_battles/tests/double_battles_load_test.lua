-- Loads double_battles through the headless loader: clean load, exports
-- present, and the on-demand starter refuses politely with no world.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/double_battles",
  { data = Data })
-- discovery finding nothing also reports zero errors, so a vacuous run
-- must fail here rather than pass silently (MOD_DIR must be relative)
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local api = run.loader.exports.double_battles
T.check(api ~= nil, "exports registered")
local ok, why = api.startWildDouble("PIDGEY", 5, "RATTATA", 4)
T.eq(ok, false, "refuses with no overworld")
T.eq(why, "no overworld", "and says why")
local okT, whyT = api.startTrainerDouble("OPP_BUG_CATCHER", 1)
T.eq(okT, false, "trainer double refuses with no overworld")
T.eq(whyT, "no overworld", "and says why")
local okP, whyP = api.startTrainerPair("OPP_BUG_CATCHER", 1,
                                        "OPP_LASS", 1)
T.eq(okP, false, "trainer pair refuses with no overworld")
T.eq(whyP, "no overworld", "and says why")
T.eq(select(1, api.registerPartnerSource("nope")), false,
  "partner source needs a table")
T.eq(select(1, api.registerPartnerSource({ id = "x" })), false,
  "partner source needs provide")
T.eq(api.registerPartnerSource({ id = "t", provide = function() end }),
  true, "valid partner source registers")
T.eq(api.unregisterPartnerSource("t"), true, "and unregisters")
T.eq(api.tagOrganic(), true, "organic tagging is callable")
T.eq(api.isDoubleBattle({}), false, "isDoubleBattle checks the flag")
T.eq(api.isDoubleBattle({ __double = true }), true, "and accepts it")

run.release()
T.finish("double_battles")

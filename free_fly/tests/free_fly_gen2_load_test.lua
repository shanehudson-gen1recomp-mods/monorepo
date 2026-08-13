-- Loads free_fly as if Gold were the running game: the manifest's
-- games declaration must admit the mod, the load must stay clean (the
-- Pallet map script must not register into a gated registry), and the
-- flight exports must be served.  A gate skip is not an error, so the
-- state is asserted, not just the error count.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/free_fly",
                          { generation = 2 })
T.check(run.mod ~= nil, "mod discovered")
T.eq(run.mod and run.mod.state, "loaded", "loads on a Gen 2 boot")
T.eq(#run.errors, 0, "loads clean (no gated registry writes)")
local api = run.loader.exports.free_fly
T.check(api ~= nil, "exports registered")
T.eq(api.isFlying(), false, "isFlying answers grounded headless")
T.eq(api.altitude(), 0, "altitude answers zero headless")
T.eq(api.mount(), nil, "no mount while grounded")

-- the Gold gift listener stays nil-safe with no world up
run.loader.events:emit("world.interacted",
  { kind = "npc", mapId = "NEW_BARK_TOWN" })
run.loader.events:emit("map.entered", { mapId = "NEW_BARK_TOWN" })
T.eq(#run.errors, 0, "gift seams are nil-safe headless")
run.release()
T.finish("free_fly_gen2")

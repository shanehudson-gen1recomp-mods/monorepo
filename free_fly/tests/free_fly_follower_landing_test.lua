package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local root = os.getenv("MOD_DIR") or "mods/free_fly"
local FollowerLanding = assert(loadfile(root .. "/lib/FollowerLanding.lua"))()

local rebuilt, gotGame, gotWorld = 0
local landingOrder = {}
local temporarilyStopped = true
local fakeGame, fakeWorld = {}, {}
local fakeMod = { find = function(id)
  T.eq(id, "overworld_wild_spawns", "landing resolves Wilds by public mod id")
  return { exports = { syncAll = function(game, overworld)
    landingOrder[#landingOrder + 1] = "rebuild"
    T.check(not temporarilyStopped,
      "the authoritative rebuild sees every follower eligible")
    rebuilt, gotGame, gotWorld = rebuilt + 1, game, overworld
    return "rebuilt"
  end } }
end }
local ok, attempted, result = FollowerLanding.rebuild(
  fakeMod, fakeGame, fakeWorld, function()
    landingOrder[#landingOrder + 1] = "restore"
    temporarilyStopped = false
  end)
T.check(ok and attempted, "landing asks Wilds to reconstruct its convoy")
T.eq(table.concat(landingOrder, ","), "restore,rebuild",
  "landing restores follower eligibility before reconstruction")
T.eq(result, "rebuilt", "the follower owner's rebuild result is preserved")
T.eq(rebuilt, 1, "the follower owner is asked exactly once")
T.check(gotGame == fakeGame and gotWorld == fakeWorld,
  "the current game and post-seam overworld reach the rebuild")

local absent = { find = function() return nil end }
local absentRestored = false
local absentOk, absentAttempted = FollowerLanding.rebuild(absent, {}, {},
  function() absentRestored = true end)
T.check(absentOk and not absentAttempted,
  "landing without Wilds remains a successful no-op")
T.check(absentRestored,
  "landing restores temporary follower state even without Wilds")

local restoreFailed, restoreAttempted, restoreErr = FollowerLanding.rebuild(
  fakeMod, {}, {}, function() error("broken restore") end)
T.check(not restoreFailed and not restoreAttempted
    and tostring(restoreErr):find("broken restore", 1, true),
  "a restore failure cannot rebuild from a partial follower roster")

local broken = { find = function()
  return { exports = { syncAll = function() error("broken rebuild") end } }
end }
local brokenOk, brokenAttempted, brokenErr = FollowerLanding.rebuild(
  broken, {}, {})
T.check(not brokenOk and brokenAttempted
    and tostring(brokenErr):find("broken rebuild", 1, true),
  "a follower rebuild failure is reported without breaking landing")

T.finish("free_fly_follower_landing")

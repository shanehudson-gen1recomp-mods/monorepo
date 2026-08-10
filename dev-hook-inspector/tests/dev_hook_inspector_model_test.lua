-- Universal introspection with no cooperation from the inspected mod:
-- exports enumerated live off the loader, docs pulled from the comments
-- above their definitions, events found in the mod's own source or seen
-- live on the bus, and the START menu wrap inserting HOOKS before QUIT.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local MOD_DIR = os.getenv("MOD_DIR") or "mods/dev-hook-inspector"
local run = T.sdk.loadMods({ MOD_DIR, MOD_DIR .. "/tests/hook_fixture" },
  { data = Data })
T.eq(#run.errors, 0, "both mods load clean")

local api = run.loader.exports["dev-hook-inspector"]
local model = api.inspect()
T.check(type(model) == "table", "inspect returns the model")

local function find(id)
  for _, m in ipairs(model) do
    if m.id == id then return m end
  end
  return nil
end

T.check(find("dev-hook-inspector") ~= nil, "lists itself")
local fx = find("hook_fixture")
T.check(fx ~= nil, "lists the fixture mod")
T.eq(fx.name, "Hook Fixture", "title from the manifest")
T.eq(fx.description, "Fixture mod for the inspector's tests.",
  "description from the manifest")

local function hooksOf(m)
  local hooks = {}
  for _, hook in ipairs(m.hooks) do hooks[hook.name] = hook end
  return hooks
end

local hooks = hooksOf(fx)
T.check(hooks.documented ~= nil, "commented export listed")
T.eq(hooks.documented.doc, "A documented export.",
  "doc read from the comment above the definition")
T.eq(hooks.documented.kind, "export", "kind export")
T.check(hooks.bare ~= nil, "uncommented export still listed")
T.eq(hooks.bare.doc, nil, "just without a doc")
T.eq(hooks.bare.valueType, "function", "value type recorded")
local ping = hooks["mod.hook_fixture.ping"]
T.check(ping ~= nil, "event found in the mod's source")
T.eq(ping.kind, "event", "kind event")
T.eq(ping.doc, "Fires on ping.", "event doc from the comment above the emit")
T.eq(hooks["mod.hook_fixture.pong"], nil,
  "dynamically named event invisible until it fires")

-- exports sort first alphabetically, events close the list
T.eq(fx.hooks[1].name, "announce", "exports lead the list")
T.eq(fx.hooks[#fx.hooks].name, "mod.hook_fixture.ping", "events close it")

-- engine-hook wraps surface straight off the live chains, with the
-- priority and chain position no metadata had to declare
local wrap = hooks["fixture.chain"]
T.check(wrap ~= nil, "the fixture's wrap is listed")
T.eq(wrap.kind, "wrap", "kind wrap")
T.eq(wrap.priority, 25, "at its registered priority")
T.eq(wrap.of, 1, "alone in its chain")
T.check(wrap.doc and wrap.doc:find("priority 25", 1, true) ~= nil,
  "the detail line spells the chain facts out")

-- the inspector's own START menu wrap shows up on itself the same way
local selfWraps = hooksOf(find("dev-hook-inspector"))
T.check(selfWraps["ui.start_menu.items"] ~= nil,
  "the inspector reports its own menu wrap")

-- the model carries the manifest facts a dev triages load order by
T.eq(fx.priority, 500, "priority from the manifest")
T.eq(fx.skippedFiles, 0, "small mods scan whole")

-- the bus watcher picks up an event whose name never appears whole in
-- the source, once it fires
run.loader.exports.hook_fixture.whisper()
model = api.inspect()
hooks = hooksOf(find("hook_fixture"))
T.check(hooks["mod.hook_fixture.pong"] ~= nil, "live-seen event listed")
T.eq(hooks["mod.hook_fixture.pong"].doc, nil, "with no doc to find")

-- the inspector documents its own export from its own source comment
local selfHooks = hooksOf(find("dev-hook-inspector"))
T.check(selfHooks.inspect ~= nil, "inspect export listed")
T.check(selfHooks.inspect.doc ~= nil
  and selfHooks.inspect.doc:find("every loaded mod", 1, true) ~= nil,
  "documented from the comment above it")

-- the START menu wrap inserts HOOKS before QUIT
local pushed = {}
local game = { stack = { push = function(_, screen)
  pushed[#pushed + 1] = screen
end } }
local items = { { label = "POKéMON" }, { label = "QUIT" } }
local out = run.loader.hooks:call("ui.start_menu.items",
  function(_, rows) return rows end, game, items)
local at = {}
for i, item in ipairs(out) do at[item.label] = i end
T.check(at.HOOKS ~= nil, "HOOKS row added")
T.check(at.HOOKS < at.QUIT, "and sits before QUIT")

-- walking the menus: HOOKS opens the mod list, a mod opens its hooks,
-- and picking a hook logs the detail line to the console
out[at.HOOKS].onSelect()
local modList = pushed[#pushed]
T.check(modList ~= nil and modList.items ~= nil, "HOOKS opens the mod list")
local fxRow
for _, row in ipairs(modList.items) do
  if row.m and row.m.id == "hook_fixture" then fxRow = row end
end
T.check(fxRow ~= nil, "fixture mod has a row")
modList.onChoose(fxRow, modList)
local hookList = pushed[#pushed]
T.check(hookList ~= modList and hookList.items ~= nil,
  "a mod opens its hook list")
local hookRow
for _, row in ipairs(hookList.items) do
  if row.hook and row.hook.name == "documented" then hookRow = row end
end
T.check(hookRow ~= nil, "the documented export has a row")
local Logger = require("src.core.Logger")
local before = #Logger.history
hookList.onChoose(hookRow, hookList)
T.check(#Logger.history > before, "picking a hook logs to the console")
local logged
for i = before + 1, #Logger.history do
  local line = Logger.history[i]
  if line:find("hook_fixture.documented", 1, true)
     and line:find("A documented export.", 1, true) then
    logged = line
  end
end
T.check(logged ~= nil, "the console line carries the full name and doc")
T.check(pushed[#pushed] ~= hookList, "and the detail box is pushed")

run.release()
T.finish("dev-hook-inspector model")

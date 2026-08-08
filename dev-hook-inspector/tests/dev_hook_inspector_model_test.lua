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
local items = { { label = "POKéMON" }, { label = "QUIT" } }
local out = run.loader.hooks:call("ui.start_menu.items",
  function(_, rows) return rows end, { stub = true }, items)
local at = {}
for i, item in ipairs(out) do at[item.label] = i end
T.check(at.HOOKS ~= nil, "HOOKS row added")
T.check(at.HOOKS < at.QUIT, "and sits before QUIT")

run.release()
T.finish("dev-hook-inspector model")

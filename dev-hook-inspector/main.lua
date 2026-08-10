-- Dev Hook Inspector: a HOOKS entry on the START menu that lists every
-- loaded mod and the public surface it offers other mods.  Nothing here
-- asks mods to cooperate:
--
-- - Exports are enumerated live from the loader the engine hands out
--   with mods.loaded, so the list is what is actually installed.
-- - Events come from the mod's own source: only the owning mod may emit
--   under "mod.<id>.*", so any such literal in its files names an event
--   it broadcasts.  A watcher on the bus also records mod events as
--   they fire, catching names built at runtime.
-- - Descriptions are the comment block sitting directly above the
--   hook's definition (or emit), when there is one.
return function(mod)
  local state = { loader = nil, scans = {} }

  -- ------- live event watcher

  -- mod event names seen on the bus, keyed by emitting mod id
  local liveSeen = {}

  local function watchEmits(loader)
    local events = loader.events
    if events.__hookInspectorWatched then return end
    events.__hookInspectorWatched = true
    local baseEmit = events.emit
    events.emit = function(self, name, payload)
      if type(name) == "string" then
        local id = name:match("^mod%.([%w_%-]+)%.")
        if id then
          local bucket = liveSeen[id]
          if not bucket then
            bucket = {}
            liveSeen[id] = bucket
          end
          bucket[name] = true
        end
      end
      return baseEmit(self, name, payload)
    end
  end

  mod.events:on("mods.loaded", function(ev)
    state.loader = ev and ev.loader or nil
    state.scans = {}
    if state.loader then watchEmits(state.loader) end
  end)

  -- ------- source scanning

  local MAX_FILES = 64

  local function luaFiles(fs, dir, out, depth)
    local items = fs.getDirectoryItems(dir)
    if type(items) ~= "table" then return out end
    table.sort(items)
    for _, item in ipairs(items) do
      local path = dir .. "/" .. item
      local info = fs.getInfo(path)
      if info and info.type == "directory" then
        if item ~= "tests" then luaFiles(fs, path, out, depth + 1) end
      elseif item:sub(-4) == ".lua" then
        out[#out + 1] = { path = path, depth = depth }
      end
    end
    return out
  end

  -- shallow files first: an overhaul mod can carry more sources than
  -- the scan budget, and the entry file plus its root-level siblings
  -- say more than a deep lib tree.  Anything past the budget is
  -- counted, never silently dropped.
  local function scanOrder(files)
    table.sort(files, function(a, b)
      if a.depth ~= b.depth then return a.depth < b.depth end
      return a.path < b.path
    end)
    local skipped = 0
    if #files > MAX_FILES then
      skipped = #files - MAX_FILES
      for i = #files, MAX_FILES + 1, -1 do files[i] = nil end
    end
    return files, skipped
  end

  -- the contiguous comment block directly above a line, stopped at a
  -- blank line, code, or a "-- -------" style section divider
  local function commentAbove(lines, i)
    local parts = {}
    for j = i - 1, 1, -1 do
      local text = lines[j]:match("^%s*%-%-%s?(.*)")
      if not text or text:match("^%-%-%-") then break end
      table.insert(parts, 1, text)
    end
    local doc = table.concat(parts, " ")
      :gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if doc == "" then return nil end
    return doc
  end

  local function scanMod(id)
    local scan = { exportDocs = {}, events = {}, eventDocs = {},
      skippedFiles = 0 }
    local loader = state.loader
    local rec = loader.mods[id]
    if not (rec and rec.path) then return scan end
    local fs = loader.fs
    local eventPattern = '["\'](mod%.' .. id:gsub("%W", "%%%0")
      .. '%.[%w_][%w_%.%-:]*)["\']'
    local files, skipped = scanOrder(luaFiles(fs, rec.path, {}, 0))
    scan.skippedFiles = skipped
    for _, file in ipairs(files) do
      local src = fs.read(file.path)
      if type(src) == "string" then
        local lines = {}
        for line in (src .. "\n"):gmatch("(.-)\r?\n") do
          lines[#lines + 1] = line
        end
        for i, line in ipairs(lines) do
          local name = line:match("exports%.([%a_][%w_]*)%s*=")
            or line:match('exports%[["\']([^"\']+)["\']%]%s*=')
          if name and scan.exportDocs[name] == nil then
            scan.exportDocs[name] = commentAbove(lines, i)
          end
          for event in line:gmatch(eventPattern) do
            scan.events[event] = true
            if scan.eventDocs[event] == nil then
              scan.eventDocs[event] = commentAbove(lines, i)
            end
          end
        end
      end
    end
    return scan
  end

  -- ------- model

  -- exports first, then engine-hook wraps, then events, each block
  -- alphabetical
  local function hooksFor(id)
    local scan = state.scans[id]
    if not scan then
      scan = scanMod(id)
      state.scans[id] = scan
    end
    local hooks = {}
    for name, value in pairs(state.loader.exports[id] or {}) do
      hooks[#hooks + 1] = { name = tostring(name), kind = "export",
        valueType = type(value), doc = scan.exportDocs[tostring(name)] }
    end
    table.sort(hooks, function(a, b) return a.name < b.name end)
    -- which engine hook chains this mod wraps, straight off the live
    -- chains: owner and priority ride every entry, and the chain
    -- position says who else shares the slot.  For an overhaul that
    -- wraps deeply this is the headline fact about it.
    local chains = state.loader.hooks and state.loader.hooks.chains or {}
    local wraps = {}
    for chainName, chain in pairs(chains) do
      for pos, entry in ipairs(chain) do
        if entry.owner == id then
          wraps[#wraps + 1] = { name = chainName, kind = "wrap",
            priority = entry.priority or 0, pos = pos, of = #chain,
            doc = ("wraps the engine hook chain at priority %d, "
              .. "link %d of %d"):format(entry.priority or 0, pos, #chain) }
        end
      end
    end
    table.sort(wraps, function(a, b) return a.name < b.name end)
    for _, wrap in ipairs(wraps) do hooks[#hooks + 1] = wrap end
    local names = {}
    for event in pairs(scan.events) do names[event] = true end
    for event in pairs(liveSeen[id] or {}) do names[event] = true end
    local events = {}
    for event in pairs(names) do
      events[#events + 1] = { name = event, kind = "event",
        doc = scan.eventDocs[event] }
    end
    table.sort(events, function(a, b) return a.name < b.name end)
    for _, event in ipairs(events) do hooks[#hooks + 1] = event end
    return hooks, scan.skippedFiles
  end

  -- The list the inspector renders: every loaded mod with its exports
  -- and discovered events, so another tool can dump the same data.
  mod.exports.inspect = function()
    local loader = state.loader
    if not loader then return nil, "mods not loaded yet" end
    local list = {}
    for _, manifest in ipairs(loader:status().loaded) do
      local hooks, skippedFiles = hooksFor(manifest.id)
      list[#list + 1] = {
        id = manifest.id,
        name = manifest.name,
        version = manifest.version,
        description = manifest.description or "",
        priority = manifest.priority,
        profile = manifest.profile,
        hooks = hooks,
        skippedFiles = skippedFiles or 0,
      }
    end
    return list
  end

  -- ------- screens

  -- ListMenu draws labels at column 2 and right-aligns the tag to
  -- column 19, so a row has 17 columns to share between the two
  local ROW_COLS = 17
  local TYPE_TAG = { ["function"] = "fn", table = "tbl", string = "str",
    number = "num", boolean = "bool" }

  local function fit(label, right)
    local room = ROW_COLS - (right ~= "" and (#right + 1) or 0)
    return #label > room and label:sub(1, room) or label
  end

  local function pushText(game, text)
    game.stack:push(mod.ui.TextBox.new(game, text))
  end

  local NO_DOC = "No description found. The inspector shows the comment "
    .. "written above a hook's definition in the mod's source."

  local function aboutText(m)
    local text = m.name .. ": " .. (m.description ~= ""
      and m.description or "No description in the manifest.")
    if m.priority ~= nil then
      text = text .. " Priority " .. tostring(m.priority)
        .. (m.profile and (", profile " .. tostring(m.profile)) or "")
        .. "."
    end
    return text
  end

  local function openMod(game, m)
    local rows = { { label = "ABOUT", right = "" } }
    if (m.skippedFiles or 0) > 0 then
      rows[#rows + 1] = { label = "PARTIAL SCAN",
        right = tostring(m.skippedFiles),
        detail = ("This mod carries more source files than the scan "
          .. "budget (%d). %d files went unread, so some events and "
          .. "descriptions may be missing; exports and wraps come from "
          .. "the live loader and are complete.")
          :format(MAX_FILES, m.skippedFiles) }
    end
    for _, hook in ipairs(m.hooks) do
      local label, right
      if hook.kind == "event" then
        -- the emitting mod is the screen we're on, so the forced
        -- mod.<id>. prefix is noise here; the detail view keeps it
        label = hook.name:gsub("^mod%.[%w_%-]+%.", "")
        right = "ev"
      elseif hook.kind == "wrap" then
        label = hook.name
        right = "wr"
      else
        label = hook.name
        right = TYPE_TAG[hook.valueType] or "?"
      end
      rows[#rows + 1] = { label = fit(label, right), right = right,
        hook = hook }
    end
    game.stack:push(mod.ui.ListMenu.new(game, m.name:upper(), rows, {
      keyRepeat = true,
      pageJump = true,
      onChoose = function(item)
        -- devs watching the run get the same line on the console,
        -- untruncated and copyable
        if not item.hook then
          local text = item.detail or aboutText(m)
          mod.log:info("%s", text)
          pushText(game, text)
          return
        end
        local hook = item.hook
        local header = hook.kind == "event" and hook.name
          or (m.id .. "." .. hook.name)
        if hook.kind == "wrap" then header = hook.name end
        local tag = hook.kind == "event" and "event"
          or hook.kind == "wrap" and "wrap"
          or ("export (" .. (hook.valueType or "?") .. ")")
        mod.log:info("%s %s: %s", tag, header,
          hook.doc or "no description found")
        pushText(game, header .. ": " .. (hook.doc or NO_DOC))
      end,
    }))
  end

  local function openInspector(game)
    local model = mod.exports.inspect()
    if not model then
      pushText(game, "Mods are still loading.")
      return
    end
    local rows = {}
    for _, m in ipairs(model) do
      rows[#rows + 1] = { label = fit(m.name:upper(), m.version),
        right = m.version, m = m }
    end
    game.stack:push(mod.ui.ListMenu.new(game, "HOOK INSPECTOR", rows, {
      keyRepeat = true,
      pageJump = true,
      onChoose = function(item) openMod(game, item.m) end,
    }))
  end

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    mod.ui.insertBefore(out, "QUIT", { label = "HOOKS",
      onSelect = function() openInspector(game) end })
    return out
  end)
end

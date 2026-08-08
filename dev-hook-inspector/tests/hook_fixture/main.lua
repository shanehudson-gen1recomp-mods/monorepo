-- Minimal mod for the inspector's model test: a commented export, a
-- bare one, a literal event emit, and a dynamically built event name
-- only the live watcher can see.
return function(mod)
  -- A documented export.
  mod.exports.documented = function() return true end
  mod.exports.bare = function() return false end
  mod.exports.announce = function()
    -- Fires on ping.
    mod.events:emit("mod.hook_fixture.ping", {})
  end
  mod.exports.whisper = function()
    mod.events:emit("mod.hook_fixture." .. "pong", {})
  end
end

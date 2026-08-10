# Dev Hook Inspector

A developer tool for mod authors. The START menu gains a HOOKS entry
that lists every loaded mod; pick one to see its public surface: the
exports other mods can call through `mod.find(id)`, the engine hook
chains it wraps (with priority and chain position, so shared-chain
disputes are visible at a glance), and the events it broadcasts. Pick
a hook to read its description.

Every pick is also printed to the console (the terminal that launched
the game), untruncated and copyable:

```
[info] [dev-hook-inspector] export (function) free_fly.isFlying: Flight state for other mods; ...
```

No mod has to cooperate to show up here:

- Exports are enumerated live off the loader, so the list is what is
  actually installed and running, not what a document claims.
- Wraps come off the live hook chains the same way: owner, priority
  and position ride every chain entry, no metadata required.
- An overhaul carrying more source files than the scan budget gets a
  PARTIAL SCAN row saying how many files went unread (shallow files
  are read first, so the entry file always is). Exports and wraps are
  live-enumerated and complete regardless.
- Events are found in the mod's own source. Only the owning mod may
  emit under `mod.<id>.*`, so any such string literal in its files
  names an event it broadcasts. A watcher on the event bus also
  records mod events as they fire, which catches names built at
  runtime; those appear once seen.
- A hook's description is the comment written directly above its
  definition (or emit) in the source, when there is one. No comment
  just means no description; the hook is still listed by name and
  type.

The model behind the screens is itself a public hook:
`exports.inspect()` returns every loaded mod with its hooks, so
another tool can render or dump the same data.

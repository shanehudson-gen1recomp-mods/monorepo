# Dev Hook Inspector

A developer tool for mod authors. The START menu gains a HOOKS entry
that lists every loaded mod; pick one to see its public surface: the
exports other mods can call through `mod.find(id)`, and the events it
broadcasts. Pick a hook to read its description.

No mod has to cooperate to show up here:

- Exports are enumerated live off the loader, so the list is what is
  actually installed and running, not what a document claims.
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

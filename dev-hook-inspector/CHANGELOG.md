# Changelog

## 0.2.0

- Engine-hook wraps are listed: each mod's screen now shows which
  engine hook chains it wraps (tag `wr`), straight off the live
  chains, with priority and chain position in the detail view. For an
  overhaul like Crystal 251, which wraps deeply across the battle
  engine, this is the headline fact the inspector used to omit.
- Big mods scan honestly: source files are read shallow-first (the
  entry file and its root siblings before a deep lib tree), and when a
  mod carries more files than the scan budget a PARTIAL SCAN row says
  how many went unread instead of silently dropping events and docs.
  Exports and wraps come from the live loader either way, so those
  lists are always complete.
- The ABOUT entry states the mod's priority and profile, and long
  lists page-jump with left/right.

## 0.1.1

- README documents that every pick is also printed to the console. No
  gameplay changes.

## 0.1.0

- First release. HOOKS on the START menu lists every loaded mod, its
  exports (enumerated live off the loader), and the events found in its
  source or seen on the bus, with descriptions read from the comments
  above their definitions. `exports.inspect()` hands other tools the
  same model.

# shared/

Build-time shared Lua. Anything here (besides this README) is copied into
each mod as `lib/shared/` by `scripts/dev.sh`, `scripts/pack.sh` and the
release workflow, so packed zips stay self-contained.

`skylib.lua` holds the helpers the mod family shares: icon-class
lookup, the mount sprite resolver, the dex-height draw scale, type and
move checks, grass-slot reading (`Sky.grassSlots`) and mon display
names (`Sky.monName`).

The mount resolver first tries `Sky.SPRITE_SOURCES`, an ordered list of
adapters over other mods' exports (currently Wilds of Kanto,
`overworld_wild_spawns`). When such a mod is enabled, our flyers borrow
its per-species in-air art: everything we draw is airborne, so adapters
resolve flying or hovering sheets only (Wilds' animated "levitates"
sheets), never its ground walk cycles, which read as walking on air.
Species without in-air art keep the generic bird/monster/seel/fairy
mount sheets, which are drawn mid-flight.

The full author-facing reference is [INTEGRATION.md](../INTEGRATION.md).
External sprite packs join through `Sky.registerSpriteSource(source)`,
also exported by both mods as `registerSpriteSource` /
`unregisterSpriteSource(id)`. A source is a table:

- `id` (or `mod`): its identity; re-registering replaces, and
  `mod` also gates the source on that mod being enabled (its exports
  are passed to resolve; a source with only an `id` gets nil).
- `resolve(exports, game, species, dex)`: return a SpriteRenderer def
  (`image`, `frames`, `walker`, `trueColor`). Defs must be animated
  (frames > 1) or they fall through; flyers need wing flap.
- `stripWater` (optional): key the levitates splash color out of the
  sheet, for art drawn over a waterline.

Registered sources are tried before the built-ins. Each mod bundles its
own copy of this resolver, so packs register with every mod they want
to dress.

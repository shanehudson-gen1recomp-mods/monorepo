# Changelog

## 1.5.0

- Ultra-rare sightings: 1 in 1000 spawns under an open outdoor sky is
  a legendary bird (Articuno, Zapdos or Moltres, L48-52) instead of
  the map's usual pick. A legend flies alone, is always bold, and the
  roll skips towns, caves and the forest canopy, so every sighting is
  one you can battle and catch through the usual bump and free_fly
  interception seams.

## 1.4.3

- For mod authors: `exports.summonFlyer(cellX, cellY, opts)` calls the
  nearest bold bird down to a cell and consumes it on arrival, with
  the `flyer_summoned` / `summon_failed` events reporting exactly one
  ending per summon. Built for double_battles' visible recruitment.

## 1.4.2

- Update checks now come from the mod's official mirror repo
  (shanehudson-gen1recomp-mods/wild_skies). No gameplay changes.

## 1.4.1

- Walking under a rooftop bird no longer scares it off; it only moves
  along when its rest runs out, or when an airborne player gets close.
  The same goes for a bird gliding in to land on a roof above you.
  Roof rests also run two to three times longer than street rests, so
  rooftop birds properly settle in instead of touching down and
  leaving again.
- Roosting: when a bird is already sat on a roof, the next bird
  looking for a roof joins it on a free cell of the same rooftop
  rather than founding its own, so rooftop groups build up naturally.
  Arrivals never disturb the sitter.

## 1.4.0

- Birds now wander instead of flying in a straight line. They follow
  curving paths, change height as they go, and fly at the same sort of
  heights the free_fly mount uses, with the odd low swoop. Birds of
  the same species drift into loose flocks, and some arrive as a small
  group. After fifteen to thirty seconds a bird leaves over the
  nearest map edge.
- Lots more birds: the LOW / MED / HIGH caps are now 3 / 6 / 10, with
  faster respawns. To stop that turning into constant fights, only
  about a third of birds will actually battle you; the rest are
  scenery and fly away if you get close. After any battle started by
  this mod there is also a 25 second break before the next one can
  happen.
- Birds can rest on building roofs as well as on the ground. Roof
  perching needs the Dramatic Shape Voxel Mod installed, because its
  map data is what tells us which tiles are roofs; you don't have to
  use its 3D view, it works while playing flat 2D. Without that mod,
  birds rest on the ground only. Birds on roofs never start battles.
- Towns and cities get birds too, Cinnabar Island and the Indigo
  Plateau included. Town birds mostly sit on roofs, never battle, and
  their levels grow with your badge count: around level 3 to 8 with no
  badges, up to the forties with all eight. The same badge rule covers
  any other map with no encounter data to read levels from.
- Better species and level picks: sea routes get Pidgeotto, Pidgeot
  and Fearow instead of a sky full of Pidgey, ambient bird levels come
  from the map's own encounter slots, and caves count as night at all
  hours, so the Zubat line always flies in Mt Moon and Rock Tunnel.
- New BIRD SIZE option (SMALL / NORMAL / LARGE / HUGE). The default is
  NORMAL, which looks the same as before. Cave birds stay capped at a
  sensible size on every setting; without that cap Cerulean Cave's
  Golbat and Dodrio drew far too big for the corridors.
- Birds face up and down now, not just left and right.
- For mod authors: the `mod.wild_skies.flyer_taken` event fires
  whenever `takeFlyer` removes a bird, whichever mod called it.

## 1.3.1

- If a normal grass battle rolls a species while that same species is
  sitting or landing within two cells of the player, the battle now is
  that bird: it brings its own level, and beating or catching it
  removes the sprite instead of leaving it there. A grounded match is
  picked over a flying one.
- For mod authors (see INTEGRATION.md in the repository):
  `exports.spawnFlyer(species, level)` spawns one flyer on demand, the
  `mod.wild_skies.flyer_bumped` event broadcasts ground-bump battles,
  and `exports.registerSpriteSource` lets sprite packs offer in-air
  art. The ground-bump gate now reads free_fly's exported flight state
  instead of the raw player field.

## 1.3.0

- Wilds of Kanto integration: with that mod enabled, flyers wear its
  per-species "levitates" art, so a crossing Fearow looks like a Fearow
  instead of the generic bird sheet. Only its in-air sheets are
  borrowed, never its Sprite Style selection: all three of its styles
  (HGSS/PokeMMO, Poke Followers, Pokedex) are ground walk cycles, and a
  walk cycle toggled in the sky reads as walking on air. The levitates
  sheets are that mod's only flying poses and are style-independent by
  its own design (its water Pokemon ignore Sprite Style the same way),
  so the chosen style shows on the ground and the flying pose rules the
  sky. Species without a levitates sheet (Pidgey, Spearow) keep the
  generic sheets, which are at least drawn mid-flight.
- Those levitates sheets are drawn hovering over water, splash included;
  the splash (one flat color across the whole set) is keyed out at load,
  so borrowed art carries no water into the sky.
- Big wings beat slower: the flap rate eases with dex size, so a Fearow
  flaps calmer than a Spearow.
- Sprite-source option changes re-dress live flyers immediately instead
  of waiting for the next spawn.

## 1.2.0

- Forest sky-life, sparse by design: Viridian Forest gets the ambient
  pool at one bird at a time with long cooldowns, cruising low to weave
  between the trunks. The Safari Zone needs no special case: its own
  encounter slots carry Doduo, so slot spawns work there as anywhere.
- Flyers survive seamless map crossings: they translate with the same
  coordinate rebase the player gets instead of despawning at the seam.
  Warps and doors still clear the sky as before.

## 1.0.0

- 1.0.0: first public release, lockstep with free_fly. MIT license.

## 0.5.0

- GROUND BUMPS (option, default on): a bird at or below 12px, perched,
  landing or freshly flushed, can collide with a WALKING player and
  start its battle (cry plays, 1-cell reach). High flyers never touch
  anyone at ground level; airborne players remain free_fly's business.

## 0.4.1

- Fix phantom encounters: ambient skies require the map to carry an
  encounter table (towns like Cinnabar stay quiet), airborne spawns
  refuse to materialize within 5 cells of the player, and newborn or
  dead flyers are invisible to the inter-mod collision API for 0.75s.

## 0.4.0

- Sea skies: outdoor maps with no flying grass slots (Routes 19-21) get a
  sparse ambient pool (Pidgey/Spearow lines by day, Zubat line at night)
  at a reduced cap and longer cooldown.
- Behavior repertoire: some flyers land mid-crossing and rest, some start
  perched and flush away when the player comes within 2 cells; resting
  birds stand and peck instead of flapping.
- Height variety: about a third fly high, and the shadow fades and
  tightens with altitude as a depth cue.

## 0.3.2

- Shared helpers (icon-class mounts, dex scale, type/move checks) moved
  to the monorepo's shared/skylib.lua, synced in as lib/shared/. No
  behavior change.

## 0.3.1

- Flyers are sized by their dex height (scaled 0.85x-1.6x around the foot
  anchor, shadow included): Pidgey reads small, a Charizard-class flyer
  reads big.

## 0.3.0 (Phase 2)

- Flyers glide in from just past the camera edge and cross the whole
  view; no more mid-screen pop-in (world edges are the one exception).
- Species identity: each flyer wears its party-icon class walker sheet
  (bird/monster/seel/fairy) with a per-class flight profile (speed band,
  altitude band, flap rate, bob depth).
- Time of day: Zubat and Golbat own the night sky and sit out daylight;
  the slot cache keys on (map, tod) so day/night mods drive rotation.
- SKY DENSITY option: LOW / MED / HIGH spawn caps and cooldowns.

## 0.2.0

- Inter-mod API: `exports.flyerAt(cellX, cellY, radius)` and
  `exports.takeFlyer(...)` let other mods (free_fly's aerial
  interception) read and consume flyers without touching internals.
- Performance: the FLYING-slot filter is cached per map instead of
  recomputed per frame, and flyer-less maps re-arm a long cooldown.

## 0.1.0

- Proof of concept: ambient flyers from the map's FLYING grass slots,
  shadow + bob + flap on the imported SPRITE_BIRD sheet, spawn cap and
  cooldown, despawn at map edge or timeout.

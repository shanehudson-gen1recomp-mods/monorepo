# Changelog

## 1.9.0

- Seam-neighbor skies are pre-populated on the engine's ghost surface and
  retain their displayed positions when promoted to the current map. Each
  connected outdoor map keeps its own bounded resident flock; doors and other
  full transitions still refresh the population. (Gold reaches the same
  behavior through its own resident-field path; see the Gen 2 bullet.)
- A transport-neutral shared-sky provider API lets session and replay mods
  exchange bounded, revisioned field snapshots and claim encounters without
  coupling Wild Skies to a particular networking implementation.
- Gen 2 (Gold) support: the manifest declares `games: [gen1, gen2]`,
  so the mod loads on Gold boots. Everything generation-specific is
  probed from the data or object in hand, never from a version check:
  - Gold's kind-first, time-of-day encounter tables feed the sky
    directly (`encounters.grass[map].slots.NITE`). Night species are
    derived from the tables themselves, same rule the Crystal 251
    ecology probe applies, so Hoothoot owns Johto's night without a
    hand list.
  - Flyers are drawn through a tail on Gold's `World:drawPeople` (its
    world never draws the entity list) and dressed from the imported
    Gold cache: the species' own walker sheet where Gold ships one
    (Moltres, Ho-Oh, Butterfree and some thirty more), else its own
    battle front pic drawn overworld-sized (the white background
    floods to transparency from the border, so body whites survive),
    else the sheet its icon assignment names, the gold bird, or its
    menu icon. Every rung wears the species' shipped colours, so a
    Pidgey reads as a Pidgey rather than a tinted generic bird.
    Sprite packs registered through `registerSpriteSource` still
    outrank all of it, on either generation.
- Voxel integration is capability-based, not id-based: any Gold voxel
  mod publishing the bridge contract (voxelPipelineState with the
  extra-entities slot) gets the flyers in its cast, and any mod
  embedding the Wilds pipeline under exports.wilds.render serves
  borrowed art, so forks compose the day they release.
- Gold rooftop perching: with Stadium 2 installed, its shape
  profile's per-cell structure heights (VoxelScene.groundAt) tell the
  birds which cells are buildings, the same way the Dramatic Shape
  profile does on Gen 1, so downtown Johto gets its skyline roosts.
  The profile's tileset-id spelling is normalized in place exactly
  the way that mod's own bridge does it, so the two never fight.
- Stadium 2 voxel worlds (STADIUM2_OVERWORLD_MODELS) show the sky:
  its Gold compositor never blits the 2D scene, so flyers join its
  voxel cast through the bridge's extra-entities provider, chained so
  the embedded Wilds keep theirs. Altitude rides the existing pose
  contract, and each flyer carries speciesId so the Stadium 3D models
  dress the birds where the player's imported Stadium ROM has them
  (billboard cards otherwise).
- Local skies: a town's ambient pool now draws on the species hosted
  within a few seams and doorways of it, walked over the connection
  graph the map data already carries (warps included, so the Safari
  Zone counts as next door to Fuchsia). No more Safari-exclusive
  Scyther over Pallet Town; level bands localize the same way.
  Datasets without a map graph keep the world-wide pool.
- FLIGHT MOTION toggle (on by default): simulated flight attitude on
  every sprite. Birds bank into turns, pitch with climbs and dives,
  and pulse gently at their flap rate; pure draw-time motion, so
  portraits, walker sheets and borrowed True Size art all read as
  flying. Grounded and perched birds sit level.
- SKY ART option, both generations: no game of this era ships
  flying-pose overworld art, so the sky composes one. AUTO (default)
  keeps bird-shaped species on the flapping walker sheet (in their
  shipped colours on Gold) and gives every other shape its
  species-true battle portrait; on Gen 1 that includes the Gen 2
  portraits Crystal 251 extracts for its species. PORTRAIT and
  CLASSIC force one look for everything; CLASSIC is exactly the old
  Gen 1 appearance. The option re-dresses airborne birds live.
- Wilds of Kanto's per-species HGSS land sheets now dress birds that
  have no in-air art (the same sheets its own wilds wear and Dramatic
  Sky Ride's mounts fly on), resolved through WoK's own bind pipeline
  so its Sprite Style, palette mode and True Size decisions stay
  authoritative. The levitates in-air art still outranks it, and
  registered sprite packs outrank both.
- Dex-reorder guard (WoK issue #55): their packs are keyed by national
  dex position, so under a dataset that reorders the dex the borrowed
  art would belong to the wrong species. Sentinel species whose canon
  numbers never move detect a reordered dex space, and dex-keyed
  borrowing switches off there in favour of the identity-correct
  fallbacks.
- Wilds of Kanto 2.0.0 ready: borrowed sheets keep their True Size
  frame geometry (a rebuilt def without it crops tall sheets to a
  16x16 tile), a True Size sheet's own size wins over the dex-height
  scale so birds are never sized twice, and a live Sprite Style or
  Pokemon Size flip re-dresses airborne birds at the right scale.
  - View size, outdoors detection and badge count each read the Gold
    answer where the Gen 1 seam does not exist (`viewW/viewH`, the
    header's environment byte, `save.player.badges`).
  - Gold keeps resident flocks across seams too: each connected map's
    birds tick against a translated stand-in world, show through the
    seam at their offset, and a connection crossing swaps flocks with
    positions intact. Doors and other full transitions still refresh
    the sky.
- Shared skylib grows the generation-agnostic readers
  (`wildRows`, `grassSlots` with a time-of-day, `mapWild`,
  `slotLevels`, `viewSize`, `outsideMap`, `badgeCount`,
  `ensureDrawTail`, `goldWorld`) for the rest of the family.
- Not yet play-tested on a real Gold boot; `modkit gen2check` verdict
  is "will load but degrade", where the one remaining warning is a
  Gen 1-only call site Gold never reaches at runtime.
- Flightless FLYING types never join the sky on either generation:
  the dex has Doduo and Dodrio running and Natu hopping, so they stay
  on the ground where they belong.

## 1.8.0

- Derived skies: the ambient pools (sea routes, towns) now grow from
  the world's own encounter tables instead of a fixed Gen 1 list. Any
  FLYING species a dataset places in a wild slot joins the sky:
  WATER/FLYING species patrol the sea pool, the rest the day pool,
  weighted by how widely the world hosts them and leveled by the
  slots the world itself deals them. On a vanilla dex this adds the
  wild flyers the old list missed (Farfetch'd, the Doduo line,
  Scyther); with an overhaul like Crystal 251 installed, Johto's
  birds arrive without wild_skies naming a single species.
- Night knowledge: a dataset that exports a period-aware ecology
  (Crystal 251's `ecology.list()`) teaches wild_skies which of its
  species fly only after dark; probed by capability, never by mod id.
  Without such an export, a small hand list keeps the Zubat line and
  the known Gen 2 owls nocturnal.
- Crystal 251 declared as an optional dependency so it always loads
  first and its rebuilt encounter tables and species are what the
  sky reads.
- The legendary sky roll stays Articuno/Zapdos/Moltres by design:
  Crystal 251 stages Lugia and Ho-Oh at its own sanctuaries and the
  sky will not undercut those encounters.

(1.7.0 is the SKY TRAINERS series, developed on its own branch and
not yet released; the number stays reserved for it.)

## 1.6.3

- The GROUND BUMPS option is now called GROUND BATTLES. Same toggle,
  same default, same saved setting; only the label changed.

## 1.6.2

- Gen1 Modern UI works again alongside this mod. That mod checks that
  the overworld's draw function is still the engine's own before it
  lays its modern menus over the world, and 1.6.1's self-heal watchdog
  wrapped exactly that function, so every menu quietly fell back to the
  classic look. The watchdog now rides the engine's render.compose hook
  chain instead: same healing (better, actually, since it also runs
  during battles and menus), and the overworld's draw is never touched.
  free_fly 1.5.2 carries the same fix; if both are installed, update
  both, since either one's older copy re-installs the old wrap.

## 1.6.1

- Survive foreign update-hook restores: wilds of kanto 1.12.x's
  follower engine resets the overworld update function from a snapshot
  taken before this mod hooked it, which silently stopped the sky tick
  (birds vanished with no error). The hook is now tagged and re-armed
  from the draw pass whenever it goes missing, and a re-entrancy guard
  keeps the tick single even when a foreign restore leaves an older
  copy of the wrap in the chain.
- Cross-mod compatibility: the hook moved into skylib as one shared
  wrap for the whole mod family. wild_skies 1.6.1 and free_fly 1.5.1
  ride the same tagged wrap, so their watchdogs recognise each other
  and never mistake a sibling for a foreign mod (separate wraps would
  re-wrap each other every frame). Mixed versions stay safe: an
  updated mod heals itself either way, an older sibling just keeps its
  old single hook and misses the healing until it updates too.

## 1.6.0

- Legendary sightings stay 1v1: a doubles veto keeps ARTICUNO, ZAPDOS
  and MOLTRES encounters strictly solo, so a rolled partner (or the
  aimed-ball rule ending the battle on a capture) can never cost you
  the bird.
- Bird pairs: a bumped bird now brings its flockmate. The new
  `takeFlockmate` export hands the partner slot a second bold bird
  through the after-battle rest (which exists to stop battles
  chaining, not to empty the second slot of the one that already
  started); legendaries are never flockmates. free_fly uses the same
  export for its aerial interceptions.
- Survivors return to the sky: a sky-sourced second foe (a summoned
  recruit or a flockmate) that outlives an undecided battle -- you
  ran, or caught the other one -- respawns into the air instead of
  evaporating.

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

# Changelog

## 1.5.4

- Crystal 251 compatibility confirmed and pinned by a regression test:
  free_fly keeps no species list, so Johto species registered into the
  merged data mount, filter airborne encounters and gate on FLY
  compatibility exactly like Kanto ones. A FLY-knowing Hoothoot offers
  FREEFLY, a FLY-compatible Skarmory qualifies through a relaxing
  mod's eligibility chain, and a flightless Steelix stays grounded.
  No behavior change on a vanilla dex.

## 1.5.3

- The sea-crossing confirm is now Pallet Town's send-off. Flying south
  onto Route 21 asks at any point along the seam (the old check keyed
  on the landing cell, so crossing above the fence-line slipped past
  it), the message calls your mount by name ("You usually need the
  SOULBADGE to cross here... But PIDGEOT is feeling brave!"), and a
  party that could already SURF that stretch is never asked. Other
  seams no longer prompt at all; CROSS is still remembered per save.

## 1.5.2

- Gen1 Modern UI works again alongside this mod. That mod checks that
  the overworld's draw function is still the engine's own before it
  lays its modern menus over the world, and 1.5.1's self-heal watchdog
  wrapped exactly that function, so every menu quietly fell back to the
  classic look. The watchdog now rides the engine's render.compose hook
  chain instead: same healing (better, actually, since it also runs
  during battles and menus), and the overworld's draw is never touched.
  wild_skies 1.6.2 carries the same fix; if both are installed, update
  both, since either one's older copy re-installs the old wrap.

## 1.5.1

- New SIZE option (SMALL / NORMAL / LARGE / HUGE) for the mon carrying
  you. The ladder is tuned against the rider figure rather than
  wild_skies' bird sizes, and sits a step above the old look: SMALL is
  the size flight always had, NORMAL draws about 15% bigger, and the
  steps stay tight enough that you still read as seated. The
  flight-gated follower in the air scales along with it, and changes
  apply mid-flight.

- Survive foreign update-hook restores: wilds of kanto 1.12.x's
  follower engine resets the overworld update function from a snapshot
  taken before this mod hooked it, which silently stopped the flight
  tick. The hook is now re-armed from the draw pass whenever a foreign
  restore drops it.
- The follower flight gate heals the same way: the engine also wraps
  and restores PikachuFollower.update, which stripped the gate and let
  a grounded-only follower (a Bulbasaur without FLY) trail the player
  into the sky. The gate dispatcher is tagged and re-armed every frame
  from the flight tick.
- Wilds of kanto's own followers respect flight now too: its engine
  walks party mons through its own update wrap, past the PF gate, so
  free_fly speaks its language instead. While airborne, ground-bound
  mons and the mount itself are marked with the engine's per-mon stay
  flag (honoured by its trailer packs and stock follower alike) and
  released on landing. Only mons free_fly marked are released, so STAY
  choices a player made themselves survive the flight. FLYING-types
  keep trailing, and now properly: they fly at exactly the player's
  altitude in their flying sheet wherever the trail goes, land or sea.
  free_fly's dress runs after the foreign engine's frame, so its land
  and swim sprite swaps can never show through mid-flight. Airborne
  trailers also stop snagging on scenery: the engine's cell gate opens
  to any in-bounds cell for a flying mon trailer (the trainer trailer
  keeps ground rules), and one that lands mid-fence gets reseeded
  behind the player by the engine itself. Declaring
  `freeFlyAware = true` still turns all of this off.
- Voxel first/third-person flight works in forks too: the airborne
  collision pass-through for FreeMove was keyed to one mod's exports,
  so a fork shipping its own copy (Battle Art's voxel fork) kept
  ground collision while flying and the player snagged on fences. Any
  loaded mod whose exported lib serves a FreeMove module now gets the
  same scoped permissive window.
- Assisted landings no longer trust a facade scan from a bad frame: a
  tower-footprint scan that failed (mid-transition) was cached for the
  whole map visit with no facades in it, so a landing could set down
  through a roof. A failed scan now retries next frame instead.
- Cross-mod compatibility: the hook rides skylib's new shared wrap
  alongside wild_skies 1.6.1. One tag for the whole family means the
  mods recognise each other's hook instead of treating a sibling as a
  foreign mod, and any one of them healing the wrap brings every
  registered tick back. Mixed versions are fine: pair this with an
  older wild_skies and both still work, the older one just lacks the
  self-healing until it updates.

- Aerial doubles: intercepting a bird mid-flight can now bring its
  flockmate as a second foe, through wild_skies' new `takeFlockmate`
  seam. Same doubles odds and options as any wild encounter.
- The mount fights beside you: in a battle that doubles while you fly,
  the mon carrying you takes the partner slot instead of whoever sits
  next in the party, through double_battles' new ally-source API.
  On the ground nothing changes.

## 1.4.4

- With double_battles installed, an aerial interception's battle is
  tagged organic, so the intercepted bird can gain a second foe like
  any other wild encounter.

## 1.4.3

- Fixes FREEFLY showing up in the battle party menu. Picking it there
  (while switching Pokemon mid-fight) tore down the battle and took
  off. The entry now appears only in the overworld party menu, and
  takeoff refuses while any battle is running, whichever path asks for
  it, the FLY WHISTLE included.

## 1.4.2

- Update checks now come from the mod's official mirror repo
  (shanehudson-gen1recomp-mods/free_fly). No gameplay changes.

## 1.4.0

- FREEFLY no longer vanishes from the party menu when another mod (a
  randomizer, say) changes your Pokemon's data. The gift bird always
  shows the option, any Pokemon that knows FLY always shows it, and if
  a randomizer swaps the gift for a different species, that Pokemon
  still gets FLY and the badge exemption. Older saves whose gift lost
  FLY get their badge exemption back on load.

## 1.3.1

- For mod authors (see INTEGRATION.md in the repository): flight state
  is exported (`isFlying`, `altitude`, `mount`), the
  `mod.free_fly.takeoff` and `mod.free_fly.landed` events broadcast
  the flight lifecycle from every path a flight can end, follower mods
  can opt out of the built-in handling by exporting `freeFlyAware`,
  and `registerSpriteSource` lets sprite packs offer in-air art.

## 1.3.0

- Wilds of Kanto integration: with that mod enabled, the mount wears its
  per-species "levitates" art (splash keyed out, sized by dex height)
  instead of the generic bird/monster sheets. Deliberately not its
  Sprite Style setting: those styles are ground walk cycles with no
  flying poses, so the chosen style shows on the ground while the
  levitates sheets (that mod's only in-air art, style-independent by its
  own design) rule the sky. Species without one keep the generic sheets.
- Followers fly or sit out: with PokePC Followers installed (or Yellow's
  own Pikachu), a FLYING-type follower trails just below you through the
  air, wearing the same art the mount resolver picks so the pair reads
  as one style, sized by its own dex height. Any other follower, and the
  mon currently carrying you, sits the flight out and walks back at your
  side on landing. Ground follower art stays whatever the follower mod
  chose.
- The quick-start gift is now a PIDGEOT (same level, new dialogue).
  Saves that already took the Pidgey keep working: same taken flag, the
  badge exemption stays on the mon, and the old-save migration now
  matches the whole evolution line so an evolved gift stays exempt.
- Fix: re-entering Pallet Town (teleport, fly, walking back) no longer
  stacks duplicate gift NPCs; sessions that already collected twins
  self-heal on the next map entry.
- Wing flap eases with mount size: an Articuno beats its wings about a
  third slower than the old fixed rate; Pidgey-sized mounts unchanged.
- Takeoffs and landings move like the wild flyers'. The mount climbs on
  a diagonal (a short forward drift, dropped the moment you steer), and
  a land press while moving swoops in along your heading, skimming the
  last cell, instead of stopping dead and sinking. Wings flap faster in
  transitions than on the cruise, and the voxel ride height now ramps
  in and out with them rather than popping to cruise height. If an NPC
  wanders onto the spot mid-descent the mount pulls back up.
- Assisted landing: pressing land over a roof, tower facade or anything
  else unlandable now glides you to the nearest spot you could set down
  on and lands there, instead of bumping. Dry land beats water, doormats
  and occupied cells are skipped, and south is tried first so a building
  tends to drop you at its entrance. Steering, B or another whistle tap
  cancels the glide; if nothing within twelve cells is landable you get
  the old bump.
- Voxel camera, per rung: the follow factor keys on each rung's pitch
  read live from the voxel mod's own angle ladder (which includes FULL
  and the experimental person modes), and the 75-degree orbit lifts to
  the rider through the scene's placed-camera seam (the battle-camera
  mechanism): same centre, pitch and fov, focus raised to flight height.
  First/third person and battle cameras are never touched.
- Flat 2D flies steady: camera and sprite both hold constant altitude
  (the hover bob read as pixel jitter against a fixed camera); the wing
  flap carries the motion. Voxel keeps its hover.
- Quick Select: the "You don't have a BICYCLE" tap message is gone for
  real. Its wrapper arms off the raw press queue after the inner chain
  runs, so the press edge is now consumed at press time, not release.
- Voxel: constant 52px ride. The scene's building volumes cap at 48px,
  so this clears every small building everywhere with no climbs or
  push-ups at all; fence-hop immunity unchanged. Towers stay
  facade-blocked. The camera follows the constant total rather than the
  per-cell part, which removes the upward lurch over the top half of
  roofs (their upper rows mix in zero-height flat-class cells; the card
  itself was always level, the camera wasn't). The follow tightens with
  the voxel rung, so at 75 the rider sits near centre instead of
  reading far away at the top of the frame.

## 1.2.0

- Seam smoothness while flying: the crossing step now keeps flight
  speed (crossConnection bypasses tryMove, so it ran one step at walking
  pace: a visible hitch at every seam), and the rider ghost re-attaches
  in the same frame the entity list is rebuilt.
- Viridian Forest and the four Safari Zone areas count as open sky
  (they share the forest canopy tileset): take off, fly and land there.
  The Safari Game's step counter keeps ticking while airborne, so flight
  never grants extra safari time. Caves and buildings remain no-fly.

- Voxel: the rooftop compensation is applied instantly instead of eased,
  which removes the hop the rider did over every fence and small object
  (the scene snaps its ground height per cell; the ease lagged it).
- Seam prefetch: while airborne, the maps ahead (every connection of
  the current map, and their connections one hop further) are warmed
  into the engine's map cache at one load per tick, so fast flight
  crosses seams without the load hitch. In voxel, the same prefetch also
  queues each warmed map's chunk mesh through DRAMATIC_SHAPE's own build
  pump (the identical body-only request its scene makes for neighbours),
  so a flown-into map doesn't drop to the flat 2D fallback while it
  meshes.
- Very tall buildings are no-fly walls: an exterior door whose interior
  spans three or more floor maps (dept store, Silph Co, Pokemon Tower,
  Celadon Mansion) marks its building footprint as blocked while
  airborne, so you fly up to the facade and bump instead of clipping
  through. Derived from map data, never an authored list; small houses
  stay fly-over. Basements don't count as floors, cave interiors never
  qualify (Seafoam, Mt Moon, Victory Road stay flyable), and the bar is
  four floors above ground, so Cinnabar's mansion with its small drawn
  exterior stays fly-over while the true towers block. The footprint
  floods from the tower's door through building-class cells only (the
  shape profile marks walls "upright"; trees, fences and signs are other
  classes and never chain the wall into a neighbour), wide enough to
  cover Silph Co's full drawn slab, so its rear face blocks too.
  Enclosed walkable pockets inside a tower footprint (the dept store's
  rooftop plaza) seal while airborne, so towers can't be crossed via
  their roofs; walking out onto a roof and taking off still works.
- Performance: the whole outdoor world stays resident while you fly.
  All 36 outdoor maps (under a megabyte of block data) are warmed once
  at one load per six ticks (always yielding the frame to the voxel
  mod's own mesh builds) and marked protected from the engine's cache
  eviction, so seam crossings never load anything and the LRU churn that
  dragged the Cycling Road corridor down is gone entirely. Indoor
  spaces are untouched by this mod on principle: they keep their FULL
  vanilla cache budget (the resident outdoor world never counts against
  the engine's cap), and the no-bicycle SELECT tap only exists outdoors,
  so inside a building quick select behaves exactly as stock.
- Voxel ride height is a constant total above the ground plane (>= 66px,
  measured against the profile's flat 16px solids and the scene's 48px
  volume cap), so every small building clears at default altitude
  without raising the option, and the ride stays level.
- Fix: tapping SELECT with no bicycle no longer also shows Quick
  Select's "You don't have a BICYCLE" (its raw press-queue branch saw
  the tap before we consumed it).
- Ledges no longer hijack an airborne step into the vanilla hop (the
  arc used to stack on the flight lift); a flyer just crosses them.
- Voxel: visual flight height raised to 75% (was 60%), balanced by the
  camera tracking only part of the lift so the rider reads smaller and
  further away. An earlier build used a real zoom rung for this, which
  enlarged the rendered chunk set and stepped up the shadow-map
  resolution: that was the building lag while airborne, and it's gone.

## 1.1.0

- Eligibility defers to the engine and other mods: the species must be
  HM02-compatible per the MERGED data (so compatibility-expanding mods
  count), and "knows FLY" is decided through the engine's
  fieldmove.eligibility chain, so HM-relaxing mods like qol_toggles'
  FIELD MOVES ALL unlock FREEFLY exactly as they unlock FLY itself.
  Water landings route SURF through the same chain. This mod adds no
  eligibility rules of its own.
- Quick Select integration: with jj_quick_select installed (and only
  then), a FLY WHISTLE key item appears in the bag. Register it to a
  SELECT+direction slot and it toggles flight: takeoff with the first
  eligible partner, landing while airborne. With no BICYCLE in the bag,
  tap-SELECT defaults to flight instead of the "You don't have a
  BICYCLE" message (hold+direction slots keep working); owning a bicycle
  restores Quick Select's native tap. Without quick select none of this
  exists and nothing changes.

## 1.0.0

- 1.0.0: first public release. QUICK START option (default on) gates
  the Pallet Town gift Pidgey; MIT license.

## 0.12.0

- 2D riding reads as riding: the rider draws first, tucked low, and the
  mount draws over it, so the crop line hides behind the mount's body
  instead of a head floating above a gap.
- Voxel: the visual flight height runs at 60% while a voxel pipeline is
  active, so the card stops looming at the pitched camera; 2D keeps the
  full altitude, and rooftop clearance still applies on top.

## 0.11.3

- While airborne, the only wild battle that can start is one this mod
  asked for (interception). Ground roamers from other mods
  (overworld_encounters) collide by ground cell and were battling
  overflying players; their battles are now gated at BattleState.newWild
  until you land.

## 0.11.2

- Cockpit view keys off FirstPerson.hidePlayer() (true only when the eye
  hides your card) instead of engaged(), which was also true in third
  person; a one-shot log line reports why the overlay is or isn't
  drawing.
- AIR ENCOUNTERS now governs aerial interception. Airborne grass rolls
  ended with 0.11.1's step-trigger skip, so visible birds are the one
  source of airborne battles, and this option is their switch.

## 0.11.1

- Step triggers no longer fire under an airborne player: locked-door
  scripts ("The door is locked!"), gate guards, spinner tiles and poison
  step ticks all wait until you land.

## 0.11.0

- First-person rider view: while airborne with DRAMATIC_SHAPE's first
  person engaged, the mount draws bottom-center of the view, back-facing,
  flapping and bobbing, sized by its dex scale. First person hides the
  player card (which IS the mount), so this is how the rider sees their
  bird.

## 0.10.1

- Safety: loading a save always grounds the flight state machine, so a
  stale airborne phase can never follow the player into a fresh save.

## 0.10.0

- Voxel first/third person: movement works airborne (their FreeMove runs
  its own collision, now wrapped with a flight-scoped permissive window),
  and the mount is visible because it becomes the player's sprite sheet
  for the flight's duration; the walking sheet returns on landing.
- Hard guarantee against indoor flight: entering any non-outside map
  (caves included) while airborne ends the flight on arrival, on top of
  the existing takeoff and door gates.

## 0.9.6

- Flying over the Cycling Road no longer triggers the "You need a
  BICYCLE" alert or a mid-air force-mount; forced-movement tiles only
  apply again once you land on them.

## 0.9.5

- An aerial interception plays the caught species' cry, so a battle
  never starts without an audible cause.

## 0.9.4

- Shared helpers (icon-class mounts, dex scale, type/move checks) moved
  to the monorepo's shared/skylib.lua, synced in as lib/shared/. No
  behavior change.

## 0.9.3

- Fix: the sea-crossing ask's cooldown never decayed, so answering TURN
  BACK silently blocked all later attempts. It now re-asks on each try
  (1-2s apart) until the player says CROSS.

## 0.9.2

- Migration: saves from before 0.9.0 re-mark the gift PIDGEY (first
  FLY-knowing Pidgey when the taken flag is set), so BADGE CHECKS keeps
  exempting it and FREEFLY reappears.

## 0.9.1

- The mount is sized by its dex height (0.85x-1.6x): a Charizard carries
  you visibly bigger than a Pidgey, the rider sits higher on a taller
  mount, and the shadow scales to match.

## 0.9.0

- BADGE CHECKS option (default on): FREEFLY wants the THUNDERBADGE and
  water landings want the SOULBADGE, like vanilla's field moves. The
  Pallet gift Pidgey is exempt from the fly check (marked on the mon, so
  it persists in the save); the surf check has no exemption.

## 0.8.1

- FREEFLY only appears on mons whose species can learn HM02 FLY (the same
  tmhm list the machine-teach path checks), on top of knowing the move. A
  save-edited or mod-injected FLY on an ineligible species no longer
  offers a ride.

## 0.8.0

- Sea-crossing confirm: an airborne seam whose landing tile is water asks
  "That looks dangerous!" once per map (CROSS / TURN BACK), remembered in
  the save. Story-gated maps still hard-refuse first.
- Mount identity: you ride the mon you picked. Its party-icon class maps
  to a real walker sheet (bird/monster/seel/fairy), so Charizard carries
  you as the monster sprite, works in voxel too. Icon-only classes keep
  the bird.
- Water landing: B over water with a SURF-knower in the party sets you
  down surfing. Taking off while surfing dismounts into the air, so
  fly-surf-fly round trips work.

## 0.7.0

- STORY GATES (default on): flying across a seam into a badge-gated map
  you haven't earned bounces you with "A fierce wind blows you back!".
  Driven by the engine's own field.badgeGates data (Route 23's guard
  ladder, gate-building badges), so modded gates are respected too. Turn
  the option off for full sandbox flight.

## 0.6.0

- Aerial interception: while airborne, brushing a wild_skies flyer starts
  that exact wild battle, consumed through wild_skies' exports API. Short
  cooldown so a battle can't chain-trigger.
- Options pane: ALTITUDE (LOW/MED/HIGH), FLY SPEED (NORMAL/FAST/TURBO),
  AIR ENCOUNTERS toggle, TRAINERS SPOT YOU hardcore toggle. Altitude
  changes apply mid-flight.
- Landing feedback: the shadow shrinks with height and turns green over
  ground you can land on; a refused landing bumps audibly.
- Performance: the voxel ground-height lookup is cached per cell, the
  wild_skies handle resolves once per load, and the trainer-sight gate is
  hot-reload-swappable.

## 0.5.0

- Airborne encounters filter to FLYING species instead of being fully
  suppressed: flying over grass can flush a Pidgey, never a Rattata. A
  battle you win or flee resumes the flight.

## 0.4.1

- Voxel: altitude is absolute now. The scene adds the ground height back
  under the card, so buildings no longer stack on top of the cruise
  height; the lift shrinks over roofs (min 10px clearance), read from the
  voxel mod's own TileShape data via its exports.lib.
- The camera (and with it the tilt-shift focus band) follows the bird
  instead of the ground point, so the rider stays sharp in voxel and
  centred in 2D. Cell-to-cell height changes ease instead of snapping.

## 0.4.0

- Cruise altitude raised 16 -> 56 px so flight clears voxel rooftops (a
  6-row house extrudes to 48px); climb rate raised to match.
- Blacking out ends the flight: you wake at the heal point grounded
  instead of still airborne. A battle survived mid-air keeps you flying,
  since force-landing could drop you on water.

## 0.3.1

- Fix crash on FREEFLY: the rider ghost entity lacked px/py, which the
  overworld's y-sort and the voxel capture both read.

## 0.3.0

- The ride now shows in voxel and tilt modes: the player's billboard
  becomes the flapping bird and a ghost rider entity carries the player
  figure seated above it. The flat 2D composite is unchanged.

## 0.2.0

- A Pidgey waits in Pallet Town: talk to it and it joins at L10 already
  knowing FLY, then despawns for that save.
- Riding look: airborne the player sits on the bird sheet (mount + rider
  composed from the player's own cache), with flapping wings.
- Flight crosses map seams over water; the connection landing check is
  gated while airborne.
- Takeoff plays the FLY jingle.
- FREEFLY no longer requires the THUNDERBADGE, only a mon that knows FLY.

## 0.1.0

- First proof of concept: FREEFLY party action, free-roam flight with lift
  and shadow, B to land on walkable ground, encounter/warp/trainer/save
  gating while airborne.

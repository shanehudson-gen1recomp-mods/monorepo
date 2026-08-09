# Free Fly

Lets a party member that knows FLY carry you around the overworld. Take
off anywhere outdoors, fly over trees, water, fences and rooftops, cross
into neighbouring routes (the sea included), and press the B button (X on
keyboard) over open ground to land. That's the whole mod: free flight, no dependencies.

[![Demo](https://raw.githubusercontent.com/shanehudson-gen1recomp-mods/monorepo/main/.github/free_fly-demo.gif)](https://www.loom.com/share/5867c264456040c8a37acc7e32f4c827)

*Click through for the demo video.*

Looking for a bigger mount system? Check out
[Dramatic Sky Ride](https://github.com/mfrtechconsult/dramatic-sky-ride):
it adds controllable flying, ground and surf mounts with stamina, boost
and airborne battles, and it depends on the
[Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod)
plus a follower-sprite provider. Free Fly is the small alternative: one
mechanic, no dependencies, and it works in the flat 2D game as well as
in voxel.

## Getting airborne

1. Have a party member that can use FLY. The species must be
   HM02-compatible in the game data (mods that expand compatibility
   count), and either know the move or have it unlocked by a mod that
   relaxes field-move rules, such as qol_toggles' FIELD MOVES ALL. This
   also means Red and Blue's Charizard needs such a mod, since only
   Yellow made it HM02-compatible.
2. Open its party submenu and pick FREEFLY.
3. Move as normal. The shadow under you turns green over ground you can
   land on; press the B button (X on keyboard) to set down. Over a roof
   or anywhere else unlandable, the same press glides you to the nearest
   open spot and lands there (steer or press B again to cancel the
   glide). Blacking out also grounds you.

### Flying from a shortcut (Quick Select)

With [Quick Select](https://github.com/Roxas2712/pokemon-quick-select)
installed, this mod adds a FLY WHISTLE key item to your bag:

1. Open the BAG, move the cursor to FLY WHISTLE and press SELECT.
2. Pick a direction to register it, the same way Quick Select registers
   any item.
3. In the overworld, hold SELECT and press that direction: you take off
   with your first eligible partner, or land if you're already flying.

While you own no BICYCLE, simply tapping SELECT also toggles flight;
once you get the bicycle, the tap goes back to it and your registered
direction keeps working for flight. Without Quick Select installed, the
whistle doesn't exist and nothing changes.

### The quick-start Pidgeot

In vanilla you can't fly until late in the game: HM02 is in the Safari
Zone and using FLY needs the THUNDERBADGE. As an optional shortcut, a
Pidgeot stands in the middle of Pallet Town. Talk to it and it joins at
L10 already knowing FLY, and it skips the badge check, so you can fly
from the start of a new game. One per save. If you'd rather earn flight
normally, turn QUICK START off in the mod's options and the Pidgeot
never appears. Saves that already took the gift when it was a Pidgey
keep it, badge exemption included, even after it evolves.

## Options

| Option | Default | What it does |
|---|---|---|
| ALTITUDE | MED | LOW / MED / HIGH cruise height (32 / 56 / 80 px) |
| FLY SPEED | NORMAL | NORMAL / FAST / TURBO ground speed |
| AIR ENCOUNTERS | ON | brushing a wild_skies flyer starts its battle |
| TRAINERS SPOT YOU | OFF | hardcore: trainer sight works on flyers |
| STORY GATES | ON | badge-gated areas (Route 23) refuse airborne entry |
| BADGE CHECKS | ON | vanilla badges: THUNDERBADGE to fly, SOULBADGE to land on water (the gift bird is exempt from the fly check) |
| QUICK START | ON | the Pallet Town Pidgeot |

## What flying changes, and what it doesn't

While airborne: terrain doesn't block you, doors don't pull you in,
trainers don't spot you (unless you opt in), step events (locked doors,
gate guards, spinners, poison) wait for you to land, the Cycling Road
doesn't demand a bicycle until you land on it, saving is blocked (so a
save can never strand you mid-air), and ground battles can't reach you.
Crossing a seam whose landing is open water asks "That looks dangerous!"
once per map. Landing on water with a SURF knower in the party puts you
straight into surfing; taking off from a surf works too.

You still cannot fly indoors or in caves (entering one ends the flight),
into badge-gated areas you haven't earned, or away from a battle.

You ride the Pokémon you picked: its menu-icon class chooses the mount
sprite from your own imported game data, sized by its Pokédex height, so
a Charizard carries you visibly bigger than a Pidgey.

## Works well with

Tested alongside these, with the versions noted (later versions may add
overlapping features of their own, so check their changelogs):

- [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod)
  (tested with 1.6.0): full support. Flight clears voxel rooftops at a
  fixed absolute altitude, the camera and tilt-shift focus follow the
  bird, first and third person movement work airborne, and first person
  gets a cockpit view of your mount.
- [Overworld Wild Encounters](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters)
  (tested with 0.0.5): its roaming ground Pokémon cannot start battles
  against you while you fly over them; land and everything is vanilla.
- [wild_skies](../wild_skies): ambient flying Pokémon in the sky, which
  this mod lets you intercept mid-air for a battle.
- [double_battles](../double_battles): an intercepted bird can bring
  its flockmate as a second foe, and in an aerial double the mon
  carrying you is the one fighting beside your lead instead of
  whoever sits next in the party.
- [Quick Select](https://github.com/Roxas2712/pokemon-quick-select)
  (tested with 1.0.1): adds the FLY WHISTLE shortcut flow described
  above.
- [PokePC Followers](https://github.com/gamecorner-033/PokePCFollowers)
  (tested with 0.5.1): a FLYING-type follower takes to the air and trails
  just below you while you fly; any other follower waits out the flight
  and walks back to your side when you land. The same applies to Yellow's
  own Pikachu without the mod.
- [QoL Toggles](https://github.com/ShaneMcGovernIE/qol_toggles): its
  FIELD MOVES ALL setting unlocks FREEFLY (and water landings) on any
  HM-compatible partner without teaching the move, because this mod asks
  the engine's own field-move eligibility chain instead of keeping rules
  of its own.

## For mod authors

The full reference with payloads and examples is
[INTEGRATION.md](../INTEGRATION.md) in the repository. The short
version:

Flight state is exported: `isFlying()`, `altitude()` (pixels, 0 on the
ground) and `mount()` (the ridden mon's species and level, or nil).
Lifecycle events broadcast to every mod: `mod.free_fly.takeoff` carries
`{ species, level }`, `mod.free_fly.landed` carries `{ reason, x, y,
water }` where reason is `landed`, `indoors`, `blackout` or
`save_loaded`. Prefer these over reading the player's `freeFlying`
field.

Follower mods: by default this mod lifts a FLYING-type follower into
the air and hides any other during flight. Export `freeFlyAware = true`
and it keeps its hands off your follower entirely; react to the events
above instead.

Sprite packs with flying or hovering art can register it through
`exports.registerSpriteSource(source)` (and unregister by id); the
source shape is documented in INTEGRATION.md. Each of our mods bundles
its own resolver, so register with every mod you want to dress.

## Install

1. Download `free_fly-<version>.zip` from the
   [releases page](https://github.com/shanehudson-gen1recomp-mods/free_fly/releases).
2. In the game, open MODS from the pause menu (or press F10) and pick
   Import mod .zip.
3. Enable the mod in the same menu.

Updates show up in the mod manager automatically once installed.

Known rough edges are listed in `mod.card`.

Pokémon is a trademark of Nintendo; the Gen 1 games are © Nintendo /
Creatures Inc. / GAME FREAK inc. Unofficial fan mod; no ROMs, no
copyrighted game content. See the repository NOTICE.md.

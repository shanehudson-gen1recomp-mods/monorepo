# Wild Skies

Adds flying Pokémon to the overworld. Species come from each map's own
encounter table, so Pidgey and Spearow cross the early routes, the
Zubat line comes out at night and fills the caves at any hour, the
open sea belongs to Pidgeotto, Pidgeot and Fearow, and towns and
cities get rooftop birds that never pick a fight. They cast shadows,
flap their wings, and are sized by their Pokédex height.

Birds roam rather than commute: they wander the sky on lazy curving
paths, drift between heights in the same band the free_fly mount uses,
and sometimes arrive as a loose flock of the same species that wheels
together. They rest on the grass, and with the Dramatic Shape Voxel Mod
installed also on building roofs, then fly off when you get close or
when their visit is over.

The sky is busy, so most birds are scenery: only the bold ones (about a
third) will meet you head on. If you reach a bold low one before it
gets away, a normal wild battle starts with that species and level, and
the flock then keeps its distance for a while so fights never chain.
High flyers never trigger battles from the ground. If you also have
[free_fly](../free_fly) installed, flying into one starts its battle
mid-air, under the same rules.

And once in a very long while (1 in 1000 spawns), the bird crossing an
open outdoor sky is Articuno, Zapdos or Moltres, around L50. A legend
flies alone, is always bold, and never appears over towns, in caves or
under the forest canopy, so when you do see one it can actually be
fought and caught.

![Demo](https://raw.githubusercontent.com/shanehudson-gen1recomp-mods/monorepo/main/.github/wild_skies-demo.gif)

## Options

| Option | Default | What it does |
|---|---|---|
| SKY DENSITY | MED | LOW / MED / HIGH flyer caps and spawn cooldowns |
| BIRD SIZE | NORMAL | SMALL / NORMAL / LARGE / HUGE draw scale on top of dex height |
| GROUND BATTLES | ON | low birds (perched, landing, flushed) can battle a walking player |

## Works well with

Tested alongside these, with the versions noted (later versions may add
overlapping features of their own, so check their changelogs):

- [Overworld Wild Encounters](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters)
  (tested with 0.0.5): recommended. It puts visible roaming Pokémon on
  the ground while this mod handles the sky, and the flyers landing and
  taking off fit right in alongside its roamers. Battles don't overlap:
  its roamers handle the ground, this mod's birds handle the air.
- [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod)
  (tested with 1.6.0): flyers billboard in the 3D diorama with real
  altitude.
- [free_fly](../free_fly): aerial interception; also the source of the
  mount-riding flight this mod's birds share their sky with.
- [double_battles](../double_battles): a bumped bird brings its
  flockmate as the second foe, a summoned bird can be recruited into a
  wild double, and a sky bird that survives an undecided fight (you
  ran, or caught the other one) returns visibly to the air. Legendary
  sightings always stay 1v1, so a partner can never spoil the catch.

For a full mount system (controllable flying, ground and surf mounts),
see [Dramatic Sky Ride](https://github.com/mfrtechconsult/dramatic-sky-ride).
This mod only adds ambient wildlife.

## For mod authors

The full reference with payloads and examples is
[INTEGRATION.md](../INTEGRATION.md) in the repository. The short
version:

`exports.flyerAt(cellX, cellY, radius)` reads the nearest flyer,
`exports.takeFlyer(...)` consumes it and returns its species and level.
That is the supported seam free_fly's interception uses; nothing needs
to reach into this mod's internals.

`exports.spawnFlyer(species, level)` spawns one flyer on demand for
scenario mods: entry point, height and behaviour roll as usual, ambient
caps are not consulted. Returns the flyer id, or nil and a reason.

When a ground bump starts a battle, the event
`mod.wild_skies.flyer_bumped` broadcasts `{ species, level, cellX,
cellY }`; whenever `takeFlyer` consumes a flyer, whoever called it,
`mod.wild_skies.flyer_taken` broadcasts the same shape.

Sprite packs with flying or hovering art can register it through
`exports.registerSpriteSource(source)` (and unregister by id); the
source shape is documented in INTEGRATION.md. Each of our mods bundles
its own resolver, so register with every mod you want to dress.

## Install

1. Download `wild_skies-<version>.zip` from the
   [releases page](https://github.com/shanehudson-gen1recomp-mods/wild_skies/releases).
2. In the game, open MODS from the pause menu (or press F10) and pick
   Import mod .zip.
3. Enable the mod in the same menu.

Updates show up in the mod manager automatically once installed.

Known rough edges are listed in `mod.card`.

Pokémon is a trademark of Nintendo; the Gen 1 games are © Nintendo /
Creatures Inc. / GAME FREAK inc. Unofficial fan mod; no ROMs, no
copyrighted game content. See the repository NOTICE.md.

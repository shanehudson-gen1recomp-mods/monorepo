# gen1recomp-mods

Four mods for [gen1recomp](https://github.com/bryanthaboi/gen1recomp):
two that put Pokémon in the sky, one that dresses that sky in real PMD
art, and one that makes battles two-on-one, plus a developer tool. Each
works alone, but they're built to be used together.

<p>
<a href="https://www.loom.com/share/5867c264456040c8a37acc7e32f4c827"><img src=".github/free_fly-demo.gif" width="49%" alt="free_fly demo"></a>
<img src=".github/wild_skies-demo.gif" width="49%" alt="wild_skies demo">
</p>

*Left: free_fly (click through for the video). Right: wild_skies.*

**[free_fly](free_fly/)**: a party member that knows FLY carries you
around the overworld. Take off anywhere outdoors, fly over trees, water
and rooftops, cross into neighbouring routes and over the sea, then
press the B button (X on keyboard) to land. You ride the Pokémon you picked, sized by its Pokédex
height. Story gates and badges are respected by default and everything
is an option: altitude, speed, badge checks, and a quick-start Pidgey in
Pallet Town that skips the long wait for HM02.

**[wild_skies](wild_skies/)**: flying Pokémon from each map's encounter
table cross the overworld with shadows and flapping wings. They land,
rest, take off, and flush when you run at them; the Zubat line comes out
at night; sea routes get birds of their own. Low flyers can be caught
from the ground, high ones are scenery.

**[double_battles](double_battles/)**: wild and trainer battles against
two Pokémon at once: 1v2, full 2v2, trainer doubles and two-trainer
pairs, in the classic layout, the wide layout and Dramatic Shape's 3D
battle modes. Aim your moves and balls at either foe. With wild_skies
installed, a wild double can recruit a bird you can see flying nearby
as the second foe.

**[pmd_sky_sprites](pmd_sky_sprites/)**: wild flyers and your FLY mount
wear species-true, 8-direction Pokémon Mystery Dungeon animation sheets
in the air. The mod ships community-redrawn art only (PMDCollab
SpriteCollab, CC BY-NC 4.0). For all 251 species, drop a cartridge dump
of your own *Pokémon Mystery Dungeon: Explorers of Sky* (US) — a `.nds`
file — into the mod's folder and the official in-air animations read
straight off your cart while you play; nothing official ships and
nothing is extracted to disk. Unlocks true diagonal flight on Free Fly
mounts.

**Together**: the sky wild_skies fills becomes somewhere free_fly can
hunt. Fly into a passing Pidgey and its battle starts mid-air, with the
species and level it spawned with. Both also play well with the
[Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod)
(flight clears rooftops in 3D, first person gets a cockpit view) and
[Overworld Wild Encounters](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters)
(roamers on the ground, birds in the air, no crossed wires). Details and
tested versions are in each mod's README.

**[dev-hook-inspector](dev-hook-inspector/)** (dev tool): adds a HOOKS
entry to the START menu that lists every installed mod's public
exports and events, with descriptions read from the comments in their
source and each pick echoed to the console. For mod authors wiring
mods together; regular players don't need it.

## Install

Always download a mod from its own official mirror below. The mirror is
the repo your installed copy checks for updates, so a zip from anywhere
else (including this repo's old releases) may lag behind or stop
updating. Each release ships one `<mod>-<version>.zip`; grab the newest.

| Mod | Official mirror | Download |
| --- | --- | --- |
| Free Fly | [`free_fly`](https://github.com/shanehudson-gen1recomp-mods/free_fly) | [Releases](https://github.com/shanehudson-gen1recomp-mods/free_fly/releases/latest) |
| Wild Skies | [`wild_skies`](https://github.com/shanehudson-gen1recomp-mods/wild_skies) | [Releases](https://github.com/shanehudson-gen1recomp-mods/wild_skies/releases/latest) |
| Double Battles | [`double_battles`](https://github.com/shanehudson-gen1recomp-mods/double_battles) | [Releases](https://github.com/shanehudson-gen1recomp-mods/double_battles/releases/latest) |
| PMD Sky Sprites | [`pmd_sky_sprites`](https://github.com/shanehudson-gen1recomp-mods/pmd_sky_sprites) | [Releases](https://github.com/shanehudson-gen1recomp-mods/pmd_sky_sprites/releases/latest) |
| Dev Hook Inspector (dev tool) | [`dev-hook-inspector`](https://github.com/shanehudson-gen1recomp-mods/dev-hook-inspector) | [Releases](https://github.com/shanehudson-gen1recomp-mods/dev-hook-inspector/releases/latest) |

Then, in the game:

1. Open MODS from the pause menu (or press F10) and pick Import mod .zip.
2. Enable the mod in the same menu.

Updates show up in the game's mod manager automatically once a mod is
installed. Every mirror's README also lists all the other mirrors, and
the [org page](https://github.com/shanehudson-gen1recomp-mods) carries
the full directory.

Contributing or building from source: see [DEVELOPMENT.md](DEVELOPMENT.md).

Pokémon is a trademark of Nintendo; the Gen 1 games are © Nintendo /
Creatures Inc. / GAME FREAK inc. This is an unofficial fan project that
ships no ROMs and no copyrighted game content; see [NOTICE.md](NOTICE.md).

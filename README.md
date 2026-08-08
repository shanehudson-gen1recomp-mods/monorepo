# gen1recomp-mods

Two mods for [gen1recomp](https://github.com/bryanthaboi/gen1recomp)
that put Pokémon in the sky, plus a developer tool. The sky mods work
alone, but they're built to be used together.

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

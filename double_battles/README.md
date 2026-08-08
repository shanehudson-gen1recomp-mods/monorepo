# Double Battles

Wild battles against two Pokémon at once. This is the proof-of-concept
phase: 1v2, with full 2v2 and trainer doubles on the roadmap.

> **Known limitation:** 3D battle modes don't work well with doubles
> yet. Dramatic Shape's 2D-3D and STADIUM rungs stage one Pokémon per
> side, so a double battle there shows only the foe you're aiming at
> (the HUD and targeting still work). Play doubles in the CLASSIC or
> WIDE battle layout for the full two-Pokémon view.

Turn it on in Mod Settings: WILD DOUBLES set to SOMETIMES (about 30% of
wild encounters) or ALWAYS. A second foe from the map's own encounter
table appears beside the first, with its own HP bar. Both foes pick
moves every turn, and turn order runs across all three battlers using
the engine's normal speed rules. Each defeated foe pays out experience.
When the lead foe faints, the second steps up and the battle carries on
as a normal 1v1, so catching and running work as usual from there.

When you pick a move with both foes up, a target prompt follows: LEFT
and RIGHT swap between the two (a blinking frame shows your aim), A
locks it in, B goes back to the move menu. Throwing a ball with two
wild Pokémon out wastes the ball, like a trainer battle does; knock one
out first.

While aiming, the target's name, level and health show alongside the
blinking frame, and move animations follow your aim to the right
sprite. After a double battle ends you get a few calm steps before the
grass can roll the next encounter.

With [wild_skies](../wild_skies) installed, a wild double first looks
for a visible bird near you: the encounter holds a moment while it
flies to your side, and the battle starts against that exact bird.
Nobody nearby means the second foe rolls from the encounter list as
usual.

Trainers join in too: anyone with two or more able Pokémon sends two
out at once (TRAINER 2V2 in Mod Settings, on by default), refilling
from their bench as you knock them down, until the fight collapses to
a normal 1v1 against their last Pokémon.

In the target prompt you can also just click (or tap) a foe to aim at
it, and click it again to lock in.

For map authors: `double_battles:trainer_pair OPP_A idxA OPP_B idxB`
stages two trainers against your pair; nothing pairs up on its own.

## Proof-of-concept limits (roadmap items)

- Animations shift rigidly to the partner positions; long beams can
  look approximate.
- Link play with this mod enabled is refused by the handshake, by
  design: modded battle formats cannot stay in lockstep with unmodded
  peers.

## For mod authors

`exports.startWildDouble(speciesA, levelA, speciesB, levelB)` starts a
1v2 on demand, and the script command `double_battles:start` does the
same from map scripts. `exports.isDoubleBattle(battle)` tells you
whether a battle object is one of ours.

## Install

1. Download `double_battles-<version>.zip` from the
   [releases page](https://github.com/shanehudson-gen1recomp-mods/double_battles/releases).
2. In the game, open MODS from the pause menu (or press F10) and pick
   Import mod .zip.
3. Enable the mod in the same menu.

Pokémon is a trademark of Nintendo; the Gen 1 games are © Nintendo /
Creatures Inc. / GAME FREAK inc. Unofficial fan mod; no ROMs, no
copyrighted game content. See the repository NOTICE.md.

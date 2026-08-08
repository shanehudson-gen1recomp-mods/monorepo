# Double Battles

Wild and trainer battles against two Pokémon at once: 1v2, full 2v2,
trainer doubles and two-trainer pairs, in the classic layout, the wide
layout and Dramatic Shape's 3D battle modes.

> **3D battles:** with Dramatic Shape installed, both Pokémon on each
> side stand together on the arena, the aim frame blinks on the mon
> you're targeting, and the HUD follows whoever is acting. On the
> STADIUM rungs a side showing two Pokémon rides the flat battle cards
> (the 3D models pose one mon a side); the models return the moment
> that side is back down to one. Camera mods that ride Dramatic
> Shape's battle camera (Battle Cinematics, for example) frame the
> same scene and need nothing extra.

Turn it on in Mod Settings: WILD DOUBLES set to SOMETIMES (about 30% of
wild encounters) or ALWAYS. A second foe from the map's own encounter
table appears beside the first, with its own HP bar. Both foes pick
moves every turn, and turn order runs across all three battlers using
the engine's normal speed rules. Each defeated foe pays out experience.
When the lead foe faints, the second steps up and the battle carries on
as a normal 1v1, so catching and running work as usual from there.

When you pick a move with both foes up, a target prompt follows: a
menu names both Pokémon with a cursor on your aim (a blinking frame
marks the sprite too), any direction key moves the cursor, A locks it
in, B goes back to the move menu. Throwing a ball opens the same
prompt: aim at the Pokémon you want, A throws, B puts the ball back
in the bag. Catching one ends the battle and the other flees.

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

Switching works the same way: with your pair up, picking a Pokémon
from the party menu asks which of yours steps back (LEFT/RIGHT to aim,
a green frame marks it, A locks in, B cancels; clicking works too).
The recall spends that Pokémon's turn and resolves before any move
lands, so the switch-in can still be hit, exactly like gen 1's own
free-hit rule. Your other Pokémon keeps its move.

For map authors: `double_battles:trainer_pair OPP_A idxA OPP_B idxB`
stages two trainers against your pair; nothing pairs up on its own.

## Known limits (roadmap items)

- Animations shift rigidly to the partner positions in the flat
  layouts; long beams can look approximate. In 3D the burst plays at
  the pair's cell rather than on the exact partner.
- Pointer aiming is classic/wide only; in 3D use LEFT/RIGHT and A.
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

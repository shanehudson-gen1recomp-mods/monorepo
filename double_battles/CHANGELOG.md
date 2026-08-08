# Changelog

## 0.2.2

- The target prompts grew a menu: a vanilla-style box in the text
  area names both candidates (both foes when aiming a move or ball,
  both of yours when picking who steps back for a switch), with the
  cursor on the current aim. UP/DOWN move the cursor alongside
  LEFT/RIGHT. The box sits where the FIGHT menu does, in the classic,
  wide and 3D layouts alike.

## 0.2.1

- Aimed ball throws: a ball with two wild Pokémon out now opens the
  target prompt instead of wasting the throw. LEFT/RIGHT (or a click)
  aims, A throws at that Pokémon through the vanilla catch pipeline
  (its real catch rate, shakes and storage), B backs out and returns
  the ball to the bag. The toss animation follows the aim. Catching
  one Pokémon ends the battle and the other flees. Direct
  catchAttempt calls that skip the prompt keep the old refusal.

## 0.2.0

- 3D doubles: Dramatic Shape's battle modes now stage both Pokémon on
  each side. The voxel mod bills each side as one card textured from a
  160x144 canvas, so the adapter composes the pair into that canvas by
  their sticky anchors and both stand on the arena, shadows and all.
  The aim frame blinks on the targeted mon inside the scene, and the
  3D HUD (rendered outside our draw-scoped borrow) follows the acting
  partner. On the STADIUM rungs a doubled side falls back to the flat
  cards, since the models pose one mon a side; they return when the
  side is back down to one. Collapsed 1v1 endgames, trainer intro pics
  and non-double battles pass through untouched, pixel for pixel.
- Switch targeting: with your pair up, picking a bench Pokémon from
  the party menu now asks which of yours steps back (LEFT/RIGHT, a
  green blinking frame, A to lock, B to cancel, clicking works). The
  recall spends the leaving Pokémon's turn, resolves before any move
  lands (gen 1's own free-hit order), and your other Pokémon keeps its
  pick. This also fixes real bugs: the vanilla switch flow bypassed
  the doubles turn entirely, so the second foe skipped its move, a
  pass-B switch left the slots permanently swapped, and a foe aiming
  at the withdrawn Pokémon could hit its ghost. Switches now run
  through the doubles turn, both foes act, and hits aimed at a
  withdrawn body follow the replacement in.
- Attacks come from the right Pokémon: the engine resolves attack pic
  effects (the lunge, DIG's hide, the hit blink) from a side flag that
  always landed on the slot lead, so a partner's attack visibly played
  on the lead. The resolution now follows the battler the action
  actually involves, on both sides.
- Animations no longer shift sideways in 3D: the classic partner
  offset pointed the wrong way once the anim frame was remapped onto
  the arena axis. In a 3D scene the shift stands down and the burst
  plays at the pair's cell.
- For UI and scene mods (see INTEGRATION.md): scene detectors let a
  mod that stages the battlers itself tell doubles to stand its flat
  drawing down (`registerSceneDetector`), and `aimedBattler` /
  `focusBattler` expose what the prompts and the HUD borrow are
  showing. Camera-only mods riding Dramatic Shape's battle camera need
  nothing.

## 0.1.0

- Known limitation, stated up front: 3D battle modes (Dramatic Shape's
  2D-3D and STADIUM rungs) don't support doubles yet. Those scenes
  stage one Pokémon per side, so the mod now steps back there: the
  flat partner sprites stay off the 3D shot (they used to double every
  sprite on screen) and the scene shows the foe you're aiming at.
  Targeting and the HUD still work; CLASSIC and WIDE layouts show the
  full two-Pokémon battle.

- Classic layout, room for everyone: the second foe now draws at half
  size between the enemy HUD and your own sprite (it used to sit
  full-size on top of the HUD box), and your partner tucks against
  your lead's shoulder instead of straddling the foe's slot. The aim
  frame and click targets follow. When a side collapses to one
  Pokémon, the survivor steps into the vanilla full-size slot.
- The lead foe no longer hops 8 pixels when you switch aim: the slot
  redraw during the swap now uses the engine's own 7x7-tile padding,
  so it lands pixel-identical to vanilla's draw.

- Aiming holds the whole frame: the aimed foe now occupies the lead
  slot for as long as the target prompt is up, instead of a swap
  scoped to the battle's own draw call. HUDs painted after that call
  returns (gen1_modern_ui's battle cards draw from a render.hud hook)
  were still reading the resting lead, so switching targets never
  updated their name/HP panel. Sticky anchors keep the sprites where
  they stand, and the slots are restored before any turn logic runs.
- Once the doubles roll passes, a partner always joins: a map with no
  usable encounter slots or a partner source handing back a species
  the engine refuses no longer collapses the fight to 1v1. A stand-in
  RATTATA near the lead foe's level fills the slot as the last resort.
- Blacking out in a mod-launched double now revives and warps you to
  the heal point. Battles started through `startWildDouble`,
  `startTrainerDouble`, `startTrainerPair` and their commands were
  pushed without the engine's onFinish wiring, so a wipe dropped you
  back on the map where you stood with a fainted party, and the next
  encounter began in an unwinnable state.

- Proof of concept: 1v2 wild battles. Turn WILD DOUBLES on (SOMETIMES
  or ALWAYS) and wild encounters can bring a second foe, drawn beside
  the first with its own HP bar. Both foes pick moves every turn, turn
  order runs across all three battlers with the engine's own speed
  rules, and each defeated foe pays out its experience. Beat both to
  win; when the lead foe goes down the second steps up and the battle
  continues as a normal 1v1.
- Aiming: picking a move with both foes up asks which one to hit
  (LEFT/RIGHT to swap, A to lock in, B to go back). Throwing a ball
  with two wild Pokémon out wastes the ball, like gen 1's own trainer
  battles. The second foe takes its poison, burn and Leech Seed damage
  at the same timing the ruleset gives everyone else.
- Full 2v2: with YOUR SIDE set to PAIR (the default) and two healthy
  party members, your second Pokémon fights beside your lead. You pick
  a move and target for each in turn (the menu and HUD switch to the
  partner for its pick), foes spread their attacks across both of
  yours, and fallen leads are replaced by their partners on both sides.
- Aim and see it land: the target prompt shows the aimed foe's name,
  level and health, and move animations shift to whichever sprite the
  action actually involves, on both sides.
- Breathing room: after a double battle ends, encounter rolls stay
  quiet for a few steps.
- Trainer pairs: two distinct trainers can share the enemy side, each
  slot backed by its own trainer's party. Trainer A's bench replaces
  the lead slot; when A runs out, trainer B takes over the whole side
  for the vanilla endgame (payout is then B's, a known simplification).
  Staged by map authors with `double_battles:trainer_pair OPP_A idxA
  OPP_B idxB` or the `startTrainerPair` export; nothing pairs up on
  its own.
- Click to aim: during the target prompt you can click or tap a foe to
  aim at it, and click the aimed foe to lock it in. Keyboard aiming is
  unchanged.
- The WIDE layout's status panels now follow your aim too: they read
  the borrowed slot the same way the classic HUD boxes do, so picking
  the partner shows its name and health in both layouts.
- Target switching visibly switches again: the HUD borrow was swapping
  the slots the aim frame and the sprite pass read mid-draw, so the
  frame chased the swap (looking stuck) and the lead sprite popped in
  size. The sprite pass now unswaps for its portion (sprites are fully
  borrow-proof) and the frame follows the battler you actually picked.
- Your partner is mon-sized again: back sprites are stored at the
  GB's doubled size, so the partner draws at half scale, a Pokémon
  standing beside your lead instead of a wall of pixels.
- Wilds of Kanto touch battles reliably count as organic: the check
  reads its in-flight battle marker (the touched Pokémon is already
  despawned when the battle starts), so wild doubles trigger on them
  exactly like grass encounters.
- The selection HUD works everywhere now: the borrow moved to the
  root of the battle draw, so the classic boxes, the wide layout's
  panels AND Dramatic Shape's 3D arena panels all show the aimed or
  acting Pokémon's name and health. In the 3D arena the selected mon
  also steps onto the primary cell while chosen, which reads as the
  selection cue there.
- The partner stands its ground: positions are sticky now. When a lead
  falls, the survivor stays exactly where it stood instead of sliding
  into the empty spot; only an actual replacement (a trainer's next
  Pokémon) fills the vacancy. Animations, the aim frame and clicking
  all follow the real positions.
- Partners look native: they draw inside the engine's own battle pics
  layer, at full battle scale, clipped under menus and the HUD like
  the lead sprites, instead of floating on top of everything.
- Spread moves: Surf, Blizzard and Rock Slide hit both foes;
  Earthquake, Explosion and Selfdestruct hit everyone but the user,
  your partner included. The main target takes the full move; everyone
  else takes a three-quarters ripple hit through the normal accuracy
  and damage rolls. Spread moves skip the aim prompt. Mods can extend
  the list with `registerSpreadMove`.
- DOUBLES EXP option (FULL, the default, or HALF): HALF trims each
  foe's payout in these battles only, for vanilla-ish route pacing.
- Wilds of Kanto's visible overworld Pokémon count as organic again:
  their touch battles can double under the wild-doubles option, while
  scripted story battles stay solo.
- Smarter foes: enemy Pokémon pick their target first (piling onto a
  badly hurt slot) and then score their move against that exact
  target, instead of scoring against your lead and hitting someone
  else. The battle.enemy_action hook still overrides everything.
- The borrowed HUD box now drains HP like every other bar instead of
  snapping.
- Trainer pairs pay both prizes: the first trainer's money is banked
  at the handover and paid alongside the second's on victory.
- A one-body-per-mon safety net at the slot bookkeeping chokepoint:
  any switch path that would duplicate an active mon costs the partner
  slot with a logged warning, never a broken battle.
- In-battle items already do the right thing: X-items used during your
  partner's pick apply to the partner (the menu pass owns the slot),
  and healing items pick from the party list as gen 1 always did.
- A headless turn test now drives a real 2v2 through the two-pass
  menu, targeting and execution; it caught a real crash on arrival.
- Fixes from review: Safari Zone, ghost and demo battles never double
  (a safari double was unwinnable), you can no longer switch into the
  mon already fighting beside you, trainer class AI stops mid-pair
  switches that could duplicate a benched mon, a failed RUN no longer
  strands your lead's banked action, and script-launched story battles
  (Snorlax, the legendaries) stay 1v1.
- For mod authors (see INTEGRATION.md): `registerPartnerSource` lets a
  mod supply the second wild foe by priority around the built-in bird
  and encounter list, `tagOrganic` keeps a mod's own script battles
  doubles-eligible, and `double_started` / `partner_fainted` /
  `partner_joined` events broadcast what's happening.
- One HUD, not two: the partner sprites no longer carry their own
  little HP bars. The vanilla HP box is the single health display and
  follows whichever Pokémon you're aiming at or whichever one an action
  involves.
- The HUD follows your attention: aiming at the second foe (or any
  action involving a partner slot) borrows the vanilla HP box for it,
  so the stats you see always belong to the Pokémon in play. The
  partner's HP updates instantly in the borrowed box; the drain crawl
  stays with the lead slots.
- Trainer doubles: trainers with two or more able Pokémon now send two
  out at once (TRAINER 2V2 toggle, on by default). Their bench keeps
  the second slot filled as mons fall, the lead slot promotes its
  partner exactly like wild doubles, and the fight collapses to
  vanilla 1v1 (SHIFT prompt and all) once the bench runs dry. Balls
  keep vanilla's own trainer-battle behaviour. The
  `double_battles:trainer OPP_CLASS partyIndex` command and the
  `startTrainerDouble` export start one on demand.
- Visible recruitment: with wild_skies installed, a wild double looks
  for a visible bird near the player first. The battle holds while it
  flies to your side, then starts against it, real species and level
  and all. No bird nearby (or a swoop that fails) falls back to the
  encounter list as before, and a map change quietly cancels the held
  battle. Only bold birds answer, and the after-battle rest applies.

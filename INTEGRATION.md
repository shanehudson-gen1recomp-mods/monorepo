# Integrating with these mods

This is the reference for other mod authors. Everything below is a
supported seam: we test against it and try hard not to break it between
versions. Anything not listed here is internal and fair game for us to
rearrange, so please don't reach past the exports.

Both mods follow gen1recomp's two inter-mod channels. Exports are plain
functions you call, fetched through `mod.find(id)`, which returns nil
when the other mod is missing, disabled or failed to load. Events are
broadcasts: a mod may emit under its own `mod.<id>.*` prefix and anyone
can listen with `mod.events:on(name, fn)`.

```lua
local ff = mod.find("free_fly")
if ff and ff.exports.isFlying() then
  -- the player is airborne right now
end
```

Load order note: free_fly loads at priority 100 and wild_skies at 110.
If your mod loads earlier, call `mod.find` lazily (inside a handler or
tick) rather than at load time.

## free_fly

### Flight state

| Export | Returns |
|---|---|
| `isFlying()` | true while the player is airborne, takeoff and landing included |
| `altitude()` | current lift in pixels, 0 on the ground |
| `mount()` | `{ species, level }` of the mon carrying the player, or nil |

Prefer these over reading `player.freeFlying`. The field still exists
and still gets stamped, but the exports are the contract.

### Events

`mod.free_fly.takeoff` fires once per takeoff with
`{ species, level }` of the mount.

`mod.free_fly.landed` fires once per flight end with
`{ reason, x, y, water }`. The reason tells you how it ended:

- `landed`: a normal landing. `x, y` is the cell, `water` is true when
  the player set down on water and went straight into surfing.
- `indoors`: the player crossed into a cave or building, which ends the
  flight on arrival.
- `blackout`: the party wiped mid-air.
- `save_loaded`: a save swap grounded the state machine. No position in
  the payload, since the flight belonged to the previous save.

```lua
mod.events:on("mod.free_fly.landed", function(ev)
  if ev.reason == "landed" and ev.water then
    -- the player is now surfing at ev.x, ev.y
  end
end)
```

### Follower mods

By default free_fly manages the follower during flight: a FLYING-type
follower gets lifted into the air and trails the player, anything else
is despawned until landing, and the mon currently being ridden is never
also shown trailing.

That default only reaches followers driven through the engine's
`PikachuFollower`. If your mod moves followers from its own update
loop, free_fly cannot see them, and the usual player report is a
ground-bound follower walking under an airborne player, through water
and all.

So if you run your own follower system, export `freeFlyAware = true`.
free_fly then leaves followers completely alone, engine ones included,
and trusts you to react: listen for the takeoff and landed events, or
poll `isFlying()` / `altitude()` from your tick, and hide, ground or
lift your followers as fits your mod. Only declare the flag if you
actually manage followers; it switches off free_fly's own handling.

## Wrapping engine functions

Not an API of ours, but the interop rule that keeps all of the above
working. If your mod wraps an engine function (`OverworldState.update`
is the popular one), the slot you wrapped is a shared chain: other
mods wrap on top of you, and you never know who.

Two rules follow. Install your wrap once and keep it installed,
gating its body on an "active" flag when your feature toggles. And
never restore the function from a snapshot you captured earlier:
another mod's wrap may sit above yours by then, and writing your
snapshot back silently amputates everything wrapped after you. The
victim's feature just stops, with no error anywhere, and the player's
bug report lands on them, not you.

Our mods re-arm their own hooks when this happens (you'll see a
`[sky]` re-arming line in the log), but that heals us, not the chain.
If a hook of yours ever "stops working when both mods are installed",
look for an unconditional restore first.

## wild_skies

### Reading and consuming flyers

`exports.flyerAt(cellX, cellY, radius)` returns
`{ id, species, level, altitude }`
for the nearest live flyer within the radius, or nil. Newborn flyers
are invisible to this for their first moments, so nothing can collide
with a bird the player hasn't had a chance to see. Since the sky got
busy, only bold birds (roughly a third of ambient spawns) answer here
at all; the rest are scenery and scatter instead of battling. Birds
spawned through `spawnFlyer` are always bold.

`exports.takeFlyer(cellX, cellY, radius)` does the same lookup but also
despawns the flyer and hands you its identity. This is how free_fly
turns a mid-air interception into that exact bird's battle.

`exports.takeFlockmate(cellX, cellY, radius)` is takeFlyer for the
partner slot of a battle ALREADY born from this sky: it ignores the
after-battle rest (which exists to stop battles chaining, not to empty
the second slot of the one that already started) and never hands over
a legendary. Both sky mods use it to give a bumped or intercepted bird
its flockmate as the second foe.

Both calls also go quiet for about twenty five seconds after any battle
born from this sky (a ground bump, or any consumer taking a bird), so
heavy spawns decorate the route instead of chaining fights. Expect nil
during that rest and just try again later.

### Spawning flyers

`exports.spawnFlyer(species, level)` puts one flyer into the current
map on demand. Entry point, cruise height and behaviour roll the same
way ambient spawns do, but the ambient caps and cooldowns are not
consulted, so a scenario mod can crowd the sky if it wants to. Returns
the flyer id, or nil plus a reason ("no overworld" when there's no map
loaded, or the species has no usable sprite and no clear entry point).

### Summoning flyers

`exports.summonFlyer(cellX, cellY, opts)` calls the nearest bold bird
within `opts.radius` (default 8 cells) down to that cell. It returns a
summonId, or nil and a reason ("nobody near", or "resting" during the
after-battle rest). The bird flies hard to the spot; on arrival it
leaves the sky and `mod.wild_skies.flyer_summoned` fires with
`{ summonId, species, level, cellX, cellY }`. Every other ending (too
slow, the map changed, the bird was lost) fires
`mod.wild_skies.summon_failed` with `{ summonId, reason }`. Exactly one
of the two always fires, so deferring work on a summon is safe.
double_battles uses this to fly a visible bird to the player as the
second foe of a wild double.

### Events

`mod.wild_skies.flyer_bumped` fires when a low bird collides with the
walking player and starts its battle. Payload:
`{ species, level, cellX, cellY }`.

`mod.wild_skies.flyer_taken` fires whenever `takeFlyer` consumes a
flyer, whoever the caller was, with the same payload shape. Listen to
this rather than to each consumer's own events if you want to track
every bird that leaves the sky through the API.

### Shared SKY providers

A session or replay mod can own sky composition without Wild Skies knowing its
transport. Register with
`registerSharedSkyProvider(id, { requestClaim = function(map, id, context) ... end })`
and unregister with the same id. `context.domain` is `SKY` and
`context.airborne` says whether the contact came from a flying player.

The provider exchanges normalized snapshots through
`sharedSkyFieldSnapshot(map)`, `applySharedSkyFieldSnapshot(snapshot)`, and
`sharedSkyNeighborMaps()`. A snapshot is:

```lua
{
  domain = "SKY", map = "ROUTE_1", revision = 12,
  localAuthority = false,
  spawns = {
    { id = "bird-7", species = "PIDGEY", level = 5,
      x = 160, y = 96, alt = 56, vx = -32, vy = 4,
      facing = "left", mode = "roam", bold = true },
  },
}
```

Snapshots are bounded, copied at the boundary, sorted by stable id, and reject
malformed, duplicate-id, oversized, or stale-revision input. Only a field with
`localAuthority = true` runs private flock AI and spawns new birds; replicas
predict from canonical velocity between snapshots. Neighbor snapshots render
through the same resident ghost surface as solo play.

Shared contact is atomic. `takeFlyer` requests a claim and returns nil while it
is pending. The provider answers with `grantSharedSkyFieldContact(map, id)` or
`denySharedSkyFieldContact(map, id)`. It may also apply canonical removal with
`removeSharedSkyFieldSpawn(id)`. `clearSharedSkyField()` drops shared state and
returns immediately to the standalone resident-sky lifecycle.

## double_battles

### Starting doubles

| Export / command | Does |
|---|---|
| `startWildDouble(spA, lvA, spB, lvB)` | wild 1v2/2v2 on demand |
| `startTrainerDouble(oppClass, partyIndex)` | one trainer sends two |
| `startTrainerPair(oppA, idxA, oppB, idxB)` | two trainers share the side |
| `double_battles:start` / `:trainer` / `:trainer_pair` | the same from map scripts |
| `isDoubleBattle(battle)` | true for a decorated battle |

### The decorated battle shape (stable)

A decorated battle carries `battle.__double = true`, the extra battlers
as `battle.enemy2` and `battle.player2`, and populates the engine's
`sides[n].battlers` lists with both slots per side. These names are the
contract: chrome mods may read them. `battle.turn_started` gains an
`enemyAction2` field in doubles.

### Scripted battles and organic tagging

Script-launched wild battles (`start_battle` from map scripts) stay
1v1: story fights like Snorlax never gain a partner. A mod whose script
battles ARE organic encounters (wild_skies bumps, free_fly
interceptions do this) calls `exports.tagOrganic()` just before
queueing its `start_battle`, which restores doubles eligibility for
that battle.

### Scene detectors and the presentation surface

The doubles UI has two layers. The slot borrow is the universal one:
while you aim or a partner acts, that battler occupies `battle.enemy`
or `battle.player` for the whole frame, so any HUD that reads the lead
slots (the classic boxes, the wide panels, gen1_modern_ui's cards,
Dramatic Shape's HUD texture) names the right Pokémon without knowing
doubles exist. The flat layer is ours: partner sprites drawn in the
engine's pics layer, blinking aim frames, a rigid animation shift.

A mod that stages the battlers itself (a 3D scene, a cinematic
renderer) should register a scene detector so the flat layer stands
down while its scene is up:

```lua
local db = mod.find("double_battles")
if db then
  db.exports.registerSceneDetector({
    id = "my_scene",
    active = function(battle) return battle.mySceneFlag ~= nil end,
  })
end
```

While any detector reports active, doubles stops drawing flat partner
sprites and classic-coords aim frames and drops the animation shift;
the borrow keeps working. `unregisterSceneDetector(id)` removes one.
Dramatic Shape is detected built-in (its `battle.dramaticShapeShot`
stamp), and ships with a deeper adapter that composes both battlers
into its billboard textures. Camera-only mods that attach to Dramatic
Shape's battle camera (Battle Cinematics Stadium Camera, for example)
frame the same scene and need nothing.

To render doubles natively instead, read the stable surface:
`battle.enemy2` / `battle.player2`, `sides[n].battlers`, and each
battler's `dbAnchor` (1 = the vanilla lead spot, 2 = the partner spot;
sticky for the battler's life). `exports.aimedBattler(battle)` returns
the battler under the aim cursor while a target or switch prompt is
up, `exports.focusBattler(battle)` the partner the HUD borrow is
following mid-action; both are nil otherwise.

### Partner sources

`registerPartnerSource({ id, priority, provide })` lets a mod supply
the second wild foe. `provide(game, battle)` returns `species, level`
or nil to pass. Sources run by ascending priority; the built-in
wild_skies summoned bird sits at 50 and the encounter-list fallback at
100, so priority below 50 beats the bird and 50-99 runs between bird
and list. Default priority is 75. `unregisterPartnerSource(id)`
removes one. Wilds of Kanto could register its visible ground mons
here, for example. The flock sources both sky mods register sit at 40.

### Trainer pair sources

`registerTrainerPairSource({ id, priority, provide })` puts a second
trainer beside an organically started one: when a vanilla trainer
battle (a sight line, a talked-to NPC) passes through the push seam,
`provide(game, battle)` may return `oppClassB, partyIndexB` and the
battle becomes a full trainer pair, each slot backed by its own
trainer's bench, both payouts honored. Return nil to pass; a class the
engine refuses falls back to the ordinary trainer double. Firing is
the source mod's deliberate choice, so the TRAINER 2V2 option does not
gate it -- an NPC mod staging a gen 4 style "two trainers turn at
once" moment decides its own conditions. Staged pairs by command or
export (`startTrainerPair`) are unchanged.
`unregisterTrainerPairSource(id)` removes one.

With no source registered, pairs still happen on their own: when an
unfought plain trainer stands within PAIR DISTANCE of the engaged one
(touching, 2 or 3 cells; touching by default), the two fight you
together (the gen 3 pair convention), gated by the TRAINER PAIRS
option and by vetoes. Trainer classes registered by another mod (AI
Rivals' walkers, say) are exempt on both sides: their duels stay 1v1
and their characters never get conscripted as partners -- a pair
source registered by the owning mod is the opt-in, and it always
outranks the local pairing. Story battles never pair -- any
class#party with a scripted victory reward (badges, prizes, staged
scenes) is excluded on both sides, derived from the dataset. A pair
win beats both trainers: the partner's defeat flag and header event
land exactly as if fought alone.

Contract details a trainer mod should know:

- Building side B runs the engine's own trainer path, so the
  `trainer.party` hook chain fires a second time for a battle that is
  not "starting". `exports.buildingPairSide()` is truthy for exactly
  that build -- a mod tracking "the battle about to start" (a pending
  rival, say) should stand down while it is.
- `battle.oppClass` keeps trainer A's class for the whole battle, even
  after trainer B takes over the lead slot; the original trainer
  record survives on `battle.dbOriginalTrainer`.
- `exports.pairInfo(battle)` returns `{ classA, classB, partyIndexB,
  takenOver }` for a pair, nil otherwise -- the supported way to tell
  a pair from a TRAINER 2V2.
- `mod.double_battles.pair_decorated` fires when a pair forms:
  `{ battle, classA, classB }`.

### Ally sources and vetoes

`registerAllySource({ id, priority, provide })` picks WHICH of your
party mons fights beside your lead when a battle doubles. `provide`
returns a party mon object or nil to pass; a pick that is not a
healthy non-lead party member falls through to the default (the next
healthy bench mon). free_fly registers the mount here at priority 50,
so mid-air your ride is the one fighting beside you.

`registerDoubleVeto({ id, veto })` keeps specific battles out of the
automatic decorations: `veto(game, battle)` returning true blocks a
wild double before any partner is rolled, and keeps a trainer battle
from gaining an adjacent partner. Vetoes never affect explicit
requests -- the `start*` exports and registered pair sources fire
regardless. wild_skies vetoes its legendary sightings this way. `unregisterAllySource(id)` and
`unregisterDoubleVeto(id)` remove one each.

### Events

`mod.double_battles.double_started` fires as a decorated battle begins:
`{ battle, format, recruited }` where format is `1v2`, `2v2`,
`trainer` or `pair` and recruited is true when a summoned wild_skies
bird became the foe. `mod.double_battles.partner_fainted` and
`mod.double_battles.partner_joined` report partner-slot changes with
`{ battle, side, species }` (side 1 is yours).

## Sprite sources: offering in-air art

Both mods draw airborne creatures (wild flyers, the mount, the lifted
follower) through one shared resolver. Out of the box it borrows Wilds
of Kanto's "levitates" sheets when that mod is enabled, and falls back
to the engine's generic bird/monster/seel/fairy sheets.

If your mod ships flying or hovering art, you can register it as a
source and both mods will wear it:

```lua
local target = mod.find("free_fly")   -- and again for "wild_skies"
if target then
  target.exports.registerSpriteSource({
    id = "my_pack",
    resolve = function(exports, game, species, dex)
      local sheet = myArtFor(dex)
      if not sheet then return nil end
      return { image = sheet, frames = 6, walker = true, trueColor = true }
    end,
  })
end
```

The rules:

- A source needs an `id` or a `mod`. With `mod`, the source only runs
  while that mod is enabled, and its exports are passed as the first
  argument to `resolve`. With only an `id`, resolve gets nil there.
- `resolve(exports, game, species, dex)` returns a SpriteRenderer def:
  an `image` path, `frames`, `walker = true` for the engine's 6-frame
  stand/walk layout, `trueColor = true` for full-colour art. Return nil
  for species you don't cover and the resolver moves on.
- Defs must be animated (more than one frame). Flyers need wing flap,
  so a static image falls through to the next source.
- Set `stripWater = true` on the source if your sheets are drawn over a
  waterline like the levitates set; the splash colour gets keyed out
  before the art is used in the sky.
- Registered sources are tried before the built-ins, first registered
  wins among yours, and re-registering an id replaces the old one.
- Each mod bundles its own copy of the resolver, so register with every
  mod you want to dress. There's no shared global registry.

Sources are re-consulted when a spawn happens and whenever the source
mod's options change, so art that depends on a setting updates live.

## What we consume

For symmetry, the other side of the fence:

- Wilds of Kanto (`overworld_wild_spawns`): we resolve its levitates
  sheets through `exports.render.waterSpriteRegistry`. Its Sprite Style
  setting is deliberately not consulted in the air, because all three
  styles are ground walk cycles; the style you pick shows on land.
- PokePC Followers (`PokePCFollowers_VoxelMerge`): we read
  `exports.activeMon` to know who's following, and wrap the engine's
  follower update to lift or hide it during flight. Export
  `freeFlyAware` as above to opt out.
- Quick Select (`jj_quick_select`): free_fly registers a FLY WHISTLE
  item through its exports when it's installed.
- Crystal 251 (`CRYSTAL_251`): mostly we consume nothing directly,
  and that's the design. Its species land in the engine's merged data
  (`data.pokemon` with types and tmhm, `data.encounters`, icons), the
  same tables we already read, so Johto flyers and mounts work with
  no id-keyed code. Two deliberate seams on
  top: wild_skies probes any mod exporting a period-aware `ecology`
  (a table with `list()` returning rows of `{ mapId, terrain, period,
  group }`) to learn which species fly only at night, and
  double_battles announces every partner battler over the engine's
  `battle.battler_switched` event so Crystal's per-battler stat
  attach follows the whole double. wild_skies also declares
  `CRYSTAL_251` as an optional dependency purely for load order (both
  sit at priority 110). Solitary legends (the roamers and sanctuary
  encounters) are kept 1v1 by a species-keyed veto in double_battles;
  Lugia and Ho-Oh never roll in wild_skies' legendary sky slot.

If you maintain one of these and change a surface we use, open an issue
on this repo and we'll follow.

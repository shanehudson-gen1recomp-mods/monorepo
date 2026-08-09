# Development

The repo holds every mod, each with its own version in its
`manifest.json`. Any top-level directory with a `manifest.json` is a mod;
the scripts and the release workflow discover them, so adding a mod needs
no list edits anywhere. `shared/` is copied into each mod as
`lib/shared/` by the scripts, so packed zips are self-contained; edit
shared code only in `shared/`.

```sh
scripts/dev.sh       # install the mods into the gen1recomp checkout's mods/
scripts/test.sh      # dev.sh + run each headless suite on the installed copies
scripts/pack.sh      # validate + pack each mod into dist/<id>-<version>.zip
scripts/release.sh   # pack + publish new versions to the release mirrors
```

`dev.sh` targets the gen1recomp checkout's `mods/` folder (default
`~/Development/Projects/pokemon/gen1recomp/mods`, override with
`GEN1RECOMP_MODS_DIR`). `pack.sh` needs a gen1recomp checkout for modkit
(default `~/Development/Projects/pokemon/gen1recomp`, override
`GEN1RECOMP_DIR`).

In game, run with developer mode (`love . --developer` from a gen1recomp
checkout) and F5 hot-reloads the mods after `dev.sh`.

## Tests

Each mod has a headless load suite. `scripts/test.sh` syncs and runs them
all against the installed copies in the gen1recomp checkout's `mods/`
folder, the same files the game loads. To run one suite by hand:

```sh
cd ~/Development/Projects/pokemon/gen1recomp
MOD_DIR=mods/free_fly luajit mods/free_fly/tests/free_fly_load_test.lua
```

## Releases

Each mod releases on its own mirror repo
(`shanehudson-gen1recomp-mods/<id>`), the repo its manifest's `github`
field points at. That gives every mod its own version stream, updater
cache entry, and download stats; the game's updater assumes exactly one
mod per repo, which is why the monorepo itself never hosts releases.

Releases are manual only. Bump the mod's `manifest.json` version, test,
then either run `scripts/release.sh [mod ...]` locally or trigger the
Release workflow from the Actions tab. Both skip any mod whose manifest
version is already on its mirror, so releasing everything is safe. Each
publish tags the monorepo `<id>-v<version>` (for changelog ranges) and
re-syncs every mirror's README, which lists all the other mirrors.

The workflow needs the `MIRROR_RELEASE_TOKEN` secret: a fine-grained PAT
with Contents read/write on the org's repos. `scripts/release.sh` run
locally just uses your `gh` login and needs no setup.

Adding a mod: create `<id>/` with its `manifest.json` pointing `github`
at `shanehudson-gen1recomp-mods/<id>`, create that (public) repo, and
release. The README sync fills in the cross-links; add a row to the
install table in this repo's README by hand.

## The wrap chain (read before touching any engine hook)

The engine has a proper chained hook system, `Runtime.call(name,
vanilla, ...)`, with ~48 named choke points (`movement.collision`,
`encounter.roll`, `render.compose`, ...). It has NO per-frame world
hook. That gap is why every mod in the ecosystem raw-patches
`OverworldState.update`, and raw patching is a shared chain with no
owner: whoever "restores" a function from a snapshot amputates every
wrap installed after theirs, silently. This bit us for real (wilds of
kanto 1.12.x killed wild_skies' tick and free_fly's follower gate with
no error anywhere). The long-term fix is an upstream gen1recomp PR
adding a `world.update` hook; until then, the rules:

- Never restore a wrapped function from a snapshot. Install once, keep
  it installed, gate the body on an active flag.
- Any per-frame tick of ours rides `Sky.ensureUpdateWrap(OC, tickKey)`
  in `shared/skylib.lua`: ONE shared wrap for the whole mod family. It
  is tagged (`OC.__skyUpdateWrap`), dispatches every key in
  `OC.__skyTickKeys`, and the draw pass watchdogs it: if a foreign mod
  clobbers `OC.update`, the next drawn frame re-wraps whatever is
  current and prints a `[sky]` re-arm line. `OC.__skyTicking` is the
  re-entrancy guard that keeps ticks single when a foreign restore
  resurrects an older copy of our wrap inside the chain.
- Do NOT give each mod its own tagged wrap with its own watchdog. Two
  tags can't both equal `OC.update`, so the watchdogs re-wrap on top of
  each other every frame and the chain grows without bound. That
  regression shipped for about an hour; the shared tag is the fix.
- `wild_skies/tests/wild_skies_wrap_heal_test.lua` simulates the exact
  clobber ordering (foreign snapshot before our wrap, unconditional
  restore, stacked and resurrected wraps). Extend it when the wrap
  logic changes.

The external-facing version of these rules lives in INTEGRATION.md
("Wrapping engine functions"); keep the two in sync.

## Foreign mod seams we depend on

None of this is covered by anyone's compatibility promise. Versions in
brackets are what the code was verified against; re-check these spots
when a mod updates and something follower- or flight-shaped breaks.

**overworld_wild_spawns / "wilds of kanto"** [1.12.1] — its follower
ControlEngine (`lib/follower/control_engine.lua`) wraps BOTH
`OverworldState.update` and `PikachuFollower.update` and restores each
from install-time snapshots (the clobber source; see
`_restoreOverworldUpdateWrap` and the vanilla-hooks uninstall). Seams
free_fly uses:

- `mon.stopFollowing` on a save party mon is its per-mon STAY flag,
  honoured by every follower shape it has (`partyTrailMons` skips
  flagged mons, `getActiveFollowerMon` skips them for the stock
  follower). free_fly sets it on ground-bound mons while airborne and
  releases only the mons it flagged (`syncWildsFollowers`), so player
  STAY choices survive.
- Its trailer NPCs live in `ow.pokepcTrailers`; a mon trailer has
  `npc.pokepcMon` (the save mon) and `npc.pokepcTrailerKind == "mon"`,
  the lead-trainer NPC has kind `"trainer"`.
- The ControlEngine instance is reachable at
  `exports.follower.control`. Its `isFollowerCellAllowed` method is
  the single gate for ALL trailer pathing (goal seeding, stepping,
  ledge hops, catch-up); free_fly wraps it on the instance
  (`openWildsSkyLanes`) to allow any in-bounds cell while flying.
- `engine:removeTrailers(ow)` drops the trail and its next sync
  reseeds behind the player; free_fly uses that as landing recovery
  when a trailer is stranded on a now-illegal cell.

**PokePCFollowers_VoxelMerge** [0.5.1] — rides the engine's
`PikachuFollower` (`PF.current`, wraps `PF.update` politely, keeps the
chain). Everything free_fly does for it goes through the PF gate; no
bespoke code. It does not use `pokepcTrailers` despite wilds borrowing
that name.

**DRAMATIC_SHAPE** [1.6.2] **and forks (BATTLE_ART_VOXEL_FORK)**
[1.7.6] — first/third-person movement is a `FreeMove` module served by
the mod's exported lib (`exports.lib`, `V.require("FreeMove")`), with
`FreeMove.tick(state)` doing its own collision via `Map:isWalkableCell`
and `Collision.occupied` directly. free_fly discovers FreeMove in EVERY
loaded mod's exported lib (never key on one mod id; that's how the
BattleArt fence bug happened) and wraps each tick to open the
`MapMod.__freeFlyPermissive` window while the player flies. Other
DRAMATIC_SHAPE integrations in free_fly (camera placement,
ChunkMesher, VoxelState) are still keyed to `exports.DRAMATIC_SHAPE`
and are the next candidates if a fork misbehaves in voxel modes.

## free_fly's follower pipeline

All in `free_fly/main.lua`, inside the `game.ready` handler. Per frame
while flying, in order (our tick is the outermost layer of the frame,
which is what lets the dress win):

1. `followerModAware()` — any loaded mod exporting
   `freeFlyAware = true` switches ALL of this off; that mod owns
   follower flight (documented contract in INTEGRATION.md).
2. `syncWildsFollowers(true)` — stay-flag ground-bound wilds mons.
3. `openWildsSkyLanes()` — lazy, once-per-engine-instance install of
   the cell-gate wrap.
4. Trailer dress loop — every `pokepcTrailers` mon gets
   `dressFollower` at exactly `state.alt`.
5. The engine (PF) follower is handled separately in
   `PF.__freeFlyTick`, which runs from the self-healing
   `PF.__freeFlyEnsureWrap` dispatcher: non-FLYING mon or the mount
   itself → `removeFollower`; FLYING → dressed at `state.alt`.

`dressFollower` / `groundFollower` are exposed as `PF.__freeFlyDress` /
`PF.__freeFlyGround` because the overworld tick is defined earlier in
the file than they are (Lua locals aren't hoisted). The dress
re-asserts the flying sheet every frame, so a foreign engine's
land/swim sprite swaps never show; it only stashes a ground sprite
that isn't our own air sheet, or landing would restore the wrong one.

Landing: `syncWildsFollowers(false)` releases our stay flags,
`groundFollower` undresses, and the `trailersFlown` sweep asks the
engine to reseed if any trailer is stranded mid-fence.

`state.landmark` (the tower-facade scan that keeps assisted landings
off roofs) is cached per map id but a FAILED scan carries
`retry = true` and recomputes next frame; never cache a bad scan for
the whole visit.

## Debugging playbook

- "A per-frame feature silently stopped, no error" → a foreign wrap
  restore. Look for `[sky]` re-arm lines in the log; if they repeat
  every few seconds, some mod is clobbering `OC.update` per session
  and our heal is covering it.
- The game loads mods from BOTH the checkout's `mods/` and the LOVE
  save dir (`~/Library/Application Support/LOVE/pokemon-love2d/mods`),
  and the save dir WINS. `dev.sh` syncs both so shadowing is harmless,
  but a player report about "version X" means the save-dir copy.
  Third-party mods are only in the save dir; read them there.
- Player reports of mod-combo breakage bisect fastest by third-party
  version: their releases are zips in the save dir, and the manifest
  `version` field is authoritative.
- Follower misbehaving in the air: first check which path owns it
  (wilds trailers vs PF follower vs a freeFlyAware mod), then the seam
  list above for what its engine changed.

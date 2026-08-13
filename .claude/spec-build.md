# Spec / Build conventions

Conventions for the `spec` and `build` skills.

## Paths
- Specs: `docs/specs/`
- Plans: `docs/plans/`
- Progress tracker: `docs/PROGRESS.md`
- (docs/ is the gitignored local scratchpad by design; specs and
  progress stay local, only code and public docs are committed)

## Commands
- Test (all suites): `bash scripts/test.sh`
- Test (one suite): `cd ~/Development/Projects/pokemon/gen1recomp &&
  MOD_DIR=mods/<mod> luajit mods/<mod>/tests/<name>_test.lua`
- Build/pack: `bash scripts/pack.sh [mod ...]`
- Lint: none

## Commit style
Lowercase descriptive subject; release bumps read "<mod> <version>:
what changed", other work "<area>: what changed". Prose body, no
prefixes, no trailers, no em dashes.

## Repo notes
- Mods are top-level dirs with manifest.json. Shared code is edited
  ONLY in shared/ (scripts sync it to */lib/shared/).
- scripts/test.sh runs dev.sh first, then every suite against the
  installed copies in the gen1recomp checkout.
- Before touching any engine hook read docs/wrap-chain.md: never
  restore a wrapped function from a snapshot, per-frame ticks ride
  Sky.ensureUpdateWrap, and never wrap OC.draw (gen1_modern_ui
  fingerprints it; docs/foreign-mod-seams.md).
- Inter-mod surface lives in INTEGRATION.md; everything else is
  internal. Releases are manual per-mod via scripts/release.sh.
- Never key behavior on a specific foreign mod id when a capability
  probe works (the FreeMove lesson; flight state via the shared
  isFlying/altitude/mount exports).

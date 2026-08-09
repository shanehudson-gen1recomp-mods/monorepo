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

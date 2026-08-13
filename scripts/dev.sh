#!/usr/bin/env bash
# Link every mod into the gen1recomp checkout's mods/ folder for
# running from source. The engine enables PhysFS symlinks (conf.lua)
# and its loader handles dev-linked dirs, so the game always reads the
# live working tree; only shared/ still needs a copy step, into each
# mod's lib/shared/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${GEN1RECOMP_MODS_DIR:-$HOME/Development/Projects/pokemon/gen1recomp/mods}"

mkdir -p "$TARGET"

# LOVE overlays the save directory over the source checkout and the
# save dir wins, so a mod copy there (an imported release zip, say)
# silently shadows every dev sync. Linking both locations to the same
# working tree makes that shadowing harmless.
SAVE_MODS="$HOME/Library/Application Support/LOVE/pokemon-love2d/mods"

link_mod() {
  local src="$1" dest="$2"
  if [ -L "$dest" ]; then
    [ "$(readlink "$dest")" = "$src" ] && return
    rm "$dest"
  elif [ -d "$dest" ]; then
    rm -rf "$dest"
  fi
  ln -s "$src" "$dest"
  echo "linked $dest -> $src"
}

for m in "$ROOT"/*/manifest.json; do
  [ -f "$m" ] || continue
  mod="$(basename "$(dirname "$m")")"
  mkdir -p "$ROOT/$mod/lib/shared"
  rsync -a --delete --exclude 'README*' "$ROOT/shared/" "$ROOT/$mod/lib/shared/"
  link_mod "$ROOT/$mod" "$TARGET/$mod"
  if [ -d "$SAVE_MODS" ]; then
    link_mod "$ROOT/$mod" "$SAVE_MODS/$mod"
  fi
done

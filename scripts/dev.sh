#!/usr/bin/env bash
# Install every mod into the gen1recomp checkout's mods/ folder for
# running from source. The monorepo stays canonical; these copies are
# disposable test installs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${GEN1RECOMP_MODS_DIR:-$HOME/Development/Projects/pokemon/gen1recomp/mods}"

mkdir -p "$TARGET"

# LOVE overlays the save directory over the source checkout and the
# save dir wins, so a mod copy there (an imported release zip, say)
# silently shadows every dev sync. Keeping both locations identical
# makes that shadowing harmless.
SAVE_MODS="$HOME/Library/Application Support/LOVE/pokemon-love2d/mods"

for m in "$ROOT"/*/manifest.json; do
  [ -f "$m" ] || continue
  mod="$(basename "$(dirname "$m")")"
  mkdir -p "$ROOT/$mod/lib/shared"
  rsync -a --delete --exclude 'README*' "$ROOT/shared/" "$ROOT/$mod/lib/shared/"
  rsync -a --delete --exclude '.git' "$ROOT/$mod/" "$TARGET/$mod/"
  echo "installed $mod -> $TARGET/$mod"
  if [ -d "$SAVE_MODS" ]; then
    rsync -a --delete --exclude '.git' "$ROOT/$mod/" "$SAVE_MODS/$mod/"
  fi
done

#!/usr/bin/env bash
# Publish mods as GitHub releases on their per-mod mirror repos
# (shanehudson-gen1recomp-mods/<id>), one release per mod version. Each
# manifest's `github` field points at its mirror, so every mod gets its
# own version stream, updater cache entry, and download stats.
#
# Releases are MANUAL by design: run this after scripts/test.sh passes.
# A mod whose manifest version is already on its mirror is skipped, so
# releasing everything is always safe. Each publish also tags the
# monorepo <id>-v<version> so the next release's changelog has a range.
#
# Usage: scripts/release.sh [mod ...]   (no args = every mod)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="shanehudson-gen1recomp-mods"

mods=("$@")
if [ ${#mods[@]} -eq 0 ]; then
  # Tracked mods only, so a private in-dev mod dir can never be
  # released by the "release everything" default.
  while IFS= read -r m; do
    case "$m" in */*/*) continue ;; esac
    mods+=("$(dirname "$m")")
  done <<< "$(git -C "$ROOT" ls-files '*/manifest.json')"
fi

"$ROOT/scripts/pack.sh" "${mods[@]}"

for mod in "${mods[@]}"; do
  version="$(python3 -c "import json;print(json.load(open('$ROOT/$mod/manifest.json'))['version'])")"
  mirror="$ORG/$mod"
  tag="v$version"
  monotag="$mod-v$version"

  if gh release view "$tag" --repo "$mirror" >/dev/null 2>&1; then
    echo "$mod $version is already on $mirror, skipping"
    continue
  fi

  zip="$ROOT/dist/$mod-$version.zip"
  [ -f "$zip" ] || { echo "missing $zip (pack failed?)"; exit 1; }

  prev="$(git -C "$ROOT" tag -l "$mod-v*" --sort=-v:refname | head -1 || true)"
  range="${prev:+$prev..}HEAD"
  changes="$(git -C "$ROOT" log --no-merges --pretty='- %s' "$range" -- "$mod" shared | head -50 || true)"

  notes="Download the .zip and install it from the game: MODS > Import mod .zip. Installed copies pick up new releases through the game's mod manager.

Source: https://github.com/$ORG/monorepo (development happens in the monorepo; this repo hosts releases)."
  if [ -n "$changes" ]; then
    notes+=$'\n\n## Changes\n\n'"$changes"
  fi

  if ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$monotag" >/dev/null; then
    # Provenance markers, not artifacts: unsigned, and -c overrides
    # tag.gpgsign=true so a machine without the signing key still works.
    git -C "$ROOT" -c tag.gpgsign=false tag -m "$mod $version" "$monotag"
    git -C "$ROOT" push origin "$monotag"
  fi

  gh release create "$tag" --repo "$mirror" --title "$version" \
    --notes "$notes" "$zip"
  echo "released $mod $version -> https://github.com/$mirror/releases/tag/$tag"
done

"$ROOT/scripts/sync-mirror-readmes.sh"

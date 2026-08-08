#!/usr/bin/env bash
# Regenerate the README on every per-mod mirror repo
# (shanehudson-gen1recomp-mods/<id>). Each README links back to the
# monorepo and lists every other mirror, so finding one mod surfaces the
# rest. Runs from release.sh; safe to run by hand after adding a mod.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="shanehudson-gen1recomp-mods"

# Tracked mods only: an untracked mod dir is private dev work and must
# not leak into public READMEs or the org profile.
mods=()
while IFS= read -r m; do
  case "$m" in */*/*) continue ;; esac
  mods+=("$(dirname "$m")")
done <<< "$(git -C "$ROOT" ls-files '*/manifest.json')"
[ ${#mods[@]} -gt 0 ] || { echo "no mods found"; exit 1; }

# Quiet launches: a mod listed here releases on its own mirror but is
# left off the other mirrors' listings, the org profile, and any other
# public directory until it graduates. Its own mirror README still
# renders (without the family listing).
UNLISTED=("double_battles")

is_unlisted() {
  local candidate="$1"
  for u in "${UNLISTED[@]}"; do
    [ "$u" = "$candidate" ] && return 0
  done
  return 1
}

name_of() {
  python3 -c "import json;print(json.load(open('$ROOT/$1/manifest.json')).get('name','$1'))"
}

for mod in "${mods[@]}"; do
  # Demo gifs live in the monorepo's .github/; only tracked ones are
  # guaranteed to resolve on raw.githubusercontent.com.
  demo=""
  if git -C "$ROOT" ls-files --error-unmatch ".github/$mod-demo.gif" >/dev/null 2>&1; then
    demo=$'\n'"![Demo](https://raw.githubusercontent.com/$ORG/monorepo/main/.github/$mod-demo.gif)"$'\n'
  fi

  listing=""
  for other in "${mods[@]}"; do
    if [ "$other" = "$mod" ]; then
      listing+="- **$(name_of "$other")** (\`$other\`, this repo)"$'\n'
    elif ! is_unlisted "$other"; then
      listing+="- [$(name_of "$other")](https://github.com/$ORG/$other) (\`$other\`)"$'\n'
    fi
  done

  family="## All mods in this family

$listing"
  # An unlisted mod's own README carries no family section either way:
  # the point of a quiet launch is that nothing points at the family
  # and the family points at nothing here.
  if is_unlisted "$mod"; then family=""; fi

  readme="# $mod (Official mirror)

Installable releases of the **$(name_of "$mod")** mod for [gen1recomp](https://github.com/bryanthaboi/gen1recomp).
$demo
Grab the newest \`.zip\` from [Releases](https://github.com/$ORG/$mod/releases) and install it in-game: **MODS > Import mod .zip**. Installed copies get update checks through the launcher automatically.

Source code and issues live in the [mods monorepo](https://github.com/$ORG/monorepo); this repo only hosts releases.

$family"
  # Command substitution strips trailing newlines when reading the remote
  # copy back, so strip them here too or the comparison never matches.
  readme="$(printf '%s' "$readme")"

  current="$(gh api "repos/$ORG/$mod/contents/README.md" --jq .content 2>/dev/null \
    | python3 -c "import sys,base64;sys.stdout.write(base64.b64decode(sys.stdin.read()).decode())" \
    2>/dev/null || true)"
  if [ "$current" = "$readme" ]; then
    echo "$mod README up to date"
    continue
  fi

  sha="$(gh api "repos/$ORG/$mod/contents/README.md" --jq .sha 2>/dev/null || true)"
  args=(-f message="Sync mirror README" -f content="$(printf '%s' "$readme" | base64)")
  [ -n "$sha" ] && args+=(-f sha="$sha")
  gh api --method PUT "repos/$ORG/$mod/contents/README.md" "${args[@]}" --jq .commit.sha >/dev/null
  echo "$mod README updated"
done

# The org profile (github.com/$ORG) gets the same directory.
listing=""
for mod in "${mods[@]}"; do
  if ! is_unlisted "$mod"; then
    listing+="- [$(name_of "$mod")](https://github.com/$ORG/$mod) (\`$mod\`)"$'\n'
  fi
done

profile="# gen1recomp mods

Mods for [gen1recomp](https://github.com/bryanthaboi/gen1recomp). Each mod's repo here is its official mirror: grab the newest \`.zip\` from its Releases and install it in-game via **MODS > Import mod .zip**. Installed mods get update checks through the launcher automatically.

$listing
Development happens in the [mods monorepo](https://github.com/$ORG/monorepo); the per-mod repos only host releases."

current="$(gh api "repos/$ORG/.github/contents/profile/README.md" --jq .content 2>/dev/null \
  | python3 -c "import sys,base64;sys.stdout.write(base64.b64decode(sys.stdin.read()).decode())" \
  2>/dev/null || true)"
if [ "$current" = "$profile" ]; then
  echo "org profile up to date"
else
  sha="$(gh api "repos/$ORG/.github/contents/profile/README.md" --jq .sha 2>/dev/null || true)"
  args=(-f message="Sync org profile" -f content="$(printf '%s' "$profile" | base64)")
  [ -n "$sha" ] && args+=(-f sha="$sha")
  gh api --method PUT "repos/$ORG/.github/contents/profile/README.md" "${args[@]}" --jq .commit.sha >/dev/null
  echo "org profile updated"
fi

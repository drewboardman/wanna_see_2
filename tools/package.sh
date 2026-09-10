#!/bin/sh
# Build the release package that gets dropped into the game's mods folder.
#
# The archive contains a single top-level "i_wanna_see" folder so it can be
# extracted straight into <game>/mods/, giving the layout Darktide Mod
# Framework expects:
#
#   mods/i_wanna_see/i_wanna_see.mod
#   mods/i_wanna_see/scripts/mods/i_wanna_see/...
#
# Usage: tools/package.sh <version>   (e.g. tools/package.sh v1.2.0)
set -eu

version="${1:?usage: tools/package.sh <version>}"

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/release"
staging="$out/i_wanna_see"

rm -rf "$staging"
mkdir -p "$staging/scripts/mods"
cp "$root/i_wanna_see.mod" "$staging/"
cp -R "$root/scripts/mods/i_wanna_see" "$staging/scripts/mods/"

(cd "$out" && rm -f "i_wanna_see-$version.zip" && zip -r -q "i_wanna_see-$version.zip" i_wanna_see)
rm -rf "$staging"

echo "$out/i_wanna_see-$version.zip"

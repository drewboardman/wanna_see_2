#!/bin/sh
# Print the error blocks from the newest Darktide console log, so a mod failure can
# be read without hunting through the Proton prefix by hand. Written for a Steam
# Deck, where the game writes inside its compatdata folder and may live on a card.
#
# Usage: tools/deck_logs.sh [lines of context, default 25]
set -eu

context="${1:-25}"
app_id=1361210
relative="steamapps/compatdata/$app_id/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs"

candidates="$HOME/.steam/steam/$relative $HOME/.local/share/Steam/$relative"

# Darktide is often installed on the microSD card, which mounts under /run/media.
for mount in /run/media/mmcblk0p1 /run/media/deck/*; do
	candidates="$candidates $mount/$relative"
done

log=""
for directory in $candidates; do
	if [ -d "$directory" ]; then
		newest=$(ls -t "$directory"/*.log 2>/dev/null | head -1 || true)

		if [ -n "$newest" ]; then
			log="$newest"
			break
		fi
	fi
done

if [ -z "$log" ]; then
	echo "No console log found. Looked in:" >&2

	for directory in $candidates; do
		echo "  $directory" >&2
	done

	exit 1
fi

echo "Newest log: $log"
echo
echo "=== script errors ==="
grep -n -A "$context" -E '<<Script Error>>|<<Lua Error>>' "$log" | tail -100 || echo "(none)"
echo
echo "=== lines naming i_wanna_see ==="
grep -n 'i_wanna_see' "$log" | tail -30 || echo "(none)"

#!/bin/bash
# Builds the Counter-Strike: Source package in build/package (drag and drop it on the server's cstrike folder).
#   SPCOMP=/path/to/sourcemod/scripting/spcomp64 tools/build.sh
# Plugins for other games (TF2, Left 4 Dead) are compiled into addons/sourcemod/plugins/disabled.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SPCOMP=${SPCOMP:-spcomp64}
SRC=$ROOT/addons/sourcemod/scripting
OUT=$ROOT/build/package
OTHER_GAMES="War3Source_020_Dragonborn War3Source_021_Fluttershy War3Source_Addon_HalloweenBossHorseman
War3Source_Addon_NoSpySuicide War3Source_Addon_TF2MedicXPGoldMultiplier War3Source_Engine_Left4Dead
War3Source_Engine_XPGoldL4D War3Source_Engine_XPGoldTF"

rm -rf "$OUT"
mkdir -p "$OUT/addons/sourcemod/plugins/disabled" "$OUT/cfg"
cp -r "$ROOT/addons/sourcemod/configs" "$ROOT/addons/sourcemod/gamedata" "$ROOT/addons/sourcemod/translations" \
      "$ROOT/addons/sourcemod/scripting" "$OUT/addons/sourcemod/"
cp -r "$ROOT/sound" "$OUT/"
cp "$ROOT/cfg/war3source.cfg" "$OUT/cfg/"

failed=0
for sp in "$SRC"/*.sp; do
  name=$(basename "$sp" .sp)
  dest=$OUT/addons/sourcemod/plugins
  if grep -qw "$name" <<< "$OTHER_GAMES"; then
    dest=$dest/disabled
  fi
  if ! "$SPCOMP" "$sp" -i"$SRC" -i"$SRC/W3SIncs" -o"$dest/$name.smx" > "$ROOT/build/$name.log" 2>&1; then
    echo "FAILED: $name (see build/$name.log)"
    failed=1
  elif grep -q "warning" "$ROOT/build/$name.log"; then
    grep "warning" "$ROOT/build/$name.log"
  fi
done
rm -f "$ROOT"/build/*.log
[ $failed -eq 0 ] || exit 1
echo "$(ls "$OUT/addons/sourcemod/plugins" | grep -c smx) plugins, $(ls "$OUT/addons/sourcemod/plugins/disabled" | grep -c smx) for other games in plugins/disabled -> $OUT"

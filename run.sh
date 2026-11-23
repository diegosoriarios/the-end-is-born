#!/bin/zsh
# Run the game.
#
# LÖVE 11.5's native arm64 build runs LuaJIT in interpreter-only mode (no JIT
# module). Forcing the x86_64 slice via Rosetta enables the full LuaJIT JIT
# (~7x faster hot loops), which we need for thousands of enemies at 60fps.
# Falls back to native mode automatically if Rosetta is unavailable.

DIR="$(cd "$(dirname "$0")" && pwd)"

# Locate LÖVE: explicit override, Linux AppImage, macOS bundle, then PATH.
if [ -n "$LOVE_BIN" ]; then
  LOVE="$LOVE_BIN"
elif [ -x "$HOME/AppImage/love.AppImage" ]; then
  LOVE="$HOME/AppImage/love.AppImage"
elif [ -x "/Applications/love.app/Contents/MacOS/love" ]; then
  LOVE="/Applications/love.app/Contents/MacOS/love"
elif command -v love >/dev/null 2>&1; then
  LOVE="$(command -v love)"
elif command -v love2d >/dev/null 2>&1; then
  LOVE="$(command -v love2d)"
else
  echo "run.sh: cannot find LÖVE; set LOVE_BIN=/path/to/love" >&2
  exit 1
fi

case "$1" in
  --stress)  touch "$DIR/stress.flag";  shift ;;
  --stress2) touch "$DIR/stress2.flag"; shift ;;
  --smoke)   touch "$DIR/smoke.flag";   shift ;;
  --test)    touch "$DIR/test.flag";    shift ;;
  --life)    touch "$DIR/life.flag";    shift ;;
  --menu)    touch "$DIR/menu.flag";    shift ;;
  --shot)    touch "$DIR/shot.flag";    shift ;;
  --save)    touch "$DIR/save.flag";    shift ;;
  --content) touch "$DIR/content.flag"; shift ;;
  --ages)    touch "$DIR/ages.flag";    shift ;;
  --research) touch "$DIR/research.flag"; shift ;;
  --farm)    touch "$DIR/farm.flag";    shift ;;
  --grave)   touch "$DIR/grave.flag";   shift ;;
  --war)     touch "$DIR/war.flag";     shift ;;
  --assign)  touch "$DIR/assign.flag";  shift ;;
  --path)    touch "$DIR/path.flag";    shift ;;
  --spit)    touch "$DIR/spit.flag";    shift ;;
  --pair)    touch "$DIR/pair.flag";    shift ;;
  --ux)      touch "$DIR/ux.flag";      shift ;;
esac

if [ "$(uname)" = "Darwin" ] && command -v arch >/dev/null 2>&1 && arch -x86_64 /usr/bin/true 2>/dev/null; then
  arch -x86_64 "$LOVE" "$DIR" "$@"
else
  "$LOVE" "$DIR" "$@"
fi
rc=$?
# Harness flag files are consumed at load; remove them so the next plain run
# starts the game normally (and the next harness gets a clean pick).
rm -f "$DIR/smoke.flag" "$DIR/stress.flag" "$DIR/stress2.flag" "$DIR/test.flag" "$DIR/life.flag" "$DIR/menu.flag" "$DIR/shot.flag" "$DIR/save.flag" "$DIR/content.flag" "$DIR/ages.flag" "$DIR/research.flag" "$DIR/farm.flag" "$DIR/grave.flag" "$DIR/war.flag" "$DIR/assign.flag" "$DIR/path.flag" "$DIR/spit.flag" "$DIR/pair.flag" "$DIR/ux.flag"
exit $rc

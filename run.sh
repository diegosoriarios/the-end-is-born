#!/bin/zsh
# Run the game.
#
# LÖVE 11.5's native arm64 build runs LuaJIT in interpreter-only mode (no JIT
# module). Forcing the x86_64 slice via Rosetta enables the full LuaJIT JIT
# (~7x faster hot loops), which we need for thousands of enemies at 60fps.
# Falls back to native mode automatically if Rosetta is unavailable.

DIR="$(cd "$(dirname "$0")" && pwd)"
LOVE="/Applications/love.app/Contents/MacOS/love"

case "$1" in
  --stress)  touch "$DIR/stress.flag";  shift ;;
  --stress2) touch "$DIR/stress2.flag"; shift ;;
  --smoke)   touch "$DIR/smoke.flag";   shift ;;
  --test)    touch "$DIR/test.flag";    shift ;;
esac

if command -v arch >/dev/null 2>&1 && arch -x86_64 /usr/bin/true 2>/dev/null; then
  exec arch -x86_64 "$LOVE" "$DIR" "$@"
else
  exec "$LOVE" "$DIR" "$@"
fi

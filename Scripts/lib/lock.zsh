# Sourced by the build and test scripts. Only one of them runs at a time on this Mac: a second
# one waits for the first to finish. A script started by another that already holds the lock
# does not wait for itself.
homepad_lock() {
  [[ -n "${HOMEPAD_LOCK_HELD:-}" ]] && return 0
  local dir="$1/build/.lock"
  mkdir -p "$1/build"
  while ! mkdir "$dir" 2>/dev/null; do
    local owner
    owner=$(cat "$dir/pid" 2>/dev/null)
    # A lock whose owner is gone was left by a killed run.
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$dir"
      continue
    fi
    sleep 10
  done
  echo $$ > "$dir/pid"
  export HOMEPAD_LOCK_HELD=1
  HOMEPAD_LOCK_DIR="$dir"
}

homepad_unlock() {
  [[ -n "${HOMEPAD_LOCK_DIR:-}" ]] && rm -rf "$HOMEPAD_LOCK_DIR"
}

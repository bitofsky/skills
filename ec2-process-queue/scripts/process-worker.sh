#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${REMOTE_DIR:-/work/process-worker}"
IDLE_SLEEP_SECONDS="${IDLE_SLEEP_SECONDS:-10}"
PROCESS_SCRIPT="${PROCESS_SCRIPT:-./process-target.sh}"

cd "$REMOTE_DIR"
mkdir -p logs tmp
touch next completed failed next.lock

if [ ! -x "$PROCESS_SCRIPT" ]; then
  echo "missing executable: ${REMOTE_DIR}/${PROCESS_SCRIPT}" >&2
  exit 127
fi

write_idle_status() {
  local tmp
  tmp="$(mktemp "${REMOTE_DIR}/status.XXXXXX")"
  printf "%s\n" "$(date -Is) phase=idle next=$(wc -l < next 2>/dev/null || echo 0)" > "$tmp"
  mv -f "$tmp" status
}

pop_next() {
  flock next.lock bash -c '
    target="$(head -n 1 next 2>/dev/null || true)"
    [ -n "$target" ] || exit 1
    tail -n +2 next > next.tmp
    mv next.tmp next
    printf "%s\n" "$target"
  '
}

echo "$(date -Is) worker started in $REMOTE_DIR"

while true; do
  if target="$(pop_next)"; then
    echo "$(date -Is) START $target"
    if PROCESS_STATUS_FILE="${REMOTE_DIR}/status" "$PROCESS_SCRIPT" "$target"; then
      echo "$target" >> completed
      echo "$(date -Is) DONE  $target"
    else
      echo "$target" >> failed
      echo "$(date -Is) FAIL  $target"
    fi
  else
    write_idle_status
    sleep "$IDLE_SLEEP_SECONDS"
  fi
done

#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 '<record>'" >&2
  exit 2
fi

record="$1"
status_file="${PROCESS_STATUS_FILE:-}"

write_status() {
  [ -n "$status_file" ] || return 0
  mkdir -p "$(dirname "$status_file")"
  local tmp
  tmp="$(mktemp "${status_file}.XXXXXX")"
  if printf "%s\n" "$(date -Is) $*" > "$tmp"; then
    mv -f "$tmp" "$status_file"
  else
    rm -f "$tmp"
    return 1
  fi
}

write_status "phase=running target=$record"
echo "$(date -Is) PROCESS record=$record"

# Replace this sample with real one-target process logic.
# TSV example: IFS=$'\t' read -r id tenant date meta <<< "$record"
# NDJSON example: id="$(jq -r '.id' <<< "$record")"
sleep "${PROCESS_SLEEP_SECONDS:-2}"

write_status "phase=done target=$record"
echo "$(date -Is) PROCESS_DONE record=$record"

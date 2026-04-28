#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
WORKERS_FILE="${WORKERS_FILE:-workers}"
QUEUE_FILE="${QUEUE_FILE:-target_process.queue}"
DISPATCHED_FILE="${DISPATCHED_FILE:-target_process.dispatched}"
MAX_NEXT="${MAX_NEXT:-5}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-10}"
REFILL_PARALLELISM="${REFILL_PARALLELISM:-20}"
LOCK_FILE="${LOCK_FILE:-${QUEUE_FILE}.lock}"
ONCE="${ONCE:-0}"

touch "$QUEUE_FILE" "$DISPATCHED_FILE"

json_commands() {
  python3 - "$@" <<'PY'
import json
import sys
print("commands=" + json.dumps(list(sys.argv[1:])))
PY
}

wait_command() {
  local instance_id="$1"
  local command_id="$2"
  local status
  while true; do
    status="$(
      aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        --query Status \
        --output text 2>/dev/null || true
    )"
    case "$status" in
      Success|Failed|Cancelled|TimedOut|Cancelling) printf "%s\n" "$status"; return 0 ;;
      Pending|InProgress|Delayed|"") sleep 1 ;;
    esac
  done
}

worker_instances() {
  awk '
    NF && $1 !~ /^#/ {
      if (!seen[$1]++) order[++n] = $1
      dirs[$1] = dirs[$1] " " $2
    }
    END {
      for (i = 1; i <= n; i++) {
        id = order[i]
        sub(/^ /, "", dirs[id])
        print id "\t" dirs[id]
      }
    }
  ' "$WORKERS_FILE"
}

pop_local_targets() {
  local count="$1"
  flock "$LOCK_FILE" bash -c '
    count="$1"
    queue="$2"
    [ "$count" -gt 0 ] || exit 0
    [ -s "$queue" ] || exit 0
    head -n "$count" "$queue"
    tail -n +"$((count + 1))" "$queue" > "${queue}.tmp"
    mv "${queue}.tmp" "$queue"
  ' bash "$count" "$QUEUE_FILE"
}

return_local_targets_file() {
  local refill_file="$1"
  [ -s "$refill_file" ] || return 0
  flock "$LOCK_FILE" bash -c '
    refill_file="$1"
    queue="$2"
    cut -f2- "$refill_file" > "${queue}.returned"
    cat "$queue" >> "${queue}.returned"
    mv "${queue}.returned" "$queue"
  ' bash "$refill_file" "$QUEUE_FILE"
}

refill_instance_once() {
  local instance_id="$1"
  local remote_dirs="$2"
  local cmd_id status output refill_file encoded payload need count remote_dir target

  cmd_id="$(
    aws ssm send-command \
      --region "$AWS_REGION" \
      --instance-ids "$instance_id" \
      --document-name AWS-RunShellScript \
      --comment process-next-counts \
      --parameters "$(
        json_commands \
          "set -euo pipefail" \
          "for d in $remote_dirs; do mkdir -p \"\$d\"; touch \"\$d/next\"; printf '%s\t%s\n' \"\$d\" \"\$(wc -l < \"\$d/next\" 2>/dev/null || echo 0)\"; done"
      )" \
      --query 'Command.CommandId' \
      --output text
  )"
  status="$(wait_command "$instance_id" "$cmd_id")"
  [ "$status" = "Success" ] || return 0

  output="$(
    aws ssm get-command-invocation \
      --region "$AWS_REGION" \
      --instance-id "$instance_id" \
      --command-id "$cmd_id" \
      --query StandardOutputContent \
      --output text
  )"

  refill_file="$(mktemp)"
  while IFS=$'\t' read -r remote_dir count; do
    [ -n "${remote_dir:-}" ] || continue
    count="${count:-$MAX_NEXT}"
    need=$((MAX_NEXT - count))
    [ "$need" -gt 0 ] || continue
    payload="$(pop_local_targets "$need" || true)"
    [ -n "$payload" ] || continue
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      printf "%s\t%s\n" "$remote_dir" "$target" >> "$refill_file"
    done <<< "$payload"
  done <<< "$output"

  if [ ! -s "$refill_file" ]; then
    rm -f "$refill_file"
    return 0
  fi

  encoded="$(base64 -w0 "$refill_file")"
  cmd_id="$(
    aws ssm send-command \
      --region "$AWS_REGION" \
      --instance-ids "$instance_id" \
      --document-name AWS-RunShellScript \
      --comment process-next-refill \
      --parameters "$(
        json_commands \
          "set -euo pipefail" \
          "printf '%s' '$encoded' | base64 -d > /tmp/process-refill.tsv" \
          "while IFS=\$(printf '\t') read -r d item; do [ -n \"\$d\" ] || continue; [ -n \"\$item\" ] || continue; mkdir -p \"\$d\"; touch \"\$d/next\" \"\$d/next.lock\"; exec 9>>\"\$d/next.lock\"; flock 9; printf '%s\n' \"\$item\" >> \"\$d/next\"; flock -u 9; exec 9>&-; done < /tmp/process-refill.tsv" \
          "rm -f /tmp/process-refill.tsv"
      )" \
      --query 'Command.CommandId' \
      --output text
  )"
  status="$(wait_command "$instance_id" "$cmd_id")"

  if [ "$status" = "Success" ]; then
    awk -F '\t' -v ts="$(date -Is)" -v instance="$instance_id" '{ print ts "\t" instance "\t" $1 "\t" $2 }' "$refill_file" >> "$DISPATCHED_FILE"
    echo "$(date -Is) refilled instance=$instance_id added=$(wc -l < "$refill_file")"
  else
    echo "ERROR instance=$instance_id refill_status=$status; returning records to local queue" >&2
    return_local_targets_file "$refill_file"
  fi
  rm -f "$refill_file"
}

refill_once() {
  echo "$(date -Is) queue_remaining=$(wc -l < "$QUEUE_FILE")"
  local pids=()
  local active=0
  local instance_id remote_dirs
  while IFS=$'\t' read -r instance_id remote_dirs; do
    refill_instance_once "$instance_id" "$remote_dirs" &
    pids+=("$!")
    active=$((active + 1))
    if [ "$active" -ge "$REFILL_PARALLELISM" ]; then
      wait "${pids[0]}" || true
      pids=("${pids[@]:1}")
      active=$((active - 1))
    fi
  done < <(worker_instances)
  for pid in "${pids[@]}"; do wait "$pid" || true; done
}

while true; do
  refill_once
  [ "$ONCE" = "1" ] && exit 0
  sleep "$INTERVAL_SECONDS"
done

#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
WORKERS_FILE="${WORKERS_FILE:-workers}"

json_commands() {
  python3 - "$@" <<'PY'
import json
import sys
print("commands=" + json.dumps(list(sys.argv[1:])))
PY
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

monitor_instance() {
  local instance_id="$1"
  local remote_dirs="$2"
  local cmd_id status output

  cmd_id="$(
    aws ssm send-command \
      --region "$AWS_REGION" \
      --instance-ids "$instance_id" \
      --document-name AWS-RunShellScript \
      --comment process-worker-status \
      --parameters "$(
        json_commands \
          "set -euo pipefail" \
          "read_cpu() { awk '/^cpu / { total=0; for (i=2; i<=NF; i++) total+=\$i; print total, \$5 }' /proc/stat; }" \
          "read_net() { awk -F'[: ]+' '\$2 != \"lo\" { rx+=\$3; tx+=\$11 } END { print rx+0, tx+0 }' /proc/net/dev; }" \
          "human_rate() { awk -v b=\"\$1\" 'BEGIN { split(\"B/s KB/s MB/s GB/s TB/s\", u); i=1; while (b >= 1024 && i < 5) { b/=1024; i++ } printf \"%.1f%s\", b, u[i] }'; }" \
          "read cpu_total_1 cpu_idle_1 < <(read_cpu)" \
          "read rx_1 tx_1 < <(read_net)" \
          "sleep 1" \
          "read cpu_total_2 cpu_idle_2 < <(read_cpu)" \
          "read rx_2 tx_2 < <(read_net)" \
          "cpu_pct=\$(awk -v t1=\"\$cpu_total_1\" -v i1=\"\$cpu_idle_1\" -v t2=\"\$cpu_total_2\" -v i2=\"\$cpu_idle_2\" 'BEGIN { dt=t2-t1; di=i2-i1; if (dt <= 0) printf \"0.0%%\"; else printf \"%.1f%%\", (dt-di)*100/dt }')" \
          "rx_rate=\$(human_rate \$((rx_2 - rx_1)))" \
          "tx_rate=\$(human_rate \$((tx_2 - tx_1)))" \
          "for d in $remote_dirs; do if ! cd \"\$d\" 2>/dev/null; then printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \"\$d\" '-' '-' '-' \"\$cpu_pct\" \"\$rx_rate\" \"\$tx_rate\" 'MISSING_DIR'; continue; fi; next=\$(wc -l < next 2>/dev/null || echo 0); completed=\$(wc -l < completed 2>/dev/null || echo 0); failed=\$(wc -l < failed 2>/dev/null || echo 0); status=\$(cat status 2>/dev/null || echo no-status); printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \"\$d\" \"\$next\" \"\$completed\" \"\$failed\" \"\$cpu_pct\" \"\$rx_rate\" \"\$tx_rate\" \"\$status\"; done"
      )" \
      --query 'Command.CommandId' \
      --output text
  )"

  while true; do
    status="$(
      aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --instance-id "$instance_id" \
        --command-id "$cmd_id" \
        --query Status \
        --output text 2>/dev/null || true
    )"
    case "$status" in Success|Failed|Cancelled|TimedOut|Cancelling) break ;; esac
    sleep 1
  done

  output="$(
    aws ssm get-command-invocation \
      --region "$AWS_REGION" \
      --instance-id "$instance_id" \
      --command-id "$cmd_id" \
      --query StandardOutputContent \
      --output text 2>/dev/null || true
  )"

  while IFS=$'\t' read -r dir next completed failed cpu_pct rx_rate tx_rate status_line; do
    [ -n "${dir:-}" ] || continue
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$instance_id" "$dir" "$next" "$completed" "$failed" "$cpu_pct" "$rx_rate" "$tx_rate" "$status_line"
  done <<< "$output"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

i=0
while IFS=$'\t' read -r instance_id remote_dirs; do
  [ -n "${instance_id:-}" ] || continue
  i=$((i + 1))
  monitor_instance "$instance_id" "$remote_dirs" > "$tmp_dir/$i.out" &
done < <(worker_instances)
wait

printf "%-22s %-8s %8s %10s %8s %7s %10s %10s  %s\n" "INSTANCE" "DIR" "NEXT" "COMPLETED" "FAILED" "CPU" "RX/s" "TX/s" "STATUS"
total_next=0
total_completed=0
total_failed=0

for f in "$tmp_dir"/*.out; do
  [ -e "$f" ] || continue
  while IFS=$'\t' read -r instance_id dir next completed failed cpu_pct rx_rate tx_rate status_line; do
    [[ "$next" =~ ^[0-9]+$ ]] && total_next=$((total_next + next))
    [[ "$completed" =~ ^[0-9]+$ ]] && total_completed=$((total_completed + completed))
    [[ "$failed" =~ ^[0-9]+$ ]] && total_failed=$((total_failed + failed))
    printf "%-22s %-8s %8s %10s %8s %7s %10s %10s  %s\n" "$instance_id" "$dir" "$next" "$completed" "$failed" "$cpu_pct" "$rx_rate" "$tx_rate" "$status_line"
  done < "$f"
done

echo
echo "TOTAL next=$total_next completed=$total_completed failed=$total_failed"

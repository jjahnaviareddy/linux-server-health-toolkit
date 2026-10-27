#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

CPU_WARN_THRESHOLD="${CPU_WARN_THRESHOLD:-80}"
CPU_CRIT_THRESHOLD="${CPU_CRIT_THRESHOLD:-95}"

read_cpu() {
    awk '/^cpu / {
        total = 0
        for (i = 2; i <= 9; i++) total += $i
        print total, $5 + $6
        exit
    }' /proc/stat
}

log_line "INFO" "Starting CPU check"

read -r total_before idle_before < <(read_cpu)
sleep 1
read -r total_after idle_after < <(read_cpu)

total_delta=$((total_after - total_before))
idle_delta=$((idle_after - idle_before))

if (( total_delta <= 0 )); then
    log_line "ERROR" "Unable to calculate CPU usage"
    exit 2
fi

percent=$((100 * (total_delta - idle_delta) / total_delta))
status="OK"
result=0

if (( percent >= CPU_CRIT_THRESHOLD )); then
    status="CRITICAL"
    result=2
elif (( percent >= CPU_WARN_THRESHOLD )); then
    status="WARNING"
    result=1
fi

log_line "$status" "CPU usage is ${percent}%"

json=$(printf '{"timestamp":"%s","host":"%s","check":"cpu","percent":%s,"status":"%s"}' \
    "$TIMESTAMP" "$(json_escape "$HOSTNAME_STR")" "$percent" "$status")

write_result "cpu_results.jsonl" "$json"
exit "$result"

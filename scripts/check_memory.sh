#!/usr/bin/env bash
# =============================================================================
# check_memory.sh
# Checks RAM and swap usage against the configured thresholds and appends
# a structured result to logs/data/memory_results.jsonl
#
# Exit codes: 0 = OK, 1 = WARNING present, 2 = CRITICAL present
# =============================================================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

log_line "INFO" "Starting memory check"
EXIT_CODE=0

read -r total used free shared buff_cache available <<< "$(free -m | awk '/^Mem:/{print $2, $3, $4, $5, $6, $7}')"
read -r swap_total swap_used swap_free <<< "$(free -m | awk '/^Swap:/{print $2, $3, $4}')"

total="${total:-0}"; used="${used:-0}"; free="${free:-0}"
swap_total="${swap_total:-0}"; swap_used="${swap_used:-0}"

mem_pcent=0
if (( total > 0 )); then
    mem_pcent=$(( used * 100 / total ))
fi

swap_pcent=0
if (( swap_total > 0 )); then
    swap_pcent=$(( swap_used * 100 / swap_total ))
fi

mem_status="OK"
if (( mem_pcent >= MEM_CRIT_THRESHOLD )); then
    mem_status="CRITICAL"
    EXIT_CODE=2
    log_line "CRITICAL" "Memory usage is ${mem_pcent}% (>= ${MEM_CRIT_THRESHOLD}%)"
elif (( mem_pcent >= MEM_WARN_THRESHOLD )); then
    mem_status="WARNING"
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
    log_line "WARNING" "Memory usage is ${mem_pcent}% (>= ${MEM_WARN_THRESHOLD}%)"
else
    log_line "INFO" "Memory usage is ${mem_pcent}% - OK"
fi

swap_status="OK"
if (( swap_total > 0 )) && (( swap_pcent >= SWAP_WARN_THRESHOLD )); then
    swap_status="WARNING"
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
    log_line "WARNING" "Swap usage is ${swap_pcent}% (>= ${SWAP_WARN_THRESHOLD}%)"
else
    log_line "INFO" "Swap usage is ${swap_pcent}% - OK"
fi

json=$(printf '{"timestamp":"%s","host":"%s","check":"memory","total_mb":%s,"used_mb":%s,"free_mb":%s,"mem_percent":%s,"mem_status":"%s","swap_total_mb":%s,"swap_used_mb":%s,"swap_percent":%s,"swap_status":"%s"}' \
    "${TIMESTAMP}" "${HOSTNAME_STR}" "${total}" "${used}" "${free}" "${mem_pcent}" "${mem_status}" \
    "${swap_total}" "${swap_used}" "${swap_pcent}" "${swap_status}")
write_result "memory_results.jsonl" "${json}"

log_line "INFO" "Memory check complete (exit code ${EXIT_CODE})"
exit ${EXIT_CODE}

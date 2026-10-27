#!/usr/bin/env bash
# =============================================================================
# check_disk.sh
# Checks disk usage on every mounted filesystem and flags any that exceed
# the configured warning/critical thresholds. Appends structured results
# to logs/data/disk_results.jsonl for the report generator to consume.
#
# Exit codes: 0 = OK, 1 = WARNING present, 2 = CRITICAL present
# =============================================================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

log_line "INFO" "Starting disk space check"

EXIT_CODE=0

while read -r line; do
    fs=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    avail=$(echo "$line" | awk '{print $4}')
    pcent=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')

    # Skip any row where percent didn't parse as a number
    [[ "${pcent}" =~ ^[0-9]+$ ]] || continue

    status="OK"
    if (( pcent >= DISK_CRIT_THRESHOLD )); then
        status="CRITICAL"
        EXIT_CODE=2
        log_line "CRITICAL" "Disk usage on ${mount} (${fs}) is ${pcent}% (>= ${DISK_CRIT_THRESHOLD}%)"
    elif (( pcent >= DISK_WARN_THRESHOLD )); then
        status="WARNING"
        [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
        log_line "WARNING" "Disk usage on ${mount} (${fs}) is ${pcent}% (>= ${DISK_WARN_THRESHOLD}%)"
    else
        log_line "INFO" "Disk usage on ${mount} (${fs}) is ${pcent}% - OK"
    fi

    json=$(printf '{"timestamp":"%s","host":"%s","check":"disk","filesystem":"%s","mount":"%s","size":"%s","used":"%s","available":"%s","percent":%s,"status":"%s"}' \
        "${TIMESTAMP}" "${HOSTNAME_STR}" "$(json_escape "$fs")" "$(json_escape "$mount")" \
        "$(json_escape "$size")" "$(json_escape "$used")" "$(json_escape "$avail")" "${pcent}" "${status}")
    write_result "disk_results.jsonl" "${json}"

done < <(df -hP -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)

log_line "INFO" "Disk space check complete (exit code ${EXIT_CODE})"
exit ${EXIT_CODE}

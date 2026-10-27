#!/usr/bin/env bash
# =============================================================================
# check_services.sh
# Verifies that the systemd services listed in SERVICES_TO_CHECK (see
# config/health_check.conf) are active. Appends results to
# logs/data/service_results.jsonl
#
# Exit codes: 0 = all active, 2 = one or more services down
# On non-systemd hosts this check is skipped gracefully (exit 0).
# =============================================================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

log_line "INFO" "Starting service check"
EXIT_CODE=0

if ! command -v systemctl &>/dev/null; then
    log_line "WARNING" "systemctl not found - skipping service checks (non-systemd host?)"
    exit 0
fi

for svc in ${SERVICES_TO_CHECK}; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        state="active"
        log_line "INFO" "Service ${svc} is active"
    else
        state="$(systemctl is-active "${svc}" 2>/dev/null)"
        state="${state:-unknown}"
        log_line "CRITICAL" "Service ${svc} is NOT active (state: ${state})"
        EXIT_CODE=2
    fi

    json=$(printf '{"timestamp":"%s","host":"%s","check":"service","service":"%s","state":"%s"}' \
        "${TIMESTAMP}" "${HOSTNAME_STR}" "$(json_escape "$svc")" "$(json_escape "$state")")
    write_result "service_results.jsonl" "${json}"
done

log_line "INFO" "Service check complete (exit code ${EXIT_CODE})"
exit ${EXIT_CODE}

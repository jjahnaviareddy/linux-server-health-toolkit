#!/usr/bin/env bash
# =============================================================================
# run_all_checks.sh
# Master script: runs every check in sequence, rotates logs, then invokes
# the Python report generator to build the day's Markdown summary.
# Intended to be called from cron (see cron/crontab_example.txt).
# =============================================================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

OVERALL_EXIT=0

run_check() {
    local name="$1"; shift
    log_line "INFO" "==> Running ${name}"
    "$@"
    local rc=$?
    if (( rc > OVERALL_EXIT )); then
        OVERALL_EXIT=$rc
    fi
}

run_check "CPU check" "${SCRIPT_DIR}/check_cpu.sh"
run_check "disk check"    "${SCRIPT_DIR}/check_disk.sh"
run_check "memory check"  "${SCRIPT_DIR}/check_memory.sh"
run_check "service check" "${SCRIPT_DIR}/check_services.sh"
run_check "log rotation"  "${SCRIPT_DIR}/log_rotate.sh"

log_line "INFO" "Generating daily report"
PYTHON_BIN="$(command -v python3 || command -v python || true)"
if [[ -n "${PYTHON_BIN}" ]]; then
    "${PYTHON_BIN}" "${PROJECT_ROOT}/python/generate_report.py" \
        --data-dir "${DATA_DIR}" \
        --report-dir "${REPORT_DIR}" \
        --date "${DATE_ONLY}"
else
    log_line "WARNING" "python3 not found; skipping report generation"
fi

if [[ -n "${PYTHON_BIN}" ]]; then
    log_line "INFO" "Generating HTML report"
    "${PYTHON_BIN}" "${PROJECT_ROOT}/python/generate_html.py" \
        "${REPORT_DIR}/report-${DATE_ONLY}.md"
    html_rc=$?
    if (( html_rc != 0 )); then
        log_line "ERROR" "HTML report generation failed"
        OVERALL_EXIT=2
    fi
fi

log_line "INFO" "All checks complete. Overall exit code: ${OVERALL_EXIT}"
exit ${OVERALL_EXIT}

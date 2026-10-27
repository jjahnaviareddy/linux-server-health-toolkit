#!/usr/bin/env bash
# =============================================================================
# log_rotate.sh
# Compresses plain .log files older than a day and deletes compressed logs
# older than LOG_ROTATE_MAX_AGE_DAYS. Rotates the toolkit's own log
# directory, plus an optional external LOG_ROTATE_TARGET_DIR from config.
# =============================================================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

log_line "INFO" "Starting log rotation"

rotate_dir() {
    local dir="$1"
    local max_age="$2"

    if [[ ! -d "$dir" ]]; then
        log_line "WARNING" "Rotate target ${dir} does not exist, skipping"
        return
    fi

    # Compress plain .log files older than 1 day that aren't already gz
    find "$dir" -maxdepth 1 -type f -name "*.log" -mtime +0 ! -name "*.gz" -print0 2>/dev/null |
    while IFS= read -r -d '' f; do
        if [[ "${LOG_ROTATE_COMPRESS}" == "true" ]]; then
            gzip -f "$f" && log_line "INFO" "Compressed $f"
        fi
    done

    # Delete compressed/rotated logs older than max_age days
    find "$dir" -maxdepth 1 -type f -name "*.gz" -mtime +"${max_age}" -print0 2>/dev/null |
    while IFS= read -r -d '' f; do
        rm -f "$f" && log_line "INFO" "Deleted expired log $f"
    done
}

rotate_dir "${LOG_DIR}" "${LOG_ROTATE_MAX_AGE_DAYS}"

if [[ -n "${LOG_ROTATE_TARGET_DIR:-}" ]]; then
    rotate_dir "${LOG_ROTATE_TARGET_DIR}" "${LOG_ROTATE_MAX_AGE_DAYS}"
fi

log_line "INFO" "Log rotation complete"

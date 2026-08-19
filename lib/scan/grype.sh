#!/bin/bash
# ============================================================
# grype.sh
# CVE-Scan via Grype
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

GRYPE_BIN=$(command -v grype)
GRYPE_SEVERITY_FAIL="critical,high"
GRYPE_SEVERITY_WARN="medium"

scan_grype() {
    local package_path="$1"

    # Grype vorhanden?
    if [ -z "${GRYPE_BIN}" ]; then
        echo "SKIP: grype nicht gefunden"
        return 0
    fi

    # Scan auf CRITICAL/HIGH
    local output
    output=$(${GRYPE_BIN} "${package_path}" \
        --fail-on "${GRYPE_SEVERITY_FAIL}" \
        --output json \
        --quiet 2>&1)
    local exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        echo "${output}"
        return 2
    fi

    # Scan auf MEDIUM
    output=$(${GRYPE_BIN} "${package_path}" \
        --fail-on "${GRYPE_SEVERITY_WARN}" \
        --output json \
        --quiet 2>&1)
    exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        echo "${output}"
        return 1
    fi

    echo "OK"
    return 0
}

# Direktaufruf
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    scan_grype "$1"
    exit $?
fi
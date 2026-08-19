#!/bin/bash
# ============================================================
# trivy.sh
# CVE-Scan via Trivy
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

source "$(dirname "$0")/../../conf/repo-security.conf"

TRIVY_BIN=$(command -v trivy)
TRIVY_SEVERITY_FAIL="CRITICAL,HIGH"
TRIVY_SEVERITY_WARN="MEDIUM"

scan_trivy() {
    local package_path="$1"

    # Trivy vorhanden?
    if [ -z "${TRIVY_BIN}" ]; then
        echo "SKIP: trivy nicht gefunden"
        return 0
    fi

    # Scan durchführen
    local output
    output=$(${TRIVY_BIN} rootfs \
        --severity "${TRIVY_SEVERITY_FAIL}" \
        --exit-code 2 \
        --no-progress \
        --format json \
        "${package_path}" 2>&1)
    local exit_code=$?

    if [ ${exit_code} -eq 2 ]; then
        echo "${output}"
        return 2
    fi

    # WARN-Severity prüfen
    output=$(${TRIVY_BIN} rootfs \
        --severity "${TRIVY_SEVERITY_WARN}" \
        --exit-code 1 \
        --no-progress \
        --format json \
        "${package_path}" 2>&1)
    exit_code=$?

    if [ ${exit_code} -eq 1 ]; then
        echo "${output}"
        return 1
    fi

    echo "OK"
    return 0
}

# Direktaufruf
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    scan_trivy "$1"
    exit $?
fi
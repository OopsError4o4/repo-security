#!/bin/bash
# ============================================================
# clamav.sh
# Malware-Scan via ClamAV
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

CLAMSCAN_BIN=$(command -v clamscan)

scan_clamav() {
    local package_path="$1"

    # ClamAV vorhanden?
    if [ -z "${CLAMSCAN_BIN}" ]; then
        echo "SKIP: clamscan nicht gefunden"
        return 0
    fi

    # Scan durchführen
    local output
    output=$(${CLAMSCAN_BIN} \
        --infected \
        --no-summary \
        --stdout \
        "${package_path}" 2>&1)
    local exit_code=$?

    # Exit 1 = Virus gefunden
    if [ ${exit_code} -eq 1 ]; then
        echo "${output}"
        return 2
    fi

    # Exit 2 = Fehler beim Scan
    if [ ${exit_code} -eq 2 ]; then
        echo "WARN: ClamAV Scan-Fehler: ${output}"
        return 1
    fi

    echo "OK"
    return 0
}

# Direktaufruf
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    scan_clamav "$1"
    exit $?
fi
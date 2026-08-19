#!/bin/bash
# ============================================================
# bandit.sh
# Python SAST via Bandit
# Nur relevant wenn Paket Python-Code enthält
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

source "$(dirname "$0")/../../conf/repo-security.conf"

BANDIT_BIN=$(command -v bandit)
EXTRACT_DIR="/tmp/repo-security-extract"

scan_bandit() {
    local package_path="$1"

    # Bandit vorhanden?
    if [ -z "${BANDIT_BIN}" ]; then
        echo "SKIP: bandit nicht gefunden"
        return 0
    fi

    # Paket extrahieren
    mkdir -p "${EXTRACT_DIR}"
    rm -rf "${EXTRACT_DIR:?}"/*

    local ext="${package_path##*.}"

    if [ "${ext}" = "rpm" ]; then
        rpm2cpio "${package_path}" | cpio -idm -D "${EXTRACT_DIR}" 2>/dev/null
    elif [ "${ext}" = "deb" ]; then
        dpkg-deb -x "${package_path}" "${EXTRACT_DIR}" 2>/dev/null
    else
        echo "SKIP: Unbekanntes Paketformat: ${ext}"
        rm -rf "${EXTRACT_DIR}"
        return 0
    fi

    # Python-Dateien vorhanden?
    local py_files
    py_files=$(find "${EXTRACT_DIR}" -name "*.py" 2>/dev/null)

    if [ -z "${py_files}" ]; then
        echo "SKIP: Keine Python-Dateien im Paket gefunden"
        rm -rf "${EXTRACT_DIR}"
        return 0
    fi

    # Bandit-Scan
    local output
    output=$(${BANDIT_BIN} \
        -r "${EXTRACT_DIR}" \
        -f json \
        -l \
        -i \
        2>&1)
    local exit_code=$?

    # Aufräumen
    rm -rf "${EXTRACT_DIR}"

    if [ ${exit_code} -ne 0 ]; then
        # HIGH severity = FAIL
        if echo "${output}" | grep -qi '"severity": "HIGH"'; then
            echo "${output}"
            return 2
        fi
        # MEDIUM severity = WARN
        if echo "${output}" | grep -qi '"severity": "MEDIUM"'; then
            echo "${output}"
            return 1
        fi
    fi

    echo "OK"
    return 0
}

# Direktaufruf
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    scan_bandit "$1"
    exit $?
fi
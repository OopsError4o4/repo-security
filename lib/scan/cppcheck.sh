#!/bin/bash
# ============================================================
# cppcheck.sh
# C/C++ SAST via cppcheck
# Nur relevant wenn Paket C/C++ Quellcode enthält
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

source "$(dirname "$0")/../../conf/repo-security.conf"

CPPCHECK_BIN=$(command -v cppcheck)
EXTRACT_DIR="/tmp/repo-security-extract"

scan_cppcheck() {
    local package_path="$1"

    # cppcheck vorhanden?
    if [ -z "${CPPCHECK_BIN}" ]; then
        echo "SKIP: cppcheck nicht gefunden"
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

    # C/C++ Dateien vorhanden?
    local cpp_files
    cpp_files=$(find "${EXTRACT_DIR}" -name "*.c" -o -name "*.cpp" -o -name "*.h" 2>/dev/null)

    if [ -z "${cpp_files}" ]; then
        echo "SKIP: Keine C/C++ Dateien im Paket gefunden"
        rm -rf "${EXTRACT_DIR}"
        return 0
    fi

    # cppcheck-Scan
    local output
    output=$(${CPPCHECK_BIN} \
        --enable=warning,error \
        --error-exitcode=2 \
        --quiet \
        "${EXTRACT_DIR}" 2>&1)
    local exit_code=$?

    # Aufräumen
    rm -rf "${EXTRACT_DIR}"

    if [ ${exit_code} -eq 2 ]; then
        echo "${output}"
        return 2
    fi

    if echo "${output}" | grep -qi "warning"; then
        echo "${output}"
        return 1
    fi

    echo "OK"
    return 0
}

# Direktaufruf
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    scan_cppcheck "$1"
    exit $?
fi
#!/bin/bash
# ============================================================
# rkhunter.sh
# Rootkit-Scan via rkhunter
# Hinweis: rkhunter ist primär für laufende Systeme gedacht.
# Hier wird es auf extrahierten Paketinhalt angewendet.
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

source "$(dirname "$0")/../../conf/repo-security.conf"

RKHUNTER_BIN=$(command -v rkhunter)
EXTRACT_DIR="/tmp/repo-security-extract"

scan_rkhunter() {
    local package_path="$1"

    # rkhunter vorhanden?
    if [ -z "${RKHUNTER_BIN}" ]; then
        echo "SKIP: rkhunter nicht gefunden"
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

    # rkhunter auf extrahiertem Inhalt ausführen
    local output
    output=$(${RKHUNTER_BIN} \
        --rootdir "${EXTRACT_DIR}" \
        --check \
        --nocolors \
        --skip-keypress \
        --report-warnings-only 2>&1)
    local exit_code=$?

    # Aufräumen
    rm -rf "${EXTRACT_DIR}"

    if [ ${exit_code} -ne 0 ]; then
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
    scan_rkhunter "$1"
    exit $?
fi
#!/bin/bash
# ============================================================
# chkrootkit.sh
# Rootkit-Scan via chkrootkit
# Hinweis: chkrootkit ist primär für laufende Systeme gedacht.
# Hier wird es auf extrahierten Paketinhalt angewendet.
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

CHKROOTKIT_BIN=$(command -v chkrootkit)
EXTRACT_DIR="/tmp/repo-security-extract"

scan_chkrootkit() {
    local package_path="$1"

    # chkrootkit vorhanden?
    if [ -z "${CHKROOTKIT_BIN}" ]; then
        echo "SKIP: chkrootkit nicht gefunden"
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

    # chkrootkit auf extrahiertem Inhalt ausführen
    local output
    output=$(${CHKROOTKIT_BIN} \
        -r "${EXTRACT_DIR}" \
        -q 2>&1)
    local exit_code=$?

    # Aufräumen
    rm -rf "${EXTRACT_DIR}"

    if [ ${exit_code} -ne 0 ]; then
        echo "${output}"
        return 2
    fi

    if echo "${output}" | grep -qi "infected\|suspicious"; then
        echo "${output}"
        return 1
    fi

    echo "OK"
    return 0
}

# Direktaufruf
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    scan_chkrootkit "$1"
    exit $?
fi
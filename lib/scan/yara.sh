#!/bin/bash
# ============================================================
# yara.sh
# Pattern-Scan via YARA
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

source "$(dirname "$0")/../../conf/repo-security.conf"

YARA_BIN=$(command -v yara)
YARA_RULES_DIR="/opt/repo-security/yara-rules"

scan_yara() {
    local package_path="$1"

    # YARA vorhanden?
    if [ -z "${YARA_BIN}" ]; then
        echo "SKIP: yara nicht gefunden"
        return 0
    fi

    # Rules-Verzeichnis vorhanden?
    if [ ! -d "${YARA_RULES_DIR}" ]; then
        echo "SKIP: YARA Rules-Verzeichnis nicht gefunden: ${YARA_RULES_DIR}"
        return 0
    fi

    # Alle .yar/.yara Rules anwenden
    local output
    local exit_code
    local fail=0
    local warn=0

    while IFS= read -r -d '' rule_file; do
        output=$(${YARA_BIN} \
            --recursive \
            "${rule_file}" \
            "${package_path}" 2>&1)
        exit_code=$?

        if [ ${exit_code} -ne 0 ]; then
            echo "WARN: YARA Fehler bei Rule ${rule_file}: ${output}"
            warn=1
            continue
        fi

        if [ -n "${output}" ]; then
            echo "FAIL: YARA Match in ${package_path}: ${output}"
            fail=1
        fi
    done < <(find "${YARA_RULES_DIR}" -name "*.yar" -o -name "*.yara" -print0)

    if [ ${fail} -eq 1 ]; then
        return 2
    fi

    if [ ${warn} -eq 1 ]; then
        return 1
    fi

    echo "OK"
    return 0
}

# Direktaufruf
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    scan_yara "$1"
    exit $?
fi
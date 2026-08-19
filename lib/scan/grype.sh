#!/bin/bash
# ============================================================
# grype.sh
# CVE-Scan via Grype (mit Paket-Extraktion)
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

GRYPE_BIN=$(command -v grype)

scan_grype() {
    local package_path="$1"
    local extract_dir="/tmp/grype-extract-$$"

    # Grype vorhanden?
    if [ -z "${GRYPE_BIN}" ]; then
        echo "SKIP: grype nicht gefunden"
        return 0
    fi

    # Paket extrahieren
    mkdir -p "${extract_dir}"
    local ext="${package_path##*.}"

    if [ "${ext}" = "rpm" ]; then
        rpm2cpio "${package_path}" | cpio -idm -D "${extract_dir}" 2>/dev/null
    elif [ "${ext}" = "deb" ]; then
        dpkg-deb -x "${package_path}" "${extract_dir}" 2>/dev/null
    else
        echo "SKIP: Unbekanntes Paketformat: ${ext}"
        rm -rf "${extract_dir}"
        return 0
    fi

    local output
    local exit_code

    # Scan auf CRITICAL
    output=$(${GRYPE_BIN} "dir:${extract_dir}" \
        --fail-on "critical" \
        --output json \
        --quiet 2>&1)
    exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        rm -rf "${extract_dir}"
        echo "${output}"
        return 2
    fi

    # Scan auf HIGH
    output=$(${GRYPE_BIN} "dir:${extract_dir}" \
        --fail-on "high" \
        --output json \
        --quiet 2>&1)
    exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        rm -rf "${extract_dir}"
        echo "${output}"
        return 2
    fi

    # Scan auf MEDIUM
    output=$(${GRYPE_BIN} "dir:${extract_dir}" \
        --fail-on "medium" \
        --output json \
        --quiet 2>&1)
    exit_code=$?

    rm -rf "${extract_dir}"

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
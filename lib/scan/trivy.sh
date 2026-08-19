#!/bin/bash
# ============================================================
# trivy.sh
# CVE-Scan via Trivy (mit Paket-Extraktion)
# Exit 0 = OK, Exit 1 = WARN, Exit 2 = FAIL
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

TRIVY_BIN=$(command -v trivy)
TRIVY_SEVERITY_FAIL="CRITICAL,HIGH"
TRIVY_SEVERITY_WARN="MEDIUM"

scan_trivy() {
    local package_path="$1"
    local extract_dir="/tmp/trivy-extract-$$"

    # Trivy vorhanden?
    if [ -z "${TRIVY_BIN}" ]; then
        echo "SKIP: trivy nicht gefunden"
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

    # Scan auf CRITICAL/HIGH
    local output
    output=$(${TRIVY_BIN} rootfs \
        --severity "${TRIVY_SEVERITY_FAIL}" \
        --exit-code 2 \
        --no-progress \
        --scanners vuln \
        --format json \
        "${extract_dir}" 2>&1)
    local exit_code=$?

    if [ ${exit_code} -eq 2 ]; then
        rm -rf "${extract_dir}"
        echo "${output}"
        return 2
    fi

    # Scan auf MEDIUM
    output=$(${TRIVY_BIN} rootfs \
        --severity "${TRIVY_SEVERITY_WARN}" \
        --exit-code 1 \
        --no-progress \
        --scanners vuln \
        --format json \
        "${extract_dir}" 2>&1)
    exit_code=$?

    rm -rf "${extract_dir}"

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
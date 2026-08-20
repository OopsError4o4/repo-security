#!/bin/bash
# ============================================================
# repo-security.sh
# Hauptscript - Security-Pipeline für Repomanager
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/conf/repo-security.conf"
source "${SCRIPT_DIR}/lib/db.sh"
source "${SCRIPT_DIR}/lib/api.sh"
source "${SCRIPT_DIR}/lib/alert.sh"

# Scan-Module laden
source "${SCRIPT_DIR}/lib/scan/trivy.sh"
source "${SCRIPT_DIR}/lib/scan/grype.sh"
source "${SCRIPT_DIR}/lib/scan/clamav.sh"
source "${SCRIPT_DIR}/lib/scan/yara.sh"
source "${SCRIPT_DIR}/lib/scan/rkhunter.sh"
source "${SCRIPT_DIR}/lib/scan/chkrootkit.sh"
source "${SCRIPT_DIR}/lib/scan/bandit.sh"
source "${SCRIPT_DIR}/lib/scan/cppcheck.sh"

# ============================================================
# Hilfsfunktionen
# ============================================================

usage() {
    echo "Usage: $0 --repo <repo_name> [--promote] [--limit <n>]"
    echo ""
    echo "  --repo      Name des Repos in Repomanager"
    echo "  --promote   Nach bestandenem Check nach prod promoten"
    echo "  --limit     Maximale Anzahl zu scannender Pakete (zum Testen)"
    exit 1
}

# Einzelnes Paket scannen
scan_package() {
    local package_path="$1"
    local package_id="$2"
    local repo_name="$3"
    local package_name="$4"
    local package_version="$5"

    local overall_status="ok"
    local scan_output
    local scan_exit

    log "INFO" "Scanne Paket: ${package_name}-${package_version}"

    declare -A scan_tools=(
        ["trivy"]="${SCAN_TRIVY}"
        ["grype"]="${SCAN_GRYPE}"
        ["clamav"]="${SCAN_CLAMAV}"
        ["yara"]="${SCAN_YARA}"
        ["rkhunter"]="${SCAN_RKHUNTER}"
        ["chkrootkit"]="${SCAN_CHKROOTKIT}"
        ["bandit"]="${SCAN_BANDIT}"
        ["cppcheck"]="${SCAN_CPPCHECK}"
    )

    for tool in "${!scan_tools[@]}"; do
        [ "${scan_tools[$tool]}" != "true" ] && continue

        log "INFO" "  → ${tool}"

        case "${tool}" in
            trivy)      scan_output=$(scan_trivy "${package_path}");      scan_exit=$? ;;
            grype)      scan_output=$(scan_grype "${package_path}");      scan_exit=$? ;;
            clamav)     scan_output=$(scan_clamav "${package_path}");     scan_exit=$? ;;
            yara)       scan_output=$(scan_yara "${package_path}");       scan_exit=$? ;;
            rkhunter)   scan_output=$(scan_rkhunter "${package_path}");   scan_exit=$? ;;
            chkrootkit) scan_output=$(scan_chkrootkit "${package_path}"); scan_exit=$? ;;
            bandit)     scan_output=$(scan_bandit "${package_path}");     scan_exit=$? ;;
            cppcheck)   scan_output=$(scan_cppcheck "${package_path}");   scan_exit=$? ;;
        esac

        local result_status
        case ${scan_exit} in
            0) result_status="ok" ;;
            1) result_status="warn"; [ "${overall_status}" != "fail" ] && overall_status="warn" ;;
            2) result_status="fail"; overall_status="fail" ;;
            *) result_status="warn"; [ "${overall_status}" != "fail" ] && overall_status="warn" ;;
        esac

        db_write_scan_result "${package_id}" "${tool}" "${result_status}" "" "${scan_output}"

        if [ "${result_status}" = "fail" ]; then
            alert_blocked_package "${repo_name}" "${package_name}" "${package_version}" \
                "${tool}" "HIGH" "${scan_output}"
        fi

        log "INFO" "  → ${tool}: ${result_status}"
    done

    if [ "${overall_status}" = "fail" ]; then
        db_update_package_status "${package_id}" "blocked"
    else
        db_update_package_status "${package_id}" "ok"
    fi

    echo "${overall_status}"
}

# ============================================================
# Main
# ============================================================

main() {
    local repo_name=""
    local do_promote=false
    local limit=0

    # Argumente parsen
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)     repo_name="$2";  shift 2 ;;
            --promote)  do_promote=true; shift ;;
            --limit)    limit="$2";      shift 2 ;;
            *)          usage ;;
        esac
    done

    [ -z "${repo_name}" ] && usage

    log "INFO" "============================================================"
    log "INFO" "Starte Security-Pipeline für Repo: ${repo_name}"
    [ "${limit}" -gt 0 ] && log "INFO" "Limit: ${limit} Pakete"
    log "INFO" "============================================================"

    # DB-Verbindung prüfen
    if ! db_check_connection; then
        log "ERROR" "Keine DB-Verbindung — Abbruch"
        exit 1
    fi

    # DB initialisieren
    db_init

    # Package-Type ermitteln
    local package_type
    package_type=$(api_get_package_type "${repo_name}")

    if [ -z "${package_type}" ]; then
        log "ERROR" "Repo '${repo_name}' nicht in Repomanager gefunden — Abbruch"
        exit 1
    fi

    log "INFO" "Package-Type: ${package_type}"

    # Snapshot-Datum ermitteln
    local snapshot_date
    snapshot_date=$(api_get_latest_snapshot_date "${repo_name}" "${package_type}")

    if [ -z "${snapshot_date}" ]; then
        log "ERROR" "Kein Snapshot gefunden — Abbruch"
        exit 1
    fi

    log "INFO" "Snapshot-Datum: ${snapshot_date}"

    # Repo-ID ermitteln
    local repo_id
    repo_id=$(api_get_repo_id "${repo_name}")
    log "INFO" "Repo-ID: ${repo_id}"

    # Paketliste holen
    local packages
    mapfile -t packages < <(api_get_packages "${repo_name}" "${snapshot_date}" "${package_type}")

    local total=${#packages[@]}
    log "INFO" "Gefundene Pakete: ${total}"

    # Limit anwenden
    if [ "${limit}" -gt 0 ] && [ "${limit}" -lt "${total}" ]; then
        packages=("${packages[@]:0:${limit}}")
        log "INFO" "Limit aktiv — scanne nur ${limit} von ${total} Paketen"
    fi

    # Pakete scannen
    local overall_pipeline_status="ok"
    local package_path
    local package_name
    local package_version
    local arch
    local package_id
    local scan_result

    for package_path in "${packages[@]}"; do
        # Paketinfos aus Dateiname extrahieren
        local filename
        filename=$(basename "${package_path}")

        if [ "${package_type}" = "rpm" ]; then
            package_name=$(rpm -qp --queryformat "%{NAME}" "${package_path}" 2>/dev/null)
            package_version=$(rpm -qp --queryformat "%{VERSION}-%{RELEASE}" "${package_path}" 2>/dev/null)
            arch=$(rpm -qp --queryformat "%{ARCH}" "${package_path}" 2>/dev/null)
        else
            package_name=$(dpkg-deb -f "${package_path}" Package 2>/dev/null)
            package_version=$(dpkg-deb -f "${package_path}" Version 2>/dev/null)
            arch=$(dpkg-deb -f "${package_path}" Architecture 2>/dev/null)
        fi

        local checksum
        checksum=$(sha256sum "${package_path}" | awk '{print $1}')

        # In DB eintragen
        db_insert_package "${repo_name}" "${snapshot_date}" \
            "${package_name}" "${package_version}" "${arch}" "${checksum}"

        # Package-ID holen
        package_id=$(db_get_package_id "${repo_name}" "${snapshot_date}" \
            "${package_name}" "${package_version}" "${arch}")

        # Bereits gescannt und OK? Überspringen
        local pkg_status
        pkg_status=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" \
            -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
            -se "SELECT status FROM packages WHERE id=${package_id};" 2>/dev/null)

        if [ "${pkg_status}" = "ok" ]; then
            log "INFO" "Paket bereits geprüft und OK: ${package_name}-${package_version}"
            continue
        fi

        # Paket scannen
        scan_result=$(scan_package "${package_path}" "${package_id}" \
            "${repo_name}" "${package_name}" "${package_version}")

        if [ "${scan_result}" = "fail" ]; then
            overall_pipeline_status="fail"
            log "WARN" "FAIL: ${package_name}-${package_version}"
        fi

    done

    # Promote-Entscheidung
    if [ "${do_promote}" = "true" ]; then
        if [ "${overall_pipeline_status}" = "fail" ] && [ "${BLOCK_ON_FAIL}" = "true" ]; then
            log "WARN" "Promote nach prod BLOCKIERT — mindestens ein Paket hat den Security-Check nicht bestanden"
            db_log_promote "${repo_name}" "${snapshot_date}" "preprod" "prod" "blocked" \
                "Security-Check fehlgeschlagen"
            alert_mail \
                "[REPO-SECURITY] Promote blockiert: ${repo_name} Snapshot ${snapshot_date}" \
                "Promote wurde blockiert da mindestens ein Paket den Security-Check nicht bestanden hat."
        else
            log "INFO" "Alle Checks bestanden — Promote nach prod wird durchgeführt"
            local promote_response
            promote_response=$(api_point_environment "${repo_id}" "${repo_id}" "prod")

            if echo "${promote_response}" | grep -qi "FEHLER"; then
                log "ERROR" "Promote fehlgeschlagen: ${promote_response}"
                exit 1
            fi

            db_log_promote "${repo_name}" "${snapshot_date}" "preprod" "prod" "promoted" "Alle Checks OK"
            alert_promoted "${repo_name}" "${snapshot_date}"
        fi
    fi

    log "INFO" "Pipeline abgeschlossen. Gesamtstatus: ${overall_pipeline_status}"
}

main "$@"
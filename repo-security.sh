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
    echo "Usage: $0 --repo <repo_name> --snapshot <snapshot_id> [--promote]"
    echo ""
    echo "  --repo      Name des Repos in Repomanager"
    echo "  --snapshot  ID des Snapshots der geprüft werden soll"
    echo "  --promote   Nach bestandenem Check nach prod promoten"
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

    # Alle aktivierten Tools durchlaufen
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

        # Ergebnis auswerten
        local result_status
        case ${scan_exit} in
            0) result_status="ok" ;;
            1) result_status="warn"; overall_status="warn" ;;
            2) result_status="fail"; overall_status="fail" ;;
            *) result_status="warn"; overall_status="warn" ;;
        esac

        # In DB schreiben
        db_write_scan_result "${package_id}" "${tool}" "${result_status}" "" "${scan_output}"

        # Bei FAIL sofort Alert
        if [ "${result_status}" = "fail" ]; then
            alert_blocked_package "${repo_name}" "${package_name}" "${package_version}" \
                "${tool}" "HIGH" "${scan_output}"
        fi

        log "INFO" "  → ${tool}: ${result_status}"
    done

    # Paket-Status in DB aktualisieren
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
    local snapshot_id=""
    local do_promote=false

    # Argumente parsen
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)     repo_name="$2";    shift 2 ;;
            --snapshot) snapshot_id="$2";  shift 2 ;;
            --promote)  do_promote=true;   shift ;;
            *)          usage ;;
        esac
    done

    [ -z "${repo_name}" ] || [ -z "${snapshot_id}" ] && usage

    log "INFO" "============================================================"
    log "INFO" "Starte Security-Pipeline für Repo: ${repo_name} Snapshot: ${snapshot_id}"
    log "INFO" "============================================================"

    # DB-Verbindung prüfen
    if ! db_check_connection; then
        log "ERROR" "Keine DB-Verbindung — Abbruch"
        exit 1
    fi

    # DB initialisieren
    db_init

    # Paketliste vom Repomanager holen
    local packages_json
    packages_json=$(api_get_packages "${repo_name}" "${snapshot_id}")

    if [ -z "${packages_json}" ]; then
        log "ERROR" "Keine Pakete vom Repomanager erhalten — Abbruch"
        exit 1
    fi

    # Pakete parsen und scannen
    local overall_pipeline_status="ok"
    local package_path
    local package_name
    local package_version
    local arch
    local checksum
    local package_id
    local scan_result

    while IFS= read -r package; do
        package_name=$(echo "${package}" | jq -r '.name')
        package_version=$(echo "${package}" | jq -r '.version')
        arch=$(echo "${package}" | jq -r '.arch')
        checksum=$(echo "${package}" | jq -r '.checksum')
        package_path=$(echo "${package}" | jq -r '.path')

        # In DB eintragen
        db_insert_package "${repo_name}" "${snapshot_id}" \
            "${package_name}" "${package_version}" "${arch}" "${checksum}"

        # Package-ID holen
        package_id=$(db_get_package_id "${repo_name}" "${snapshot_id}" \
            "${package_name}" "${package_version}" "${arch}")

        # Bereits gescannt und OK? Überspringen
        if db_package_all_scans_ok "${package_id}" 2>/dev/null; then
            local pkg_status
            pkg_status=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" \
                -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
                -se "SELECT status FROM packages WHERE id=${package_id};")
            if [ "${pkg_status}" = "ok" ]; then
                log "INFO" "Paket bereits geprüft und OK: ${package_name}-${package_version}"
                continue
            fi
        fi

        # Paket scannen
        scan_result=$(scan_package "${package_path}" "${package_id}" \
            "${repo_name}" "${package_name}" "${package_version}")

        if [ "${scan_result}" = "fail" ]; then
            overall_pipeline_status="fail"
            if [ "${BLOCK_ON_FAIL}" = "true" ]; then
                log "WARN" "BLOCK_ON_FAIL aktiv — Pipeline wird nach aktuellem Paket nicht abgebrochen, aber Promote wird blockiert"
            fi
        fi

    done < <(echo "${packages_json}" | jq -c '.[]')

    # Promote-Entscheidung
    if [ "${do_promote}" = "true" ]; then
        if [ "${overall_pipeline_status}" = "fail" ] && [ "${BLOCK_ON_FAIL}" = "true" ]; then
            log "WARN" "Promote nach prod BLOCKIERT — mindestens ein Paket hat den Security-Check nicht bestanden"
            db_log_promote "${repo_name}" "${snapshot_id}" "preprod" "prod" "blocked" \
                "Security-Check fehlgeschlagen"
            alert_mail \
                "[REPO-SECURITY] Promote blockiert: ${repo_name} Snapshot ${snapshot_id}" \
                "Promote wurde blockiert da mindestens ein Paket den Security-Check nicht bestanden hat."
        else
            log "INFO" "Alle Checks bestanden — Promote nach prod wird durchgeführt"
            api_point_environment "${repo_name}" "${snapshot_id}" "prod"
            db_log_promote "${repo_name}" "${snapshot_id}" "preprod" "prod" "promoted" "Alle Checks OK"
            alert_promoted "${repo_name}" "${snapshot_id}"
        fi
    fi

    log "INFO" "Pipeline abgeschlossen. Gesamtstatus: ${overall_pipeline_status}"
}

main "$@"
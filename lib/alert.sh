#!/bin/bash
# ============================================================
# alert.sh
# Alert-Funktionen für Wazuh und Mail
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

# Log-Funktion
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Wazuh-Alert via lokalem Log
alert_wazuh() {
    local repo_name="$1"
    local package_name="$2"
    local package_version="$3"
    local tool="$4"
    local severity="$5"
    local message="$6"

    local alert_json
    alert_json=$(cat <<EOF
{
    "timestamp": "$(date '+%Y-%m-%dT%H:%M:%S')",
    "source": "repo-security",
    "repo": "${repo_name}",
    "package": "${package_name}",
    "version": "${package_version}",
    "tool": "${tool}",
    "severity": "${severity}",
    "message": "${message}"
}
EOF
)
    echo "${alert_json}" >> "${WAZUH_AGENT_LOG}"
    log "WARN" "Wazuh-Alert gesendet: ${package_name}-${package_version} [${tool}] ${severity}"
}

# Mail-Alert
alert_mail() {
    local subject="$1"
    local body="$2"

    echo "${body}" | mail -s "${subject}" \
        -r "${ALERT_MAIL_FROM}" \
        -S smtp="${ALERT_MAIL_SMTP}" \
        "${ALERT_MAIL_TO}"

    log "INFO" "Mail-Alert gesendet an ${ALERT_MAIL_TO}: ${subject}"
}

# Kombinierter Alert bei blockiertem Paket
alert_blocked_package() {
    local repo_name="$1"
    local package_name="$2"
    local package_version="$3"
    local tool="$4"
    local severity="$5"
    local output="$6"

    local subject="[REPO-SECURITY] Paket blockiert: ${package_name}-${package_version}"
    local body="Paket wurde blockiert und nicht nach prod promoted.

Repo:     ${repo_name}
Paket:    ${package_name}
Version:  ${package_version}
Tool:     ${tool}
Severity: ${severity}

Output:
${output}"

    alert_wazuh "${repo_name}" "${package_name}" "${package_version}" "${tool}" "${severity}" "${output}"
    alert_mail "${subject}" "${body}"
}

# Alert bei erfolgreichem Promote
alert_promoted() {
    local repo_name="$1"
    local snapshot_id="$2"

    log "INFO" "Snapshot ${snapshot_id} von ${repo_name} erfolgreich nach prod promoted."
    alert_mail \
        "[REPO-SECURITY] Promote erfolgreich: ${repo_name} Snapshot ${snapshot_id}" \
        "Snapshot ${snapshot_id} des Repos ${repo_name} wurde erfolgreich nach prod promoted."
}
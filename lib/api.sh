#!/bin/bash
# ============================================================
# api.sh
# Repomanager API-Funktionen
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

# ============================================================
# Hilfsfunktionen
# ============================================================

# Session-Cookie holen via Login
api_login() {
    local cookie_file="/tmp/repo-security-session.txt"

    curl -s -c "${cookie_file}" \
        -X POST \
        -d "authType=local&username=${REPOMANAGER_USER}&password=${REPOMANAGER_PASS}" \
        -L \
        "${REPOMANAGER_URL}/login" > /dev/null

    echo "${cookie_file}"
}

# ============================================================
# Repo-Funktionen via /api/v2/
# ============================================================

# Alle Repos abrufen
api_get_repos() {
    curl -s \
        -H "Authorization: Bearer ${REPOMANAGER_API_KEY}" \
        "${REPOMANAGER_URL}/api/v2/repo"
}

# Repo-ID anhand von Name ermitteln
api_get_repo_id() {
    local repo_name="$1"

    api_get_repos | jq -r \
        ".results[] | select(.Name==\"${repo_name}\") | .Id"
}

# Package-Type eines Repos aus der API ermitteln
api_get_package_type() {
    local repo_name="$1"

    api_get_repos | jq -r \
        ".results[] | select(.Name==\"${repo_name}\") | .Package_type"
}

# Snapshots eines Repos abrufen
api_get_snapshots() {
    local repo_id="$1"

    curl -s \
        -H "Authorization: Bearer ${REPOMANAGER_API_KEY}" \
        "${REPOMANAGER_URL}/api/v2/repo/${repo_id}"
}

# Neuesten Snapshot-ID eines Repos ermitteln
api_get_latest_snapshot_id() {
    local repo_id="$1"

    api_get_snapshots "${repo_id}" | jq -r \
        ".results | sort_by(.Date, .Time) | last | .Id"
}

# ============================================================
# Filesystem-Funktionen für Paketliste
# ============================================================

# Neuestes Snapshot-Datum eines Repos ermitteln
api_get_latest_snapshot_date() {
    local repo_name="$1"
    local package_type="$2"

    local base_path
    if [ "${package_type}" = "rpm" ]; then
        base_path="/mnt/repomanager-repo/rpm/${repo_name}"
    else
        base_path="/mnt/repomanager-repo/deb/${repo_name}"
    fi

    find "${base_path}" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | \
        grep -oP '\d{4}-\d{2}-\d{2}' | sort | tail -1
}

# Paketliste eines Repos aus dem Filesystem holen
api_get_packages() {
    local repo_name="$1"
    local snapshot_date="$2"
    local package_type="$3"

    local base_path
    if [ "${package_type}" = "rpm" ]; then
        base_path="/mnt/repomanager-repo/rpm/${repo_name}"
    else
        base_path="/mnt/repomanager-repo/deb/${repo_name}"
    fi

    # Snapshot-Datum ermitteln wenn nicht angegeben
    if [ -z "${snapshot_date}" ]; then
        snapshot_date=$(api_get_latest_snapshot_date "${repo_name}" "${package_type}")
    fi

    if [ -z "${snapshot_date}" ]; then
        echo "FEHLER: Kein Snapshot gefunden unter ${base_path}"
        return 1
    fi

    # Pakete auflisten
    if [ "${package_type}" = "rpm" ]; then
        find "${base_path}" -path "*/${snapshot_date}/*" -name "*.rpm" 2>/dev/null
    else
        find "${base_path}" -path "*/${snapshot_date}/*" -name "*.deb" 2>/dev/null
    fi
}

# ============================================================
# Environment-Funktionen via SQLite
# ============================================================

# repos_env ID ermitteln anhand snap_id und env_name
api_get_env_id() {
    local snap_id="$1"
    local env_name="$2"

    sqlite3 "${REPOMANAGER_DB_PATH}" \
        "SELECT Id FROM repos_env WHERE Id_snap=${snap_id} AND Env='${env_name}';"
}

# ============================================================
# Promote via ajax/controller.php
# ============================================================

api_point_environment() {
    local repo_id="$1"
    local snap_id="$2"
    local env_name="$3"

    local env_id
    env_id=$(api_get_env_id "${snap_id}" "${env_name}")

    if [ -z "${env_id}" ]; then
        echo "FEHLER: Environment '${env_name}' für Snapshot '${snap_id}' nicht gefunden — möglicherweise noch nicht in repos_env eingetragen"
        return 1
    fi

    local cookie_file
    cookie_file=$(api_login)

    local payload
    payload=$(printf '[{"repo-id":"%s","snap-id":"%s","env-id":"%s"}]' \
        "${repo_id}" "${snap_id}" "${env_id}")

    local response
    response=$(curl -s \
        -b "${cookie_file}" \
        -X POST \
        -d "controller=general&action=get-panel&name=repos/task&params[action]=env&params[repos]=${payload}" \
        "${REPOMANAGER_URL}/ajax/controller.php")

    rm -f "${cookie_file}"

    echo "${response}"
}
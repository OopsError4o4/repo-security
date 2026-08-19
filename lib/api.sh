#!/bin/bash
# ============================================================
# api.sh
# Repomanager API-Funktionen
# ============================================================

source "$(dirname "$0")/../conf/repo-security.conf"

# ============================================================
# Hilfsfunktionen
# ============================================================

# Session-Cookie holen via Login
api_login() {
    local cookie_file="/tmp/repo-security-session.txt"

    curl -s -c "${cookie_file}" \
        -X POST \
        -d "username=${REPOMANAGER_USER}&password=${REPOMANAGER_PASS}" \
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
# Environment-Funktionen via SQLite
# ============================================================

# Environment-ID aus SQLite-DB lesen
api_get_env_id() {
    local env_name="$1"

    sqlite3 "${REPOMANAGER_DB_PATH}" \
        "SELECT Id FROM env WHERE Name='${env_name}';"
}

# ============================================================
# Promote via ajax/controller.php
# ============================================================

api_point_environment() {
    local repo_id="$1"
    local snap_id="$2"
    local env_name="$3"

    local env_id
    env_id=$(api_get_env_id "${env_name}")

    if [ -z "${env_id}" ]; then
        echo "FEHLER: Environment '${env_name}' nicht gefunden"
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
        -F "controller=general" \
        -F "action=get-panel" \
        -F "name=repos/task" \
        -F "params[action]=env" \
        -F "params[repos]=${payload}" \
        "${REPOMANAGER_URL}/ajax/controller.php")

    rm -f "${cookie_file}"

    echo "${response}"
}
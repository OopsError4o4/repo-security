#!/bin/bash
# ============================================================
# api.sh
# Repomanager API-Funktionen
# ============================================================

source "$(dirname "$0")/../conf/repo-security.conf"

# Alle Snapshots eines Repos abrufen
api_get_snapshots() {
    local repo_name="$1"
    curl -s -H "Authorization: Bearer ${REPOMANAGER_API_KEY}" \
        "${REPOMANAGER_URL}/api/v2/repos/${repo_name}/snapshots"
}

# Environment auf einen Snapshot zeigen lassen (Promote)
api_point_environment() {
    local repo_name="$1"
    local snapshot_id="$2"
    local environment="$3"

    curl -s -X POST \
        -H "Authorization: Bearer ${REPOMANAGER_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"environment\": \"${environment}\"}" \
        "${REPOMANAGER_URL}/api/v2/repos/${repo_name}/snapshots/${snapshot_id}/env"
}

# Paketliste eines Snapshots abrufen
api_get_packages() {
    local repo_name="$1"
    local snapshot_id="$2"

    curl -s -H "Authorization: Bearer ${REPOMANAGER_API_KEY}" \
        "${REPOMANAGER_URL}/api/v2/repos/${repo_name}/snapshots/${snapshot_id}/packages"
}

# Alle Repos abrufen
api_get_repos() {
    curl -s -H "Authorization: Bearer ${REPOMANAGER_API_KEY}" \
        "${REPOMANAGER_URL}/api/v2/repos"
}
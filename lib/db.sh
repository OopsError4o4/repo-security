#!/bin/bash
# ============================================================
# db.sh
# MariaDB-Funktionen für die Security-Pipeline
# ============================================================

SCRIPT_BASE_DIR="/opt/repo-security"
source "${SCRIPT_BASE_DIR}/conf/repo-security.conf"

# DB-Verbindung testen
db_check_connection() {
    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" \
        -e "SELECT 1;" "${DB_NAME}" &>/dev/null
    return $?
}

# Tabellen anlegen falls nicht vorhanden
db_init() {
    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" <<EOF
CREATE TABLE IF NOT EXISTS packages (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    repo_name       VARCHAR(255) NOT NULL,
    snapshot_id     VARCHAR(255) NOT NULL,
    package_name    VARCHAR(255) NOT NULL,
    package_version VARCHAR(255) NOT NULL,
    arch            VARCHAR(64),
    checksum        VARCHAR(512),
    status          ENUM('pending','scanning','ok','blocked') DEFAULT 'pending',
    created_at      DATETIME DEFAULT NOW(),
    updated_at      DATETIME DEFAULT NOW() ON UPDATE NOW(),
    UNIQUE KEY uq_package (repo_name, snapshot_id, package_name, package_version, arch)
);

CREATE TABLE IF NOT EXISTS scan_results (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    package_id  INT NOT NULL,
    tool        VARCHAR(64) NOT NULL,
    status      ENUM('ok','warn','fail') NOT NULL,
    severity    VARCHAR(64),
    output      TEXT,
    scanned_at  DATETIME DEFAULT NOW(),
    FOREIGN KEY (package_id) REFERENCES packages(id)
);

CREATE TABLE IF NOT EXISTS promote_log (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    repo_name   VARCHAR(255) NOT NULL,
    snapshot_id VARCHAR(255) NOT NULL,
    from_env    VARCHAR(64) NOT NULL,
    to_env      VARCHAR(64) NOT NULL,
    status      ENUM('promoted','blocked') NOT NULL,
    reason      TEXT,
    promoted_at DATETIME DEFAULT NOW()
);
EOF
}

# Paket einfügen oder ignorieren wenn schon vorhanden
db_insert_package() {
    local repo_name="$1"
    local snapshot_id="$2"
    local package_name="$3"
    local package_version="$4"
    local arch="$5"
    local checksum="$6"

    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" <<EOF
INSERT IGNORE INTO packages (repo_name, snapshot_id, package_name, package_version, arch, checksum, status)
VALUES ('${repo_name}', '${snapshot_id}', '${package_name}', '${package_version}', '${arch}', '${checksum}', 'pending');
EOF
}

# Scan-Ergebnis schreiben
db_write_scan_result() {
    local package_id="$1"
    local tool="$2"
    local status="$3"
    local severity="$4"
    local output="$5"

    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" <<EOF
INSERT INTO scan_results (package_id, tool, status, severity, output)
VALUES (${package_id}, '${tool}', '${status}', '${severity}', '${output}');
EOF
}

# Paket-Status aktualisieren
db_update_package_status() {
    local package_id="$1"
    local status="$2"

    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" <<EOF
UPDATE packages SET status='${status}' WHERE id=${package_id};
EOF
}

# Promote-Log schreiben
db_log_promote() {
    local repo_name="$1"
    local snapshot_id="$2"
    local from_env="$3"
    local to_env="$4"
    local status="$5"
    local reason="$6"

    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" <<EOF
INSERT INTO promote_log (repo_name, snapshot_id, from_env, to_env, status, reason)
VALUES ('${repo_name}', '${snapshot_id}', '${from_env}', '${to_env}', '${status}', '${reason}');
EOF
}

# Package-ID anhand von Name/Version/Arch abrufen
db_get_package_id() {
    local repo_name="$1"
    local snapshot_id="$2"
    local package_name="$3"
    local package_version="$4"
    local arch="$5"

    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
        -se "SELECT id FROM packages WHERE repo_name='${repo_name}' AND snapshot_id='${snapshot_id}' AND package_name='${package_name}' AND package_version='${package_version}' AND arch='${arch}';"
}

# Prüfen ob alle Scans eines Pakets OK sind
db_package_all_scans_ok() {
    local package_id="$1"

    local fail_count
    fail_count=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
        -se "SELECT COUNT(*) FROM scan_results WHERE package_id=${package_id} AND status='fail';")

    [ "${fail_count}" -eq 0 ]
}
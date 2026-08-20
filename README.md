# repo-security

Automatisierte Security-Pipeline für [Repomanager](https://github.com/lbr38/repomanager).  
Scannt Pakete in `preprod`-Repositories und promotet validierte Snapshots nach `prod`.

## Workflow

Repomanager Mirror-Sync
↓
preprod Snapshot
↓
repo-security Pipeline
↓
┌─────────────────┐ ┌──────────────────┐
│ Alle OK         │ │ FAIL             │
│ → promote       │ │ → blockiert      │
│ nach prod       │ │ → Alert (Mail    │
│                 │ │ + Wazuh)         │
└─────────────────┘ └──────────────────┘


## Scan-Tools

| Kategorie | Tool       | Beschreibung                                        |
|-----------|------------|-----------------------------------------------------|
| CSA       | Trivy      | CVE-Scan auf extrahiertem Paketinhalt               |
| CSA       | Grype      | CVE-Scan (Anchore)                                  |
| AV        | ClamAV     | Malware-Scan                                        |
| SAST      | cppcheck   | C/C++ SAST (nur bei C/C++ Paketen)                  |
| SAST      | YARA       | Pattern-Matching via Neo23x0/signature-base         |

### Deaktivierte Tools

| Tool       | Grund                                                      |
|------------|------------------------------------------------------------|
| rkhunter   | Für laufende Systeme konzipiert, nicht für Paketinhalte    |
| chkrootkit | Nicht in EPEL 10 verfügbar                                 |
| Bandit     | Python-SAST — für OS-Pakete nicht relevant                 |

## Voraussetzungen

- AlmaLinux 9/10 oder RHEL-kompatibel
- Repomanager (Docker oder Podman)
- MariaDB
- `jq`, `curl`, `sqlite3`, `dos2unix`
- Scan-Tools: `trivy`, `grype`, `clamav`, `cppcheck`, `yara`
- YARA-Rules: `git clone https://github.com/Neo23x0/signature-base /opt/repo-security/yara-rules`

## Installation

```bash
git clone https://github.com/OopsError4o4/repo-security.git /opt/repo-security
cd /opt/repo-security
chmod +x repo-security.sh
```

## Konfiguration

```bash
cp conf/repo-security.conf.example conf/repo-security.conf
vi conf/repo-security.conf
```

| Parameter               | Beschreibung                                              |
|-------------------------|-----------------------------------------------------------|
| REPOMANAGER_URL         | URL des Repomanager-Servers inkl. Port                    |
| REPOMANAGER_API_KEY     | API-Key des Repomanager-Benutzers                         |
| REPOMANAGER_USER        | Repomanager-Login (für Promote via ajax/controller.php)   |
| REPOMANAGER_PASS        | Repomanager-Passwort                                      |
| REPOMANAGER_DB_PATH     | Pfad zur SQLite-DB (Docker oder Podman)                   |
| DB_HOST/DB_NAME/DB_USER | MariaDB-Verbindungsparameter                              |
| DB_PASS                 | MariaDB-Passwort                                          |
| BLOCK_ON_FAIL           | Promote blockieren bei FAIL (true/false)                  |
| SCAN_*                  | Einzelne Scan-Tools aktivieren/deaktivieren               |

### DB_PATH Beispiele

```bash
# Docker
REPOMANAGER_DB_PATH="/var/lib/docker/volumes/repomanager_repomanager-data/_data/db/repomanager.db"

# Podman
REPOMANAGER_DB_PATH="/var/lib/containers/storage/volumes/repomanager_repomanager-data/_data/db/repomanager.db"
```

## MariaDB einrichten

```bash
mysql -u root <<EOF
CREATE DATABASE repo_security CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'repo_security'@'localhost' IDENTIFIED BY 'CHANGEME';
GRANT ALL PRIVILEGES ON repo_security.* TO 'repo_security'@'localhost';
FLUSH PRIVILEGES;
EOF
```

## Verwendung

```bash
# Scan ohne Promote
./repo-security.sh --repo almalinux10-baseos

# Scan mit automatischem Promote nach prod
./repo-security.sh --repo almalinux10-baseos --promote

# Scan mit Limit (zum Testen)
./repo-security.sh --repo almalinux10-baseos --limit 5 --promote
```

## Modularer Aufbau

/opt/repo-security/
├── repo-security.sh # Orchestrierung
├── conf/
│ ├── repo-security.conf # Lokale Konfiguration (nicht im Repo)
│ └── repo-security.conf.example # Vorlage
├── lib/
│ ├── db.sh # MariaDB-Funktionen
│ ├── api.sh # Repomanager API + Filesystem-Zugriff
│ ├── alert.sh # Wazuh + Mail Alerts
│ └── scan/
│ ├── trivy.sh
│ ├── grype.sh
│ ├── clamav.sh
│ ├── yara.sh
│ ├── rkhunter.sh # deaktiviert
│ ├── chkrootkit.sh # deaktiviert
│ ├── bandit.sh # deaktiviert
│ └── cppcheck.sh
├── yara-rules/ # Neo23x0/signature-base (nicht im Repo)
└── logs/
└── repo-security.log



## Exit-Codes der Scan-Module

| Exit-Code | Bedeutung |
|-----------|-----------|
| 0         | OK        |
| 1         | WARN      |
| 2         | FAIL      |

## Datenbank-Schema

```sql
packages      -- Pakete mit Status (pending/scanning/ok/blocked)
scan_results  -- Ergebnisse pro Paket und Tool
promote_log   -- Audit-Trail aller Promote-Aktionen
```

## Lizenz

GPL-3.0 — siehe [LICENSE](LICENSE)
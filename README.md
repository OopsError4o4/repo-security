# repo-security
Security-Pipeline für [Repomanager](https://github.com/lbr38/repomanager) — automatisierter Security-Scan von Paketen vor dem Promote von `preprod` nach `prod`.

## Übersicht

Repomanager Mirror-Sync
↓
preprod Snapshot
↓
Security-Pipeline (dieses Script)
↓
┌─────────────┐ ┌─────────────┐
│ Alle OK     │ │ FAIL        │
│ → promote   │ │ → blockiert │
│ nach prod   │ │ → Alert     │
└─────────────┘ └─────────────┘


## Scan-Tools

| Kategorie | Tool       | Beschreibung                          |
|-----------|------------|---------------------------------------|
| CSA       | Trivy      | CVE-Scan auf Paketebene               |
| CSA       | Grype      | CVE-Scan (Anchore)                    |
| AV        | ClamAV     | Malware-Scan                          |
| AV        | rkhunter   | Rootkit-Scan auf extrahiertem Inhalt  |
| AV        | chkrootkit | Rootkit-Scan auf extrahiertem Inhalt  |
| SAST      | Bandit     | Python SAST (nur bei Python-Paketen)  |
| SAST      | cppcheck   | C/C++ SAST (nur bei C/C++ Paketen)    |
| SAST      | YARA       | Custom Pattern-Matching               |

## Voraussetzungen

- Bash 4+
- MariaDB (Datenbank für Scan-Ergebnisse und Audit-Trail)
- `jq` (JSON-Verarbeitung)
- `curl` (API-Calls)
- `mail` (Alert-Versand)
- Repomanager mit aktivierter API
- Scan-Tools je nach Konfiguration installiert

## Installation

```bash
git clone https://github.com/<dein-username>/repo-security.git /opt/repo-security
cd /opt/repo-security
chmod +x repo-security.sh lib/scan/*.sh
```

## Konfiguration

```bash
cp conf/repo-security.conf.example conf/repo-security.conf
vi conf/repo-security.conf
```

Wichtige Parameter:

| Parameter           | Beschreibung                              |
|---------------------|-------------------------------------------|
| REPOMANAGER_URL     | URL des Repomanager-Servers               |
| REPOMANAGER_API_KEY | API-Key des Repomanager-Benutzers         |
| DB_HOST             | MariaDB-Host                              |
| DB_NAME             | Datenbankname                             |
| DB_USER             | Datenbankbenutzer                         |
| DB_PASS             | Datenbankpasswort                         |
| BLOCK_ON_FAIL       | Promote blockieren bei FAIL (true/false)  |
| SCAN_*              | Einzelne Scan-Tools aktivieren/deaktivieren |

## Verwendung

```bash
# Scan ohne Promote
./repo-security.sh --repo almalinux10-appstream --snapshot <snapshot_id>

# Scan mit automatischem Promote nach prod bei Erfolg
./repo-security.sh --repo almalinux10-appstream --snapshot <snapshot_id> --promote
```

## Modularer Aufbau

/opt/repo-security/
├── repo-security.sh # Orchestrierung
├── conf/
│ └── repo-security.conf # Zentrale Konfiguration
├── lib/
│ ├── db.sh # MariaDB-Funktionen
│ ├── api.sh # Repomanager API-Calls
│ ├── alert.sh # Wazuh + Mail Alerts
│ └── scan/
│ ├── trivy.sh
│ ├── grype.sh
│ ├── clamav.sh
│ ├── yara.sh
│ ├── rkhunter.sh
│ ├── chkrootkit.sh
│ ├── bandit.sh
│ └── cppcheck.sh
└── logs/
└── repo-security.log


## Exit-Codes der Scan-Module

| Exit-Code | Bedeutung |
|-----------|-----------|
| 0         | OK        |
| 1         | WARN      |
| 2         | FAIL      |

## Lizenz

GPL-3.0 — siehe [LICENSE](LICENSE)

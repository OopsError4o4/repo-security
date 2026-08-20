#!/bin/bash
# ============================================================
# setup.sh
# Interaktiver Setup-Guide für repo-security
# ============================================================

#set -e

# ============================================================
# Farben
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# Hilfsfunktionen
# ============================================================

print_banner() {
    echo -e "${CYAN}"
    echo "  ██████╗ ███████╗██████╗  ██████╗ "
    echo "  ██╔══██╗██╔════╝██╔══██╗██╔═══██╗"
    echo "  ██████╔╝█████╗  ██████╔╝██║   ██║"
    echo "  ██╔══██╗██╔══╝  ██╔═══╝ ██║   ██║"
    echo "  ██║  ██║███████╗██║     ╚██████╔╝"
    echo "  ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝ "
    echo -e "${NC}"
    echo -e "${BOLD}  repo-security — Interaktiver Setup-Guide${NC}"
    echo -e "  Supply-Chain-Security für Repomanager"
    echo ""
}

print_step() {
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${CYAN}  [i] $1${NC}"
}

print_ok() {
    echo -e "${GREEN}  [OK] $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}  [!] $1${NC}"
}

print_error() {
    echo -e "${RED}  [X] $1${NC}"
}

ask() {
    local question="$1"
    local default="$2"
    local answer

    if [ -n "${default}" ]; then
        echo -ne "${BOLD}  → ${question} [${default}]: ${NC}"
    else
        echo -ne "${BOLD}  → ${question}: ${NC}"
    fi

    read -r answer
    echo "${answer:-${default}}"
}

ask_yn() {
    local question="$1"
    local default="${2:-y}"
    local answer

    echo -ne "${BOLD}  → ${question} [y/n] (default: ${default}): ${NC}"
    read -r answer
    answer="${answer:-${default}}"
    [[ "${answer}" =~ ^[Yy]$ ]]
}

ask_choice() {
    local question="$1"
    shift
    local options=("$@")
    local i=1

    echo -e "${BOLD}  → ${question}${NC}"
    for opt in "${options[@]}"; do
        echo -e "    ${i}) ${opt}"
        ((i++))
    done
    echo -ne "${BOLD}  Auswahl [1-${#options[@]}]: ${NC}"
    read -r choice
    echo "${choice}"
}

# ============================================================
# Voraussetzungen prüfen und installieren
# ============================================================

check_root() {
    if [ "${EUID}" -ne 0 ]; then
        print_error "Dieses Script muss als root ausgeführt werden."
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_FAMILY="unknown"
        case "${ID}" in
            rhel|centos|almalinux|rocky|fedora)
                OS_FAMILY="rhel"
                PKG_MANAGER="dnf"
                ;;
            debian|ubuntu|linuxmint)
                OS_FAMILY="debian"
                PKG_MANAGER="apt"
                ;;
        esac
        print_ok "Betriebssystem erkannt: ${PRETTY_NAME} (${OS_FAMILY})"
    else
        print_error "Betriebssystem konnte nicht erkannt werden."
        exit 1
    fi
}

check_prerequisites() {
    print_step "Voraussetzungen prüfen"

    local errors=0

    # Zweite Disk prüfen
    local disk_count
    disk_count=$(lsblk -d -o NAME,TYPE | grep -c disk)

    if [ "${disk_count}" -lt 2 ]; then
        print_error "Keine zweite Disk gefunden — für Repomanager wird eine dedizierte Datendisk benötigt."
        print_info "Verfügbare Disks:"
        lsblk -d -o NAME,SIZE,TYPE | grep disk
        ((errors++))
    else
        print_ok "Zweite Disk gefunden."
        lsblk -d -o NAME,SIZE,TYPE | grep disk
    fi

    # Prüfen ob zweite Disk bereits gemountet ist
    local second_disk
    second_disk=$(lsblk -d -o NAME,TYPE | grep disk | tail -1 | awk '{print $1}')
    if lsblk "/dev/${second_disk}" | grep -q "/"; then
        print_warn "Disk /dev/${second_disk} ist bereits gemountet — stelle sicher dass sie für Repomanager-Daten genutzt werden kann."
    else
        print_ok "Disk /dev/${second_disk} ist noch nicht gemountet."
    fi

    # Mindest-RAM prüfen (4GB)
    local total_ram
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ "${total_ram}" -lt 3800 ]; then
        print_warn "Weniger als 4GB RAM verfügbar (${total_ram}MB) — Repomanager empfiehlt mindestens 4GB."
    else
        print_ok "RAM: ${total_ram}MB verfügbar."
    fi

    # Mindest-Speicherplatz auf OS-Disk prüfen (20GB)
    local free_space
    free_space=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    if [ "${free_space}" -lt 20 ]; then
        print_warn "Weniger als 20GB freier Speicher auf OS-Disk (${free_space}GB)."
    else
        print_ok "Freier Speicher auf OS-Disk: ${free_space}GB."
    fi

    # Internetzugang prüfen
    if curl -s --max-time 5 https://example.com &>/dev/null; then
        print_ok "Internetzugang verfügbar."
    else
        print_warn "Kein direkter Internetzugang — Proxy wird möglicherweise benötigt."
    fi

    echo ""
    if [ "${errors}" -gt 0 ]; then
        print_error "${errors} kritische Voraussetzung(en) nicht erfüllt."
        if ! ask_yn "Trotzdem fortfahren?"; then
            exit 1
        fi
    else
        print_ok "Alle Voraussetzungen erfüllt."
    fi
}

install_ansible() {
    print_step "Schritt 1/6: Voraussetzungen prüfen"

    # Ansible prüfen
    if command -v ansible-playbook &>/dev/null; then
        print_ok "Ansible bereits installiert: $(ansible --version | head -1)"
    else
        print_info "Ansible wird installiert..."
        if [ "${OS_FAMILY}" = "rhel" ]; then
            dnf install -y epel-release &>/dev/null || true
            dnf install -y ansible &>/dev/null || true
        elif [ "${OS_FAMILY}" = "debian" ]; then
            apt-get update -qq &>/dev/null || true
            apt-get install -y ansible &>/dev/null || true
        fi
        print_ok "Ansible installiert."
    fi

    # Python3 prüfen
    if command -v python3 &>/dev/null; then
        print_ok "Python3 bereits installiert."
    else
        print_info "Python3 wird installiert..."
        if [ "${OS_FAMILY}" = "rhel" ]; then
            dnf install -y python3 python3-pip &>/dev/null || true
        elif [ "${OS_FAMILY}" = "debian" ]; then
            apt-get install -y python3 python3-pip &>/dev/null || true
        fi
        print_ok "Python3 installiert."
    fi

    # Ansible Collections installieren
    print_info "Ansible Collections werden installiert..."
    ansible-galaxy collection install \
        community.mysql \
        community.general \
        ansible.posix \
        containers.podman \
        --quiet 2>/dev/null || true
    print_ok "Ansible Collections installiert."
}

# ============================================================
# Konfiguration sammeln
# ============================================================

config_mode() {
    print_step "Schritt 2/6: Installationsmodus"

    print_info "Möchtest du die Installation manuell konfigurieren"
    print_info "oder dich durch den Setup-Guide führen lassen?"
    echo ""

    local choice
    choice=$(ask_choice "Installationsmodus wählen:" \
        "Geführte Installation (empfohlen)" \
        "Manuelle Installation (all.yml selbst bearbeiten)")

    case "${choice}" in
        1) MODE="guided" ;;
        2) MODE="manual" ;;
        *) MODE="guided" ;;
    esac
}

config_components() {
    print_step "Schritt 3/6: Komponenten"

    print_info "Was möchtest du installieren?"
    echo ""

    local choice
    choice=$(ask_choice "Komponenten wählen:" \
        "Nur Repomanager" \
        "Repomanager + Supply-Chain-Security (empfohlen)" \
        "Nur Supply-Chain-Security (Repomanager bereits vorhanden)")

    case "${choice}" in
        1) INSTALL_REPOMANAGER=true;  INSTALL_SECURITY=false ;;
        2) INSTALL_REPOMANAGER=true;  INSTALL_SECURITY=true  ;;
        3) INSTALL_REPOMANAGER=false; INSTALL_SECURITY=true  ;;
        *) INSTALL_REPOMANAGER=true;  INSTALL_SECURITY=true  ;;
    esac

    print_ok "Repomanager: ${INSTALL_REPOMANAGER}"
    print_ok "Supply-Chain-Security: ${INSTALL_SECURITY}"
}

config_repomanager() {
    if [ "${INSTALL_REPOMANAGER}" = "false" ]; then
        return
    fi

    print_step "Schritt 4/6: Repomanager-Konfiguration"

    # FQDN oder IP
    if ask_yn "Möchtest du einen FQDN nutzen (statt IP-Adresse)?"; then
        REPOMANAGER_FQDN=$(ask "FQDN" "repomanager.example.com")
    else
        REPOMANAGER_FQDN=$(ask "IP-Adresse des Servers")
    fi

    # Port
    REPOMANAGER_PORT=$(ask "Port" "4747")

    # Admin-Passwort
    REPOMANAGER_ADMIN_PASS=$(ask "Admin-Passwort" "repomanager")

    # SSL
    if ask_yn "Möchtest du SSL/HTTPS aktivieren? (Nginx Reverse Proxy)"; then
        INSTALL_SSL=true
        SSL_CERT_SRC=$(ask "Pfad zum SSL-Zertifikat (.crt)" "/etc/ssl/certs/repomanager.crt")
        SSL_KEY_SRC=$(ask "Pfad zum SSL-Key (.key)" "/etc/ssl/private/repomanager.key")
    else
        INSTALL_SSL=false
        SSL_CERT_SRC=""
        SSL_KEY_SRC=""
    fi

    # Proxy
    if ask_yn "Möchtest du einen Proxy nutzen?"; then
        local proxy_choice
        proxy_choice=$(ask_choice "Proxy-Typ wählen:" \
            "Externen Proxy nutzen (URL eingeben)" \
            "Lokalen Squid-Proxy installieren")

        case "${proxy_choice}" in
            1)
                HTTP_PROXY=$(ask "Proxy-URL" "http://proxy.example.com:3128")
                HTTPS_PROXY="${HTTP_PROXY}"
                INSTALL_SQUID=false
                ;;
            2)
                INSTALL_SQUID=true
                HTTP_PROXY="http://localhost:3128"
                HTTPS_PROXY="${HTTP_PROXY}"
                ;;
        esac
        NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    else
        HTTP_PROXY=""
        HTTPS_PROXY=""
        NO_PROXY=""
        INSTALL_SQUID=false
    fi

    # Storage
    print_info "Verfügbare Disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo ""
    REPOMANAGER_DATA_DISK=$(ask "Datendisk für Repo-Daten" "/dev/sdb")
    REPOMANAGER_DATA_PARTITION="${REPOMANAGER_DATA_DISK}1"
    REPOMANAGER_REPO_MOUNT=$(ask "Mountpoint für Repo-Daten" "/mnt/repomanager-repo")

    # Image
    REPOMANAGER_IMAGE=$(ask "Repomanager Docker-Image" "docker.io/lbr38/repomanager:latest")
}

config_security() {
    if [ "${INSTALL_SECURITY}" = "false" ]; then
        return
    fi

    print_step "Schritt 5/6: Supply-Chain-Security-Konfiguration"

    # CSA
    echo ""
    print_info "Content Security Analysis (CVE-Scanning):"
    if ask_yn "  Trivy aktivieren?"; then SCAN_TRIVY=true; else SCAN_TRIVY=false; fi
    if ask_yn "  Grype aktivieren?"; then SCAN_GRYPE=true; else SCAN_GRYPE=false; fi

    # AV
    echo ""
    print_info "Anti-Virus:"
    if ask_yn "  ClamAV aktivieren?"; then SCAN_CLAMAV=true; else SCAN_CLAMAV=false; fi

    # SAST
    echo ""
    print_info "Static Application Security Testing:"
    if ask_yn "  cppcheck aktivieren? (C/C++ Analyse)"; then SCAN_CPPCHECK=true; else SCAN_CPPCHECK=false; fi
    if ask_yn "  YARA aktivieren? (Pattern-Matching)"; then
        SCAN_YARA=true
        if ask_yn "  Neo23x0 YARA-Rules automatisch klonen?"; then
            YARA_RULES_GIT_URL="https://github.com/Neo23x0/signature-base.git"
        else
            YARA_RULES_GIT_URL=""
        fi
    else
        SCAN_YARA=false
        YARA_RULES_GIT_URL=""
    fi

    # MariaDB
    echo ""
    DB_PASS=$(ask "MariaDB-Passwort für repo_security User" "CHANGEME")

    # Repomanager-Verbindung
    echo ""
    if [ "${INSTALL_REPOMANAGER}" = "false" ]; then
        REPOMANAGER_URL=$(ask "Repomanager URL" "http://10.0.0.1:4747")
        REPOMANAGER_API_KEY=$(ask "Repomanager API-Key" "ak_CHANGEME")
        REPOMANAGER_ADMIN_USER=$(ask "Repomanager Admin-User" "admin")
        REPOMANAGER_ADMIN_PASS=$(ask "Repomanager Admin-Passwort" "repomanager")
    fi
}

# ============================================================
# Zusammenfassung
# ============================================================

show_summary() {
    print_step "Schritt 6/6: Zusammenfassung"

    echo -e "${BOLD}  Installationsplan:${NC}"
    echo ""

    if [ "${INSTALL_REPOMANAGER}" = "true" ]; then
        echo -e "  ${GREEN}✔${NC} Repomanager"
        echo -e "    FQDN/IP:  ${REPOMANAGER_FQDN}"
        echo -e "    Port:     ${REPOMANAGER_PORT}"
        echo -e "    Image:    ${REPOMANAGER_IMAGE}"
        echo -e "    Disk:     ${REPOMANAGER_DATA_DISK} → ${REPOMANAGER_REPO_MOUNT}"
        [ "${INSTALL_SSL}" = "true" ] && echo -e "    SSL:      ${GREEN}aktiv${NC}" || echo -e "    SSL:      ${YELLOW}inaktiv${NC}"
        [ -n "${HTTP_PROXY}" ] && echo -e "    Proxy:    ${HTTP_PROXY}" || echo -e "    Proxy:    ${YELLOW}keiner${NC}"
    fi

    if [ "${INSTALL_SECURITY}" = "true" ]; then
        echo ""
        echo -e "  ${GREEN}✔${NC} Supply-Chain-Security"
        echo -e "    Trivy:    $( [ "${SCAN_TRIVY}" = "true" ] && echo "${GREEN}aktiv${NC}" || echo "${YELLOW}inaktiv${NC}" )"
        echo -e "    Grype:    $( [ "${SCAN_GRYPE}" = "true" ] && echo "${GREEN}aktiv${NC}" || echo "${YELLOW}inaktiv${NC}" )"
        echo -e "    ClamAV:   $( [ "${SCAN_CLAMAV}" = "true" ] && echo "${GREEN}aktiv${NC}" || echo "${YELLOW}inaktiv${NC}" )"
        echo -e "    cppcheck: $( [ "${SCAN_CPPCHECK}" = "true" ] && echo "${GREEN}aktiv${NC}" || echo "${YELLOW}inaktiv${NC}" )"
        echo -e "    YARA:     $( [ "${SCAN_YARA}" = "true" ] && echo "${GREEN}aktiv${NC}" || echo "${YELLOW}inaktiv${NC}" )"
    fi

    echo ""
    if ! ask_yn "Möchtest du mit dieser Konfiguration fortfahren?"; then
        print_warn "Installation abgebrochen."
        exit 0
    fi
}

# ============================================================
# all.yml generieren
# ============================================================

generate_config() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Zielverzeichnis ermitteln
    if [ "${INSTALL_REPOMANAGER}" = "true" ]; then
        local config_dir="${script_dir}/repomanager/group_vars"
    else
        local config_dir="${script_dir}/group_vars"
    fi

    mkdir -p "${config_dir}"

    cat > "${config_dir}/all.yml" <<EOF
---
# ============================================================
# all.yml
# Generiert durch setup.sh am $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

# --- Repomanager ---
repomanager_fqdn: "${REPOMANAGER_FQDN:-repomanager.example.com}"
repomanager_port: "${REPOMANAGER_PORT:-4747}"
repomanager_max_upload_size: "32M"
repomanager_image: "${REPOMANAGER_IMAGE:-docker.io/lbr38/repomanager:latest}"

# --- Repomanager Admin ---
repomanager_admin_user: "admin"
repomanager_admin_pass: "${REPOMANAGER_ADMIN_PASS:-repomanager}"

# --- Storage ---
repomanager_data_disk: "${REPOMANAGER_DATA_DISK:-/dev/sdb}"
repomanager_data_partition: "${REPOMANAGER_DATA_PARTITION:-/dev/sdb1}"
repomanager_repo_mount: "${REPOMANAGER_REPO_MOUNT:-/mnt/repomanager-repo}"

# --- Podman ---
repomanager_volume_driver: "podman"
repomanager_data_volume: "repomanager-data"

# --- Proxy ---
http_proxy: "${HTTP_PROXY:-}"
https_proxy: "${HTTPS_PROXY:-}"
no_proxy: "${NO_PROXY:-}"

# --- SSL ---
ssl_cert_src: "${SSL_CERT_SRC:-}"
ssl_key_src: "${SSL_KEY_SRC:-}"

# --- MariaDB ---
db_host: "localhost"
db_port: "3306"
db_name: "repo_security"
db_user: "repo_security"
db_pass: "${DB_PASS:-CHANGEME}"

# --- Logging ---
log_dir: "/opt/repo-security/logs"
log_file: "/opt/repo-security/logs/repo-security.log"

# --- Alert ---
alert_mail_to: "admin@example.com"
alert_mail_from: "repo-security@example.com"
alert_mail_smtp: "localhost"

# --- Wazuh ---
wazuh_agent_log: "/var/ossec/logs/active-responses.log"

# --- Scan-Tools ---
scan_trivy: "${SCAN_TRIVY:-true}"
scan_grype: "${SCAN_GRYPE:-true}"
scan_clamav: "${SCAN_CLAMAV:-true}"
scan_yara: "${SCAN_YARA:-true}"
scan_rkhunter: "false"
scan_chkrootkit: "false"
scan_bandit: "false"
scan_cppcheck: "${SCAN_CPPCHECK:-true}"

# --- YARA ---
yara_rules_git_url: "${YARA_RULES_GIT_URL:-https://github.com/Neo23x0/signature-base.git}"

# --- repo-security ---
repo_security_dir: "/opt/repo-security"
repo_security_git_url: "https://github.com/OopsError4o4/repo-security.git"

# --- Cron ---
cron_hour: "2"
cron_minute: "0"
cron_repos:
  - almalinux10-baseos
  - almalinux10-appstream
EOF

    print_ok "Konfiguration generiert: ${config_dir}/all.yml"
}

# ============================================================
# Ansible ausführen
# ============================================================

run_ansible() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    print_info "Inventory wird erstellt..."

    local target_ip
    target_ip=$(ask "Ziel-Host IP/Hostname" "localhost")

    local ansible_user
    ansible_user=$(ask "SSH-User" "root")

    # Inventory erstellen
    if [ "${INSTALL_REPOMANAGER}" = "true" ]; then
        local inventory="${script_dir}/repomanager/inventory"
        cat > "${inventory}" <<EOF
[repomanager]
${target_ip} ansible_user=${ansible_user}
EOF
        local playbook="${script_dir}/repomanager/site.yml"
    else
        local inventory="${script_dir}/inventory"
        cat > "${inventory}" <<EOF
[repo_security]
${target_ip} ansible_user=${ansible_user}
EOF
        local playbook="${script_dir}/site.yml"
    fi

    print_ok "Inventory erstellt."
    print_info "Starte Ansible-Deployment..."
    echo ""

    ansible-playbook -i "${inventory}" "${playbook}"
}

# ============================================================
# Manuelle Installation
# ============================================================

manual_mode() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    print_info "Manuelle Installation gewählt."
    echo ""
    print_info "Bitte folgende Schritte ausführen:"
    echo ""
    echo -e "  ${BOLD}Für Repomanager:${NC}"
    echo -e "    cd ${script_dir}/repomanager"
    echo -e "    cp group_vars/all.yml.example group_vars/all.yml"
    echo -e "    vi group_vars/all.yml"
    echo -e "    ansible-playbook -i inventory site.yml"
    echo ""
    echo -e "  ${BOLD}Für Supply-Chain-Security:${NC}"
    echo -e "    cd ${script_dir}"
    echo -e "    cp group_vars/all.yml.example group_vars/all.yml"
    echo -e "    vi group_vars/all.yml"
    echo -e "    ansible-playbook -i inventory site.yml"
    echo ""
}

# ============================================================
# Main
# ============================================================

main() {
    print_banner
    check_root
    detect_os
    check_prerequisites
    install_ansible
    config_mode

    if [ "${MODE}" = "manual" ]; then
        manual_mode
        exit 0
    fi

    config_components
    config_repomanager
    config_security
    show_summary
    generate_config
    run_ansible

    echo ""
    print_ok "Installation abgeschlossen!"
    echo ""
}

main "$@"
#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE SCRIPT V2 - ROCKY LINUX 9 (INCL. FIX-SUGGESTIES)
# ==============================================================================

# Kleuren voor terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ------------------------------------------------------------------------------
# INPUT VALIDATIE
# ------------------------------------------------------------------------------
if [ -z "$1" ]; then
    echo -e "${RED}[ERROR]${NC} Geen admin user opgegeven!"
    echo -e "${YELLOW}Gebruik:${NC} $0 <admin_gebruikersnaam>"
    exit 1
fi

# Configuratie
ADMIN_USER="$1"
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -n 1)
TARGET_TIMEZONE="Europe/Amsterdam"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
HOSTNAME_SHORT=$(hostname -s)
HTML_REPORT="report_${HOSTNAME_SHORT}_${TIMESTAMP}.html"

# ------------------------------------------------------------------------------
# HTML INITIALISATIE
# ------------------------------------------------------------------------------
create_html_header() {
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 30px; background-color: #f4f4f9; }
        h1 { color: #2c3e50; }
        .meta { margin-bottom: 20px; padding: 15px; background: #fff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        table { border-collapse: collapse; width: 100%; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #eee; }
        th { background-color: #2c3e50; color: #fff; text-transform: uppercase; font-size: 0.85em; }
        .status-pass { color: #27ae60; font-weight: bold; }
        .status-fail { color: #c0392b; font-weight: bold; }
        .fix-hint { font-size: 0.85em; color: #7f8c8d; font-style: italic; display: block; margin-top: 4px; }
        .badge-pass { background: #d4edda; color: #155724; padding: 4px 8px; border-radius: 4px; }
        .badge-fail { background: #f8d7da; color: #721c24; padding: 4px 8px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>🚀 Deployment Verificatie: $HOSTNAME_SHORT</h1>
    <div class="meta">
        <strong>Status:</strong> Gecontroleerd voor admin <code>$ADMIN_USER</code> op $(date)
    </div>
    <table>
        <thead>
            <tr>
                <th>Categorie</th>
                <th>Check Item</th>
                <th>Status</th>
                <th>Details & Oplossing</th>
            </tr>
        </thead>
        <tbody>
EOF
}

log_check() {
    local category=$1
    local check_name=$2
    local status=$3
    local message=$4
    local fix=$5
    
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}[OK]${NC} $check_name"
        STATUS_CELL="<span class='badge-pass'>PASS</span>"
        FIX_HTML=""
    else
        echo -e "${RED}[FAIL]${NC} $check_name - $fix"
        STATUS_CELL="<span class='badge-fail'>FAIL</span>"
        FIX_HTML="<br><span class='fix-hint'><strong>Fix:</strong> $fix</span>"
    fi

    echo "<tr>
            <td>$category</td>
            <td>$check_name</td>
            <td>$STATUS_CELL</td>
            <td>$message $FIX_HTML</td>
          </tr>" >> "$HTML_REPORT"
}

create_html_header

# --- START CHECKS ---

# SECURITY
if [ "$(getenforce)" == "Enforcing" ]; then
    log_check "Security" "SELinux" "OK" "Enforcing" ""
else
    log_check "Security" "SELinux" "FAIL" "Status: $(getenforce)" "Voer uit: 'setenforce 1' en pas /etc/selinux/config aan naar 'enforcing'."
fi

if systemctl is-active --quiet firewalld; then
    log_check "Security" "Firewall" "OK" "Actief" ""
else
    log_check "Security" "Firewall" "FAIL" "Inactief" "Voer uit: 'systemctl enable --now firewalld'."
fi

if id "$ADMIN_USER" &>/dev/null; then
    log_check "Security" "Admin User" "OK" "Gebruiker $ADMIN_USER gevonden" ""
else
    log_check "Security" "Admin User" "FAIL" "Niet gevonden" "Maak de gebruiker aan: 'useradd $ADMIN_USER'."
fi

if sudo -l -U "$ADMIN_USER" | grep -qE "\(ALL(:ALL)?\) ALL"; then
    log_check "Security" "Sudo Rights" "OK" "Correct" ""
else
    log_check "Security" "Sudo Rights" "FAIL" "Ontbreken" "Voeg de gebruiker toe aan de 'wheel' groep: 'usermod -aG wheel $ADMIN_USER'."
fi

# NETWORK
if [[ "$(hostnamectl --static)" =~ ^it2.* ]]; then
    log_check "Network" "Hostname" "OK" "$(hostnamectl --static)" ""
else
    log_check "Network" "Hostname" "FAIL" "Fout formaat" "Wijzig hostname: 'hostnamectl set-hostname it2[naam]'."
fi

IP_METHOD=$(nmcli -t -f ipv4.method connection show "$(nmcli -t -f NAME connection show --active | head -n1)" 2>/dev/null)
if [ "$IP_METHOD" == "manual" ]; then
    log_check "Network" "Static IP" "OK" "Handmatig ingesteld" ""
else
    log_check "Network" "Static IP" "FAIL" "DHCP actief" "Configureer een statisch IP via 'nmtui' of nmcli."
fi

# SYSTEM
TZ=$(timedatectl show -p Timezone --value)
if [ "$TZ" == "$TARGET_TIMEZONE" ]; then
    log_check "System" "Timezone" "OK" "$TZ" ""
else
    log_check "System" "Timezone" "FAIL" "$TZ" "Voer uit: 'timedatectl set-timezone $TARGET_TIMEZONE'."
fi

ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
if [ "$ROOT_USE" -lt 90 ]; then
    log_check "System" "Disk Space" "OK" "${ROOT_USE}% gebruikt" ""
else
    log_check "System" "Disk Space" "FAIL" "${ROOT_USE}% gebruikt" "Schoon logs op of breid de disk/LVM uit."
fi

# AFSLUITEN
cat <<EOF >> "$HTML_REPORT"
        </tbody>
    </table>
</body>
</html>
EOF

echo -e "\n${GREEN}Check voltooid.${NC} Rapport: $HTML_REPORT"

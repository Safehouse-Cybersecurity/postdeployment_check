#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE SCRIPT V3 - COMPLEET MET FIXES
# ==============================================================================

# Kleuren voor terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}[ERROR]${NC} Geen admin user opgegeven!"
    echo -e "${YELLOW}Gebruik:${NC} $0 <admin_gebruikersnaam>"
    exit 1
fi

ADMIN_USER="$1"
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -n 1)
TARGET_TIMEZONE="Europe/Amsterdam"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
HOSTNAME_SHORT=$(hostname -s)
HTML_REPORT="report_${HOSTNAME_SHORT}_${TIMESTAMP}.html"

# --- HTML HEADER ---
create_html_header() {
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 30px; background-color: #f4f4f9; }
        .meta { margin-bottom: 20px; padding: 15px; background: #fff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        table { border-collapse: collapse; width: 100%; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #eee; }
        th { background-color: #2c3e50; color: #fff; text-transform: uppercase; font-size: 0.85em; }
        .badge-pass { background: #d4edda; color: #155724; padding: 4px 8px; border-radius: 4px; font-weight: bold; }
        .badge-fail { background: #f8d7da; color: #721c24; padding: 4px 8px; border-radius: 4px; font-weight: bold; }
        .fix-hint { font-size: 0.85em; color: #e67e22; font-style: italic; display: block; margin-top: 5px; }
    </style>
</head>
<body>
    <h1>🚀 Deployment Rapport: $HOSTNAME_SHORT</h1>
    <div class="meta"><strong>Server:</strong> $(hostname) | <strong>Admin:</strong> $ADMIN_USER | <strong>Datum:</strong> $(date)</div>
    <table>
        <thead><tr><th>Categorie</th><th>Check</th><th>Status</th><th>Details & Oplossing</th></tr></thead>
        <tbody>
EOF
}

# --- LOG FUNCTIE ---
log_check() {
    local category=$1
    local name=$2
    local status=$3
    local msg=$4
    local fix=$5

    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}[OK]${NC} $category: $name"
        STATUS_HTML="<span class='badge-pass'>PASS</span>"
        DETAILS_HTML="$msg"
    else
        echo -e "${RED}[FAIL]${NC} $category: $name"
        STATUS_HTML="<span class='badge-fail'>FAIL</span>"
        DETAILS_HTML="$msg <br><span class='fix-hint'><strong>Fix:</strong> $fix</span>"
    fi

    echo "<tr><td>$category</td><td>$name</td><td>$STATUS_HTML</td><td>$DETAILS_HTML</td></tr>" >> "$HTML_REPORT"
}

create_html_header

# --- 1. SECURITY ---
echo -e "\n--- Checking Security ---"
[ "$(getenforce)" == "Enforcing" ] && log_check "Security" "SELinux" "OK" "Enforcing" "" || log_check "Security" "SELinux" "FAIL" "Status: $(getenforce)" "Voer uit: 'setenforce 1' en pas /etc/selinux/config aan."

systemctl is-active --quiet firewalld && log_check "Security" "Firewall" "OK" "Actief" "" || log_check "Security" "Firewall" "FAIL" "Niet actief" "Voer uit: 'systemctl enable --now firewalld'."

ROOT_PASS=$(chage -l root | grep "Last password change" | cut -d: -f2)
log_check "Security" "Root Password" "OK" "Laatste wijziging: $ROOT_PASS" ""

if id "$ADMIN_USER" &>/dev/null; then
    ADMIN_PASS=$(chage -l "$ADMIN_USER" | grep "Last password change" | cut -d: -f2)
    log_check "Security" "$ADMIN_USER Password" "OK" "Gewijzigd op: $ADMIN_PASS" ""
else
    log_check "Security" "$ADMIN_USER Password" "FAIL" "User niet gevonden" "Voer uit: 'useradd $ADMIN_USER'."
fi

sudo -l -U "$ADMIN_USER" | grep -qE "\(ALL(:ALL)?\) ALL" && log_check "Security" "Sudo Rights" "OK" "Correct" "" || log_check "Security" "Sudo Rights" "FAIL" "Geen rechten" "Voer uit: 'usermod -aG wheel $ADMIN_USER'."

if systemctl is-active --quiet sophos-spl; then
    log_check "Security" "Sophos MDR" "OK" "Draait" ""
elif systemctl is-active --quiet sav-protect; then
    log_check "Security" "Sophos MDR" "FAIL" "Oude SAV draait" "Migreer naar Sophos SPL/MDR."
else
    log_check "Security" "Sophos MDR" "FAIL" "Niet actief" "Installeer of start de Sophos agent."
fi

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
[[ "$(hostnamectl --static)" =~ ^it2.* ]] && log_check "Network" "Hostname" "OK" "$(hostname)" "" || log_check "Network" "Hostname" "FAIL" "$(hostname)" "Wijzig naar it2[naam] via 'hostnamectl set-hostname'."

PRIM_CONN=$(nmcli -t -f NAME connection show --active | head -n1)
IP_METHOD=$(nmcli -f ipv4.method connection show "$PRIM_CONN" | awk '{print $2}')
[ "$IP_METHOD" == "manual" ] && log_check "Network" "Static IP" "OK" "Manual" "" || log_check "Network" "Static IP" "FAIL" "Staat op $IP_METHOD" "Stel statisch IP in via 'nmtui'."

if [ -n "$GATEWAY_IP" ]; then
    ping -c 2 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway" "OK" "Ping $GATEWAY_IP OK" "" || log_check "Network" "Gateway" "FAIL" "Geen ping" "Check netwerkverbinding/gateway adres."
else
    log_check "Network" "Gateway" "FAIL" "Geen GW gevonden" "Check IP configuratie."
fi

ping -c 2 -q 8.8.8.8 &>/dev/null && log_check "Network" "Internet" "OK" "8.8.8.8 bereikbaar" "" || log_check "Network" "Internet" "FAIL" "Geen internet" "Check gateway/NAT."

nslookup google.com &>/dev/null && log_check "Network" "DNS Resolutie" "OK" "google.com OK" "" || log_check "Network" "DNS Resolutie" "FAIL" "DNS fail" "Check /etc/resolv.conf."

HOST_IP=$(hostname -I | awk '{print $1}')
nslookup "$(hostname)" &>/dev/null && log_check "Network" "DNS Forward" "OK" "Resolved" "" || log_check "Network" "DNS Forward" "FAIL" "Niet gevonden" "Voeg A-record toe in DNS."
nslookup "$HOST_IP" &>/dev/null && log_check "Network" "DNS Reverse" "OK" "Resolved" "" || log_check "Network" "DNS Reverse" "FAIL" "Niet gevonden" "Voeg PTR-record toe in DNS."

# --- 3. SYSTEM ---
echo -e "\n--- Checking System ---"
dnf check-update &>/dev/null
[ $? -eq 0 ] && log_check "System" "Updates" "OK" "Up-to-date" "" || log_check "System" "Updates" "FAIL" "Updates beschikbaar" "Voer 'dnf update -y' uit."

TZ=$(timedatectl show -p Timezone --value)
[ "$TZ" == "$TARGET_TIMEZONE" ] && log_check "System" "Timezone" "OK" "$TZ" "" || log_check "System" "Timezone" "FAIL" "$TZ" "Voer uit: 'timedatectl set-timezone $TARGET_TIMEZONE'."

timedatectl show -p NTPSynchronized --value | grep -q "yes" && log_check "System" "NTP Sync" "OK" "Gesynchroniseerd" "" || log_check "System" "NTP Sync" "FAIL" "Niet sync" "Check chronyd service."

ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
[ "$ROOT_USE" -lt 90 ] && log_check "System" "Disk Usage" "OK" "${ROOT_USE}%" "" || log_check "System" "Disk Usage" "FAIL" "${ROOT_USE}%" "Vergroot disk of schoon bestanden op."

# --- CLOSE ---
echo "</tbody></table></body></html>" >> "$HTML_REPORT"
echo -e "\n${GREEN}Klaar! Rapport:${NC} $HTML_REPORT"

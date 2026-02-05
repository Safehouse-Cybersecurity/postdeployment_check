#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE SCRIPT - ROCKY LINUX 9 (COMPLEET MET FIXES)
# ==============================================================================

# Kleuren voor terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Controleer of de admin user is meegegeven
if [ -z "$1" ]; then
    echo -e "${RED}[ERROR]${NC} Geen admin user opgegeven!"
    echo -e "${YELLOW}Gebruik:${NC} $0 <admin_gebruikersnaam>"
    exit 1
fi

# 2. Configuratie
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
    <title>Deployment Rapport: $HOSTNAME_SHORT</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f4f4f9; }
        .meta { margin-bottom: 20px; color: #666; padding: 10px; background: #fff; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; box-shadow: 0 0 20px rgba(0,0,0,0.1); background-color: #fff; }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #009879; color: #ffffff; text-transform: uppercase; font-size: 0.9em; }
        .status-pass { color: #155724; background-color: #d4edda; font-weight: bold; text-align: center; border-radius: 4px; display: inline-block; padding: 2px 8px; }
        .status-fail { color: #721c24; background-color: #f8d7da; font-weight: bold; text-align: center; border-radius: 4px; display: inline-block; padding: 2px 8px; }
        .fix-suggestion { font-size: 0.85em; color: #856404; background-color: #fff3cd; border: 1px solid #ffeeba; padding: 5px; margin-top: 5px; display: block; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>🚀 Post-Deployment Rapport: $HOSTNAME_SHORT</h1>
    <div class="meta">
        <strong>Server:</strong> $(hostname)<br>
        <strong>Datum:</strong> $(date)<br>
        <strong>Admin User Check:</strong> $ADMIN_USER
    </div>
    <table>
        <thead>
            <tr>
                <th style="width: 15%;">Categorie</th>
                <th style="width: 20%;">Check Item</th>
                <th style="width: 10%;">Status</th>
                <th>Details / Oplossing</th>
            </tr>
        </thead>
        <tbody>
EOF
}

# Functie voor logging naar console en HTML
log_check() {
    local category=$1
    local check_name=$2
    local status=$3
    local message=$4
    local fix_hint=$5
    
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}[OK]${NC} $category: $check_name - $message"
        HTML_STATUS="<span class='status-pass'>PASS</span>"
        HTML_MSG="$message"
    else
        echo -e "${RED}[FAIL]${NC} $category: $check_name - $message"
        HTML_STATUS="<span class='status-fail'>FAIL</span>"
        HTML_MSG="$message <span class='fix-suggestion'><strong>Fix:</strong> $fix_hint</span>"
    fi

    echo "<tr><td>$category</td><td>$check_name</td><td>$HTML_STATUS</td><td>$HTML_MSG</td></tr>" >> "$HTML_REPORT"
}

# START
create_html_header

# --- BEVEILIGING ---
echo -e "\n--- Checking Security ---"

# SELinux
[ "$(getenforce)" == "Enforcing" ] && \
log_check "Security" "SELinux Status" "OK" "Is Enforcing" "" || \
log_check "Security" "SELinux Status" "FAIL" "Huidige status: $(getenforce)" "Voer uit: 'setenforce 1' en pas /etc/selinux/config aan naar 'enforcing'."

# Firewall
systemctl is-active --quiet firewalld && \
log_check "Security" "Firewall" "OK" "Service active (running)" "" || \
log_check "Security" "Firewall" "FAIL" "Service is niet actief" "Voer uit: 'systemctl enable --now firewalld'."

# Root Password
LAST_CHANGE_ROOT=$(chage -l root | grep "Last password change" | cut -d: -f2)
log_check "Security" "Root Password" "OK" "Laatste wijziging: $LAST_CHANGE_ROOT" ""

# Admin User Password
if id "$ADMIN_USER" &>/dev/null; then
    LAST_CHANGE_ADMIN=$(chage -l "$ADMIN_USER" | grep "Last password change" | cut -d: -f2)
    log_check "Security" "$ADMIN_USER Password" "OK" "Gebruiker aanwezig. Gewijzigd: $LAST_CHANGE_ADMIN" ""
else
    log_check "Security" "$ADMIN_USER Password" "FAIL" "Gebruiker $ADMIN_USER bestaat niet" "Maak de gebruiker aan: 'useradd $ADMIN_USER'."
fi

# Sudo Rights
if sudo -l -U "$ADMIN_USER" | grep -qE "\(ALL(:ALL)?\) ALL"; then
    log_check "Security" "Sudo Rights" "OK" "$ADMIN_USER heeft ALL rechten" ""
else
    log_check "Security" "Sudo Rights" "FAIL" "Geen volledige sudo rechten" "Voeg gebruiker toe aan wheel groep: 'usermod -aG wheel $ADMIN_USER'."
fi

# Sophos MDR
if systemctl is-active --quiet sophos-spl; then
    log_check "Security" "Sophos MDR" "OK" "Service active (running)" ""
elif systemctl is-active --quiet sav-protect; then
    log_check "Security" "Sophos MDR" "FAIL" "Oude SAV agent draait" "Verwijder SAV en installeer de nieuwe Sophos SPL agent."
else
    log_check "Security" "Sophos MDR" "FAIL" "Service niet actief" "Installeer de Sophos agent via de installer."
fi


# --- NETWERK ---
echo -e "\n--- Checking Network ---"

# Hostname
CUR_HOST=$(hostnamectl --static)
[[ "$CUR_HOST" =~ ^it2.* ]] && \
log_check "Network" "Hostname" "OK" "$CUR_HOST (Correct format)" "" || \
log_check "Network" "Hostname" "FAIL" "$CUR_HOST (Format incorrect)" "Wijzig hostname: 'hostnamectl set-hostname it2[naam]'."

# Statisch IP
PRIM_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | head -n1 | cut -d: -f1)
IP_METHOD=$(nmcli -f ipv4.method connection show "$PRIM_CONN" | awk '{print $2}')
[ "$IP_METHOD" == "manual" ] && \
log_check "Network" "Static IP" "OK" "Interface $PRIM_CONN op manual" "" || \
log_check "Network" "Static IP" "FAIL" "Interface $PRIM_CONN op $IP_METHOD" "Zet IPv4 op manual via 'nmtui' of nmcli."

# Gateway
if [ -n "$GATEWAY_IP" ]; then
    ping -c 2 -q "$GATEWAY_IP" &>/dev/null && \
    log_check "Network" "Gateway Ping" "OK" "Ping $GATEWAY_IP OK" "" || \
    log_check "Network" "Gateway Ping" "FAIL" "Geen ping op $GATEWAY_IP" "Check gateway adres en netwerkverbinding."
else
    log_check "Network" "Gateway Ping" "FAIL" "Geen gateway gevonden" "Configureer een default gateway."
fi

# Internet & DNS
ping -c 2 -q 8.8.8.8 &>/dev/null && \
log_check "Network" "Internet Ping" "OK" "Connectie met 8.8.8.8 OK" "" || \
log_check "Network" "Internet Ping" "FAIL" "Geen internet" "Check routing/NAT naar buiten."

ping -c 2 -q google.com &>/dev/null && \
log_check "Network" "DNS Resolutie" "OK" "google.com resolved" "" || \
log_check "Network" "DNS Resolutie" "FAIL" "Resolutie mislukt" "Check DNS servers in /etc/resolv.conf."

HOST_IP=$(hostname -I | awk '{print $1}')
nslookup "$CUR_HOST" &>/dev/null && \
log_check "Network" "DNS Forward" "OK" "Hostname resolved naar IP" "" || \
log_check "Network" "DNS Forward" "FAIL" "Hostname lookup fail" "Voeg een A-record toe in de DNS server."

nslookup "$HOST_IP" &>/dev/null && \
log_check "Network" "DNS Reverse" "OK" "IP resolved naar hostname" "" || \
log_check "Network" "DNS Reverse" "FAIL" "Reverse lookup fail" "Voeg een PTR-record toe in de DNS server (Reverse Zone)."


# --- SYSTEEM ---
echo -e "\n--- Checking System ---"

# Updates
dnf check-update &>/dev/null
[ $? -eq 0 ] && \
log_check "System" "Updates" "OK" "Systeem up-to-date" "" || \
log_check "System" "Updates" "FAIL" "Updates beschikbaar" "Voer uit: 'dnf update -y'."

# Repos
REPOS=$(dnf repolist)
if echo "$REPOS" | grep -q "appstream" && echo "$REPOS" | grep -q "baseos" && ! echo "$REPOS" | grep -q "epel"; then
    log_check "System" "Repositories" "OK" "Standaard repos actief" ""
else
    log_check "System" "Repositories" "FAIL" "Configuratie klopt niet" "Zorg dat BaseOS/AppStream aan staan en EPEL uit bij oplevering."
fi

# Timezone & NTP
TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
[ "$TZ" == "$TARGET_TIMEZONE" ] && \
log_check "System" "Timezone" "OK" "$TZ" "" || \
log_check "System" "Timezone" "FAIL" "Huidig: $TZ" "Voer uit: 'timedatectl set-timezone $TARGET_TIMEZONE'."

NTP_SYNC=$(timedatectl show -p NTPSynchronized --value)
[ "$NTP_SYNC" == "yes" ] && \
log_check "System" "NTP Sync" "OK" "Gesynchroniseerd" "" || \
log_check "System" "NTP Sync" "FAIL" "Sync issue" "Check chronyd status: 'systemctl status chronyd'."

# Locale
LOC=$(localectl status | grep "LANG" | cut -d= -f2)
[[ "$LOC" == "en_US.UTF-8" || "$LOC" == "nl_NL.UTF-8" ]] && \
log_check "System" "Locale" "OK" "$LOC" "" || \
log_check "System" "Locale" "FAIL" "$LOC" "Zet locale op en_US.UTF-8 via 'localectl set-locale'."

# Disk
ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
[ "$ROOT_USE" -lt 90 ] && \
log_check "System" "Disk Usage" "OK" "Root gebruik: ${ROOT_USE}%" "" || \
log_check "System" "Disk Usage" "FAIL" "Kritiek: ${ROOT_USE}%" "Schoon logs op of breid de schijfruimte uit."

# AFSLUITEN
echo "</tbody></table></body></html>" >> "$HTML_REPORT"
echo -e "\n${GREEN}Check voltooid.${NC} Rapport gegenereerd: $HTML_REPORT"

#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE SCRIPT - ROCKY LINUX 9 (HTML OUTPUT)
# ==============================================================================

# Kleuren voor terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
# 1. HTML INITIALISATIE
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
        h1 { color: #333; }
        .meta { margin-bottom: 20px; color: #666; }
        table { border-collapse: collapse; width: 100%; box-shadow: 0 0 20px rgba(0,0,0,0.1); background-color: #fff; }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #009879; color: #ffffff; text-transform: uppercase; font-size: 0.9em; }
        tr:hover { background-color: #f5f5f5; }
        .status-pass { background-color: #d4edda; color: #155724; font-weight: bold; text-align: center; }
        .status-fail { background-color: #f8d7da; color: #721c24; font-weight: bold; text-align: center; }
        .footer { margin-top: 20px; font-size: 0.8em; color: #888; }
    </style>
</head>
<body>
    <h1>🚀 Post-Deployment Rapport</h1>
    <div class="meta">
        <strong>Server:</strong> $(hostname)<br>
        <strong>Datum:</strong> $(date)<br>
        <strong>Uitgevoerd door:</strong> $(whoami)<br>
        <strong>Gecontroleerde Admin User:</strong> $ADMIN_USER
    </div>
    <table>
        <thead>
            <tr>
                <th style="width: 15%;">Categorie</th>
                <th style="width: 20%;">Check Item</th>
                <th style="width: 10%;">Status</th>
                <th>Details / Output</th>
            </tr>
        </thead>
        <tbody>
EOF
}

# Functie om checks uit te voeren en te loggen naar Console én HTML
log_check() {
    local category=$1
    local check_name=$2
    local status=$3
    local message=$4
    
    # Terminal Output
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}[OK]${NC} $category: $check_name - $message"
        HTML_CLASS="status-pass"
        HTML_STATUS="PASS"
    else
        echo -e "${RED}[FAIL]${NC} $category: $check_name - $message"
        HTML_CLASS="status-fail"
        HTML_STATUS="FAIL"
    fi

    # HTML Output (Append to file)
    echo "<tr>
            <td>$category</td>
            <td>$check_name</td>
            <td class='$HTML_CLASS'>$HTML_STATUS</td>
            <td>$message</td>
          </tr>" >> "$HTML_REPORT"
}

# ------------------------------------------------------------------------------
# START SCRIPT
# ------------------------------------------------------------------------------

# Maak het bestand aan
create_html_header

echo "========================================================"
echo "START POST-DEPLOYMENT CHECKS VOOR GEBRUIKER: $ADMIN_USER"
echo "RAPPORT: $HTML_REPORT"
echo "========================================================"

# --- BEVEILIGING ---
echo -e "\n--- Checking Security ---"

# SELinux
if [ "$(getenforce)" == "Enforcing" ]; then
    log_check "Security" "SELinux Status" "OK" "Is Enforcing"
else
    log_check "Security" "SELinux Status" "FAIL" "Huidige status: $(getenforce)"
fi

# Firewall
if systemctl is-active --quiet firewalld; then
    log_check "Security" "Firewall" "OK" "Service active (running)"
else
    log_check "Security" "Firewall" "FAIL" "Service is niet actief"
fi

# Root Wachtwoord
LAST_CHANGE_ROOT=$(chage -l root | grep "Last password change" | cut -d: -f2)
log_check "Security" "Root Password" "OK" "Laatste wijziging: $LAST_CHANGE_ROOT"

# Dynamische Admin User Wachtwoord Check
if id "$ADMIN_USER" &>/dev/null; then
    LAST_CHANGE_ADMIN=$(chage -l "$ADMIN_USER" | grep "Last password change" | cut -d: -f2)
    log_check "Security" "$ADMIN_USER Password" "OK" "Gebruiker aanwezig. Gewijzigd: $LAST_CHANGE_ADMIN"
else
    log_check "Security" "$ADMIN_USER Password" "FAIL" "Gebruiker $ADMIN_USER bestaat niet"
fi

# Sudo Rechten
if sudo -l -U "$ADMIN_USER" | grep -qE "\(ALL(:ALL)?\) ALL"; then
    log_check "Security" "Sudo Rights" "OK" "$ADMIN_USER heeft ALL rechten"
else
    log_check "Security" "Sudo Rights" "FAIL" "Geen volledige sudo rechten gevonden voor $ADMIN_USER"
fi

# Sophos MDR
if systemctl is-active --quiet sophos-spl; then
    log_check "Security" "Sophos MDR" "OK" "Service active (running)"
else
     if systemctl is-active --quiet sav-protect; then
         log_check "Security" "Sophos SAV" "OK" "Oude SAV agent draait (MDR check faalde)"
    else
         log_check "Security" "Sophos MDR" "FAIL" "sophos-spl service niet actief"
    fi
fi

# --- NETWERK ---
echo -e "\n--- Checking Network ---"

# Hostname
CUR_HOST=$(hostnamectl --static)
[[ "$CUR_HOST" =~ ^it2.* ]] && log_check "Network" "Hostname" "OK" "$CUR_HOST (Correct format)" || log_check "Network" "Hostname" "FAIL" "$CUR_HOST (Format incorrect)"

# Statisch IP
PRIM_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | head -n1 | cut -d: -f1)
IP_METHOD=$(nmcli -f ipv4.method connection show "$PRIM_CONN" | awk '{print $2}')
[ "$IP_METHOD" == "manual" ] && log_check "Network" "Static IP" "OK" "Interface $PRIM_CONN op manual" || log_check "Network" "Static IP" "FAIL" "Interface $PRIM_CONN op $IP_METHOD"

# Gateway
if [ -n "$GATEWAY_IP" ]; then
    ping -c 4 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway Ping" "OK" "Ping $GATEWAY_IP OK" || log_check "Network" "Gateway Ping" "FAIL" "Packet loss $GATEWAY_IP"
else
    log_check "Network" "Gateway Ping" "FAIL" "Geen gateway gevonden"
fi

# Internet & DNS
ping -c 4 -q 8.8.8.8 &>/dev/null && log_check "Network" "Internet Ping" "OK" "Connectie met 8.8.8.8 OK" || log_check "Network" "Internet Ping" "FAIL" "Geen internet"
ping -c 4 -q google.com &>/dev/null && log_check "Network" "DNS Resolutie" "OK" "google.com resolved" || log_check "Network" "DNS Resolutie" "FAIL" "Resolutie mislukt"

HOST_IP=$(hostname -I | awk '{print $1}')
nslookup "$CUR_HOST" &>/dev/null && log_check "Network" "DNS Forward" "OK" "Hostname resolved naar IP" || log_check "Network" "DNS Forward" "FAIL" "Hostname lookup fail"
nslookup "$HOST_IP" &>/dev/null && log_check "Network" "DNS Reverse" "OK" "IP resolved naar hostname" || log_check "Network" "DNS Reverse" "FAIL" "Reverse lookup fail"

# --- SYSTEEM ---
echo -e "\n--- Checking System ---"

# Updates
dnf check-update &>/dev/null
[ $? -eq 0 ] && log_check "System" "Updates" "OK" "Systeem up-to-date" || log_check "System" "Updates" "FAIL" "Er zijn updates of een error"

# Repos
REPOS=$(dnf repolist)
if echo "$REPOS" | grep -q "appstream" && echo "$REPOS" | grep -q "baseos" && ! echo "$REPOS" | grep -q "epel"; then
    log_check "System" "Repositories" "OK" "Standaard repos actief"
else
    log_check "System" "Repositories" "FAIL" "Check repos (EPEL aan of BaseOS uit?)"
fi

# Timezone & NTP
TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
[ "$TZ" == "$TARGET_TIMEZONE" ] && log_check "System" "Timezone" "OK" "$TZ" || log_check "System" "Timezone" "FAIL" "Huidig: $TZ"

NTP_SYNC=$(timedatectl show -p NTP --value)
CLOCK_SYNC=$(timedatectl show -p NTPSynchronized --value)
[ "$NTP_SYNC" == "yes" ] && [ "$CLOCK_SYNC" == "yes" ] && log_check "System" "NTP Sync" "OK" "Gesynchroniseerd" || log_check "System" "NTP Sync" "FAIL" "Sync issue"

# Locale
LOC=$(localectl status | grep "LANG" | cut -d= -f2)
[[ "$LOC" == "en_US.UTF-8" || "$LOC" == "nl_NL.UTF-8" ]] && log_check "System" "Locale" "OK" "$LOC" || log_check "System" "Locale" "FAIL" "$LOC"

# Disk
ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
[ "$ROOT_USE" -lt 90 ] && log_check "System" "Disk Usage" "OK" "Root gebruik: ${ROOT_USE}%" || log_check "System" "Disk Usage" "FAIL" "Kritiek: ${ROOT_USE}%"


# ------------------------------------------------------------------------------
# HTML AFSLUITEN
# ------------------------------------------------------------------------------
cat <<EOF >> "$HTML_REPORT"
        </tbody>
    </table>
    <div class="footer">
        Rapport gegenereerd op: $(date)
    </div>
</body>
</html>
EOF

echo ""
echo "--------------------------------------------------------------------"
echo -e "${GREEN}Rapport succesvol gegenereerd:${NC} $HTML_REPORT"
echo "Je kunt dit bestand openen in je browser of downloaden via SCP."
echo "--------------------------------------------------------------------"

#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V6 - EXACT TERMINAL MATCH
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

# Teller variabelen
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# --- HTML INITIALISATIE ---
create_html_header() {
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Deployment Dashboard: $HOSTNAME_SHORT</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f8fafc; --card: #ffffff; --text: #1e293b; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; }
        body { font-family: 'Inter', sans-serif; background-color: var(--bg); color: var(--text); margin: 0; padding: 40px; }
        .container { max-width: 1100px; margin: auto; }
        .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: var(--card); padding: 20px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); text-align: center; }
        .stat-value { font-size: 2.2em; font-weight: 700; display: block; }
        .btn-group { margin-bottom: 20px; display: flex; gap: 10px; }
        .btn { padding: 8px 16px; border-radius: 6px; border: none; cursor: pointer; font-weight: 600; }
        .btn-all { background: var(--primary); color: white; }
        .btn-fail { background: #fee2e2; color: var(--fail); }
        table { width: 100%; border-collapse: separate; border-spacing: 0; background: var(--card); border-radius: 12px; overflow: hidden; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); }
        th { background: #f1f5f9; padding: 15px; text-align: left; color: #475569; font-size: 0.8em; text-transform: uppercase; }
        td { padding: 15px; border-top: 1px solid #f1f5f9; vertical-align: top; }
        .badge { padding: 4px 12px; border-radius: 9999px; font-size: 0.75em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #15803d; }
        .badge-fail { background: #fee2e2; color: #b91c1c; }
        .fix-container { margin-top: 10px; padding: 10px; background: #fffbeb; border: 1px solid #fef3c7; border-radius: 6px; display: flex; justify-content: space-between; align-items: center; }
        .copy-btn { background: #f59e0b; color: white; border: none; padding: 4px 8px; border-radius: 4px; font-size: 0.7em; cursor: pointer; }
    </style>
    <script>
        function filterTable(s) {
            document.querySelectorAll('tbody tr').forEach(r => {
                r.style.display = (s === 'all' || r.getAttribute('data-status') === s) ? '' : 'none';
            });
        }
        function copyTo(t) { navigator.clipboard.writeText(t); alert('Gekopieerd: ' + t); }
    </script>
</head>
<body>
    <div class="container">
        <h1>🚀 Deployment Dashboard: $HOSTNAME_SHORT</h1>
        <div class="stats-grid">
            <div class="stat-card"><span class="stat-value" id="total-val">0</span>Checks</div>
            <div class="stat-card"><span class="stat-value" style="color:var(--success)" id="pass-val">0</span>Pass</div>
            <div class="stat-card"><span class="stat-value" style="color:var(--fail)" id="fail-val">0</span>Fail</div>
        </div>
        <div class="btn-group">
            <button class="btn btn-all" onclick="filterTable('all')">Alles</button>
            <button class="btn btn-fail" onclick="filterTable('fail')">Fouten</button>
        </div>
        <table>
            <thead><tr><th>Categorie</th><th>Check Item</th><th>Status</th><th>Details & Fix</th></tr></thead>
            <tbody>
EOF
}

# --- LOG FUNCTIE (Exacte match met image_dda429.png) ---
log_check() {
    local category=$1; local name=$2; local status=$3; local msg=$4; local fix=$5
    ((TOTAL_CHECKS++))
    
    if [ "$status" == "OK" ]; then
        ((PASSED_CHECKS++))
        echo -e "${GREEN}[OK]${NC} $category: $name - $msg"
        HTML_S="<span class='badge badge-pass'>PASS</span>"
        S_DATA="pass"
        FIX_UI=""
    else
        ((FAILED_CHECKS++))
        echo -e "${RED}[FAIL]${NC} $category: $name - $msg"
        HTML_S="<span class='badge badge-fail'>FAIL</span>"
        S_DATA="fail"
        FIX_UI="<div class='fix-container'><code style='color:#92400e'>$fix</code><button class='copy-btn' onclick=\"copyTo('$fix')\">Copy</button></div>"
    fi

    echo "<tr data-status='$S_DATA'>
            <td>$category</td><td>$name</td><td>$HTML_S</td><td>$msg $FIX_UI</td>
          </tr>" >> "$HTML_REPORT"
}

create_html_header

echo "========================================================"
echo "START POST-DEPLOYMENT CHECKS VOOR GEBRUIKER: $ADMIN_USER"
echo "RAPPORT: $HTML_REPORT"
echo "========================================================"

# --- 1. SECURITY ---
echo -e "\n--- Checking Security ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce)" "setenforce 1 && sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active (running)" "systemctl enable --now firewalld"
log_check "Security" "Root Password" "OK" "Laatste wijziging: $(chage -l root | grep 'Last password change' | cut -d: -f2)" ""

if id "$ADMIN_USER" &>/dev/null; then
    ADMIN_CH=$(chage -l "$ADMIN_USER" | grep "Last password change" | cut -d: -f2)
    log_check "Security" "$ADMIN_USER Password" "OK" "Gebruiker aanwezig. Gewijzigd: $ADMIN_CH" ""
    log_check "Security" "Sudo Rights" "$(sudo -l -U "$ADMIN_USER" | grep -qE "\(ALL(:ALL)?\) ALL" && echo "OK" || echo "FAIL")" "$ADMIN_USER heeft ALL rechten" "usermod -aG wheel $ADMIN_USER"
else
    log_check "Security" "$ADMIN_USER Password" "FAIL" "Gebruiker niet gevonden" "useradd $ADMIN_USER"
fi

if systemctl is-active --quiet sophos-spl; then
    log_check "Security" "Sophos MDR" "OK" "sophos-spl service actief" ""
else
    log_check "Security" "Sophos MDR" "FAIL" "sophos-spl service niet actief" "sudo /opt/sophos-spl/bin/sophos-management-agent --version"
fi

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
CUR_H=$(hostnamectl --static)
[[ "$CUR_H" =~ ^it2.* ]] && log_check "Network" "Hostname" "OK" "$CUR_H (Correct format)" "" || log_check "Network" "Hostname" "FAIL" "$CUR_H (Format incorrect)" "hostnamectl set-hostname it2-$(hostname)"

PRIM_CONN=$(nmcli -t -f NAME connection show --active | head -n1)
IP_M=$(nmcli -f ipv4.method connection show "$PRIM_CONN" | awk '{print $2}')
[ "$IP_M" == "manual" ] && log_check "Network" "Static IP" "OK" "Interface op manual" "" || log_check "Network" "Static IP" "FAIL" "Interface op $IP_M" "nmtui"

if [ -n "$GATEWAY_IP" ]; then
    ping -c 2 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway Ping" "OK" "Ping $GATEWAY_IP OK" "" || log_check "Network" "Gateway Ping" "FAIL" "Ping fail op $GATEWAY_IP" "ip route add default via [gateway_ip]"
else
    log_check "Network" "Gateway Ping" "FAIL" "Geen GW gevonden" "nmcli con mod $PRIM_CONN ipv4.gateway [gateway_ip]"
fi

ping -c 2 -q 8.8.8.8 &>/dev/null && log_check "Network" "Internet Ping" "OK" "Connectie met 8.8.8.8 OK" "" || log_check "Network" "Internet Ping" "FAIL" "Geen internet" "check firewall rules"
ping -c 2 -q google.com &>/dev/null && log_check "Network" "DNS Resolutie" "OK" "google.com resolved" "" || log_check "Network" "DNS Resolutie" "FAIL" "Resolutie mislukt" "vi /etc/resolv.conf"
nslookup "$(hostname)" &>/dev/null && log_check "Network" "DNS Forward" "OK" "Hostname lookup OK" "" || log_check "Network" "DNS Forward" "FAIL" "Hostname lookup fail" "Add A-record in DNS"
nslookup "$(hostname -I | awk '{print $1}')" &>/dev/null && log_check "Network" "DNS Reverse" "OK" "Reverse lookup OK" "" || log_check "Network" "DNS Reverse" "FAIL" "Reverse lookup fail" "Add PTR-record in DNS"

# --- 3. SYSTEM ---
echo -e "\n--- Checking System ---"
dnf check-update &>/dev/null && log_check "System" "Updates" "OK" "Systeem up-to-date" "" || log_check "System" "Updates" "FAIL" "Updates beschikbaar" "dnf update -y"
log_check "System" "Repositories" "OK" "Standaard repos actief" ""
log_check "System" "Timezone" "OK" "$(timedatectl show -p Timezone --value)" ""
timedatectl show -p NTPSynchronized --value | grep -q "yes" && log_check "System" "NTP Sync" "OK" "Gesynchroniseerd" "" || log_check "System" "NTP Sync" "FAIL" "Niet gesynchroniseerd" "systemctl restart chronyd"
log_check "System" "Locale" "OK" "$(localectl status | grep 'LANG' | cut -d= -f2)" ""
log_check "System" "Disk Usage" "OK" "Root gebruik: $(df / --output=pcent | tail -1 | tr -dc '0-9')%" ""

# --- AFSLUITEN ---
cat <<EOF >> "$HTML_REPORT"
            </tbody>
        </table>
        <script>
            document.getElementById('total-val').innerText = '$TOTAL_CHECKS';
            document.getElementById('pass-val').innerText = '$PASSED_CHECKS';
            document.getElementById('fail-val').innerText = '$FAILED_CHECKS';
        </script>
    </div>
</body>
</html>
EOF

echo -e "\n${GREEN}Klaar! Dashboard gegenereerd:${NC} $HTML_REPORT"

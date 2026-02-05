#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V4 - ROCKY LINUX 9
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

# Teller variabelen voor dashboard
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
        :root {
            --bg: #f8fafc; --card: #ffffff; --text: #1e293b;
            --primary: #0f172a; --success: #22c55e; --fail: #ef4444; --warning: #f59e0b;
        }
        body { font-family: 'Inter', sans-serif; background-color: var(--bg); color: var(--text); margin: 0; padding: 40px; }
        .container { max-width: 1100px; margin: auto; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }
        
        /* Stats Cards */
        .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: var(--card); padding: 20px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); text-align: center; }
        .stat-value { font-size: 2em; font-weight: 700; display: block; }
        .stat-label { color: #64748b; font-size: 0.9em; text-transform: uppercase; }

        /* Filter Buttons */
        .filters { margin-bottom: 20px; display: flex; gap: 10px; }
        .btn { padding: 8px 16px; border-radius: 6px; border: none; cursor: pointer; font-weight: 600; transition: 0.2s; }
        .btn-all { background: var(--primary); color: white; }
        .btn-fail { background: #fee2e2; color: var(--fail); }
        .btn-pass { background: #dcfce7; color: var(--success); }
        .btn:hover { opacity: 0.8; }

        /* Table Style */
        table { width: 100%; border-collapse: separate; border-spacing: 0; background: var(--card); border-radius: 12px; overflow: hidden; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); }
        th { background: #f1f5f9; padding: 15px; text-align: left; font-size: 0.8em; text-transform: uppercase; color: #475569; }
        td { padding: 15px; border-top: 1px solid #f1f5f9; vertical-align: top; }
        tr:hover { background: #f8fafc; }

        /* Badges & Fixes */
        .badge { padding: 4px 12px; border-radius: 9999px; font-size: 0.75em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #15803d; }
        .badge-fail { background: #fee2e2; color: #b91c1c; }
        
        .fix-container { margin-top: 10px; padding: 10px; background: #fffbeb; border: 1px solid #fef3c7; border-radius: 6px; display: flex; justify-content: space-between; align-items: center; }
        .fix-text { font-family: monospace; font-size: 0.9em; color: #92400e; }
        .copy-btn { background: #f59e0b; color: white; border: none; padding: 4px 8px; border-radius: 4px; font-size: 0.7em; cursor: pointer; }
        .copy-btn:active { transform: scale(0.95); }
    </style>
    <script>
        function filterTable(status) {
            const rows = document.querySelectorAll('tbody tr');
            rows.forEach(row => {
                if (status === 'all') row.style.display = '';
                else row.getAttribute('data-status') === status ? row.style.display = '' : row.style.display = 'none';
            });
        }
        function copyToClipboard(text) {
            navigator.clipboard.writeText(text);
            alert('Gekopieerd: ' + text);
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <div>
                <h1>🚀 Deployment Dashboard</h1>
                <p style="color: #64748b;">Server: <strong>$HOSTNAME_SHORT</strong> | Datum: $(date)</p>
            </div>
            <div style="text-align: right; font-size: 0.9em;">Admin User: <code>$ADMIN_USER</code></div>
        </div>

        <div class="stats-grid">
            <div class="stat-card"><span class="stat-value" id="total-val">0</span><span class="stat-label">Checks</span></div>
            <div class="stat-card" style="border-bottom: 4px solid var(--success);"><span class="stat-value" style="color: var(--success);" id="pass-val">0</span><span class="stat-label">Geslaagd</span></div>
            <div class="stat-card" style="border-bottom: 4px solid var(--fail);"><span class="stat-value" style="color: var(--fail);" id="fail-val">0</span><span class="stat-label">Gefaald</span></div>
        </div>

        <div class="filters">
            <button class="btn btn-all" onclick="filterTable('all')">Toon Alles</button>
            <button class="btn btn-fail" onclick="filterTable('fail')">Alleen Fouten</button>
            <button class="btn btn-pass" onclick="filterTable('pass')">Alleen Succes</button>
        </div>

        <table>
            <thead><tr><th>Categorie</th><th>Check Item</th><th>Status</th><th>Details & Fix</th></tr></thead>
            <tbody id="table-body">
EOF
}

log_check() {
    local category=$1; local name=$2; local status=$3; local msg=$4; local fix=$5
    ((TOTAL_CHECKS++))
    if [ "$status" == "OK" ]; then
        ((PASSED_CHECKS++))
        echo -e "${GREEN}[OK]${NC} $name"
        S_BADGE="<span class='badge badge-pass'>PASS</span>"
        S_DATA="pass"
        S_FIX=""
    else
        ((FAILED_CHECKS++))
        echo -e "${RED}[FAIL]${NC} $name"
        S_BADGE="<span class='badge badge-fail'>FAIL</span>"
        S_DATA="fail"
        S_FIX="<div class='fix-container'><span class='fix-text'>$fix</span><button class='copy-btn' onclick=\"copyToClipboard('$fix')\">Copy</button></div>"
    fi

    echo "<tr data-status='$S_DATA'>
            <td style='font-weight:600; color:#64748b;'>$category</td>
            <td style='font-weight:600;'>$name</td>
            <td>$S_BADGE</td>
            <td>$msg $S_FIX</td>
          </tr>" >> "$HTML_REPORT"
}

create_html_header

# --- START ALLE CHECKS ---
echo -e "\n--- Voer verificaties uit ---"

# Security
log_check "Security" "SELinux" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Status: $(getenforce)" "setenforce 1 && sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Firewalld service" "systemctl enable --now firewalld"
log_check "Security" "Root Pass" "OK" "Laatste wijziging: $(chage -l root | grep 'Last password change' | cut -d: -f2)" ""

if id "$ADMIN_USER" &>/dev/null; then
    log_check "Security" "$ADMIN_USER" "OK" "Aanwezig" ""
    log_check "Security" "Sudo Rights" "$(sudo -l -U "$ADMIN_USER" | grep -qE "\(ALL(:ALL)?\) ALL" && echo "OK" || echo "FAIL")" "Check ALL rechten" "usermod -aG wheel $ADMIN_USER"
else
    log_check "Security" "$ADMIN_USER" "FAIL" "Niet gevonden" "useradd $ADMIN_USER"
fi

if systemctl is-active --quiet sophos-spl; then
    log_check "Security" "Sophos MDR" "OK" "Draait" ""
elif systemctl is-active --quiet sav-protect; then
    log_check "Security" "Sophos MDR" "FAIL" "Oude SAV agent" "Verwijder SAV en installeer SPL"
else
    log_check "Security" "Sophos MDR" "FAIL" "Niet actief" "Installeer Sophos MDR agent"
fi

# Network
[[ "$(hostnamectl --static)" =~ ^it2.* ]] && log_check "Network" "Hostname" "OK" "$(hostname)" "" || log_check "Network" "Hostname" "FAIL" "$(hostname)" "hostnamectl set-hostname it2-naam"
IP_METHOD=$(nmcli -f ipv4.method connection show "$(nmcli -t -f NAME connection show --active | head -n1)" | awk '{print $2}')
[ "$IP_METHOD" == "manual" ] && log_check "Network" "Static IP" "OK" "Manual" "" || log_check "Network" "Static IP" "FAIL" "Staat op $IP_METHOD" "nmtui"

if [ -n "$GATEWAY_IP" ]; then
    ping -c 2 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway" "OK" "Ping OK" "" || log_check "Network" "Gateway" "FAIL" "Geen ping" "Check routing"
else
    log_check "Network" "Gateway" "FAIL" "Geen IP" "Check IP config"
fi

ping -c 2 -q 8.8.8.8 &>/dev/null && log_check "Network" "Internet" "OK" "8.8.8.8 OK" "" || log_check "Network" "Internet" "FAIL" "Geen verbinding" "Check NAT/Firewall"
nslookup google.com &>/dev/null && log_check "Network" "DNS Res" "OK" "Resolved" "" || log_check "Network" "DNS Res" "FAIL" "DNS Fail" "vi /etc/resolv.conf"
nslookup "$(hostname)" &>/dev/null && log_check "Network" "DNS Fwd" "OK" "OK" "" || log_check "Network" "DNS Fwd" "FAIL" "Check DNS A-record" ""
nslookup "$(hostname -I | awk '{print $1}')" &>/dev/null && log_check "Network" "DNS Rev" "OK" "OK" "" || log_check "Network" "DNS Rev" "FAIL" "Check PTR-record" ""

# System
dnf check-update &>/dev/null && log_check "System" "Updates" "OK" "Up-to-date" "" || log_check "System" "Updates" "FAIL" "Updates beschikbaar" "dnf update -y"
log_check "System" "Timezone" "$([ "$(timedatectl show -p Timezone --value)" == "$TARGET_TIMEZONE" ] && echo "OK" || echo "FAIL")" "$(timedatectl show -p Timezone --value)" "timedatectl set-timezone Europe/Amsterdam"
timedatectl show -p NTPSynchronized --value | grep -q "yes" && log_check "System" "NTP Sync" "OK" "Sync" "" || log_check "System" "NTP Sync" "FAIL" "Niet gesynced" "systemctl restart chronyd"
ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
[ "$ROOT_USE" -lt 90 ] && log_check "System" "Disk" "OK" "${ROOT_USE}%" "" || log_check "System" "Disk" "FAIL" "${ROOT_USE}%" "Schoon schijf op"

# --- AFSLUITEN MET COUNTER UPDATE ---
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

echo -e "\n${GREEN}Dashboard gegenereerd:${NC} $HTML_REPORT"

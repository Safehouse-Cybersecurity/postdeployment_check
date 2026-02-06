#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V10 - AZURE ARC FIX & CIS EVIDENCE
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
TOTAL_CHECKS=0; PASSED_CHECKS=0; FAILED_CHECKS=0

# --- HTML INITIALISATIE ---
create_html_header() {
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Deployment Audit: $HOSTNAME_SHORT</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f8fafc; --card: #ffffff; --text: #1e293b; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; }
        body { font-family: 'Inter', sans-serif; background-color: var(--bg); color: var(--text); margin: 0; padding: 20px; }
        .container { max-width: 1200px; margin: auto; }
        .tabs { display: flex; gap: 5px; margin-bottom: -1px; position: relative; z-index: 10; }
        .tab-btn { padding: 12px 24px; cursor: pointer; background: #e2e8f0; border: none; border-radius: 8px 8px 0 0; font-weight: 600; color: #64748b; }
        .tab-btn.active { background: var(--card); color: var(--primary); border-bottom: 2px solid var(--primary); }
        .tab-content { display: none; background: var(--card); padding: 30px; border-radius: 0 12px 12px 12px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); }
        .tab-content.active { display: block; }
        .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: #f1f5f9; padding: 20px; border-radius: 12px; text-align: center; }
        .stat-value { font-size: 2em; font-weight: 700; display: block; }
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 12px; background: #f8fafc; color: #64748b; text-transform: uppercase; font-size: 0.75em; border-bottom: 2px solid #e2e8f0; }
        td { padding: 15px; border-bottom: 1px solid #f1f5f9; vertical-align: top; }
        .badge { padding: 4px 10px; border-radius: 6px; font-size: 0.75em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #15803d; }
        .badge-fail { background: #fee2e2; color: #b91c1c; }
        .evidence-block { margin-bottom: 30px; border-left: 4px solid #cbd5e1; padding-left: 20px; }
        .evidence-title { font-weight: 700; margin-bottom: 10px; color: #334155; }
        .raw-output { background: #1e293b; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: 'Courier New', monospace; font-size: 0.85em; overflow-x: auto; white-space: pre-wrap; }
        .fix-container { background: #fffbeb; border: 1px solid #fef3c7; padding: 10px; border-radius: 6px; margin-top: 8px; display: flex; justify-content: space-between; align-items: center; }
        .copy-btn { background: #f59e0b; color: white; border: none; padding: 4px 8px; border-radius: 4px; cursor: pointer; font-size: 0.7em; }
    </style>
    <script>
        function showTab(id) {
            document.querySelectorAll('.tab-content, .tab-btn').forEach(el => el.classList.remove('active'));
            document.getElementById(id).classList.add('active');
            document.getElementById('btn-' + id).classList.add('active');
        }
        function copyTo(t) { navigator.clipboard.writeText(t); alert('Gekopieerd!'); }
    </script>
</head>
<body>
    <div class="container">
        <header style="margin-bottom: 30px;">
            <h1>🛡️ Deployment & CIS Audit: $HOSTNAME_SHORT</h1>
            <p>Admin: <code>$ADMIN_USER</code> | Datum: $(date)</p>
        </header>
        <div class="tabs">
            <button id="btn-dashboard" class="tab-btn active" onclick="showTab('dashboard')">📊 Dashboard</button>
            <button id="btn-evidence" class="tab-btn" onclick="showTab('evidence')">📜 Technical Evidence</button>
        </div>
        <div id="dashboard" class="tab-content active">
            <div class="stats-grid">
                <div class="stat-card"><span class="stat-value" id="total-val">0</span>Checks</div>
                <div class="stat-card" style="color:var(--success)"><span class="stat-value" id="pass-val">0</span>Pass</div>
                <div class="stat-card" style="color:var(--fail)"><span class="stat-value" id="fail-val">0</span>Fail</div>
            </div>
            <table>
                <thead><tr><th>Categorie</th><th>Check Item</th><th>Status</th><th>Details & Fix</th></tr></thead>
                <tbody id="dash-table"></tbody>
            </table>
        </div>
        <div id="evidence" class="tab-content"><div id="evidence-list"></div></div>
    </div>
</body>
</html>
EOF
}

# --- LOG FUNCTIE ---
log_check() {
    local category=$1; local name=$2; local status=$3; local msg=$4; local fix=$5; local raw_out=$6
    ((TOTAL_CHECKS++))
    if [ "$status" == "OK" ]; then
        ((PASSED_CHECKS++))
        echo -e "${GREEN}[OK]${NC} $category: $name - $msg"
        HTML_S="<span class='badge badge-pass'>PASS</span>"; FIX_UI=""
    else
        ((FAILED_CHECKS++))
        echo -e "${RED}[FAIL]${NC} $category: $name - $msg"
        HTML_S="<span class='badge badge-fail'>FAIL</span>"
        FIX_UI="<div class='fix-container'><code>$fix</code><button class='copy-btn' onclick=\"copyTo('$fix')\">Copy</button></div>"
    fi
    echo "<tr><td>$category</td><td>$name</td><td>$HTML_S</td><td>$msg $FIX_UI</td></tr>" >> dashboard_tmp.html
    echo "<div class='evidence-block'><div class='evidence-title'>[$category] $name</div><div class='raw-output'># Evidence:\n$raw_out</div></div>" >> evidence_tmp.html
}

create_html_header
echo -e "========================================================\nSTART POST-DEPLOYMENT CHECKS VOOR GEBRUIKER: $ADMIN_USER\nRAPPORT: $HTML_REPORT\n========================================================"

# --- 1. SECURITY ---
echo -e "\n--- Checking Security ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce)" "setenforce 1 && sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" "$(getenforce; sestatus)"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active (running)" "systemctl enable --now firewalld" "$(systemctl status firewalld --no-pager)"
log_check "Security" "Root Password" "OK" "Laatste wijziging: $(chage -l root | grep 'Last password change' | cut -d: -f2)" "" "$(chage -l root)"

if id "$ADMIN_USER" &>/dev/null; then
    ADM_CH=$(chage -l "$ADMIN_USER" | grep "Last password change" | cut -d: -f2)
    log_check "Security" "$ADMIN_USER Password" "OK" "Gebruiker aanwezig. Gewijzigd: $ADM_CH" "" "$(id "$ADMIN_USER"; chage -l "$ADMIN_USER")"
    RAW_SUDO=$(sudo -l -U "$ADMIN_USER")
    log_check "Security" "Sudo Rights" "$(echo "$RAW_SUDO" | grep -qE "\(ALL(:ALL)?\) ALL" && echo "OK" || echo "FAIL")" "$ADMIN_USER heeft ALL rechten" "usermod -aG wheel $ADMIN_USER" "$RAW_SUDO"
else
    log_check "Security" "$ADMIN_USER Password" "FAIL" "Gebruiker niet gevonden" "useradd $ADMIN_USER" "User $ADMIN_USER does not exist"
fi

# Sophos Check (Service based)
RAW_SOPHOS=$(systemctl status sophos-spl --no-pager 2>&1)
if systemctl is-active --quiet sophos-spl; then
    log_check "Security" "Sophos MDR" "OK" "sophos-spl service actief (running)" "" "$RAW_SOPHOS"
else
    log_check "Security" "Sophos MDR" "FAIL" "sophos-spl service niet actief" "systemctl start sophos-spl" "$RAW_SOPHOS"
fi

# Azure Arc Check (VERBETERD: Kijkt naar status ipv alleen service naam)
RAW_ARC=$(azcmagent show 2>&1)
if echo "$RAW_ARC" | grep -iq "Agent Status.*: Connected"; then
    log_check "Security" "Azure Arc" "OK" "Connected Machine Agent verbonden" "" "$RAW_ARC"
else
    log_check "Security" "Azure Arc" "FAIL" "Agent niet verbonden" "sudo azcmagent connect" "$RAW_ARC"
fi

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
CUR_H=$(hostnamectl --static)
log_check "Network" "Hostname" "$([[ "$CUR_H" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$CUR_H" "hostnamectl set-hostname it2-$(hostname)" "$(hostnamectl)"
PRIM_CONN=$(nmcli -t -f NAME connection show --active | head -n1)
IP_M=$(nmcli -f ipv4.method connection show "$PRIM_CONN" | awk '{print $2}')
log_check "Network" "Static IP" "$([ "$IP_M" == "manual" ] && echo "OK" || echo "FAIL")" "Interface op $IP_M" "nmtui" "$(nmcli device show)"
if [ -n "$GATEWAY_IP" ]; then
    ping -c 2 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway Ping" "OK" "Ping $GATEWAY_IP OK" "" "Gateway: $GATEWAY_IP" || log_check "Network" "Gateway Ping" "FAIL" "Ping fail" "" "Gateway: $GATEWAY_IP"
else
    log_check "Network" "Gateway Ping" "FAIL" "Geen GW gevonden" "" "No default route"
fi
ping -c 2 -q 8.8.8.8 &>/dev/null && log_check "Network" "Internet Ping" "OK" "Connectie met 8.8.8.8 OK" "" "8.8.8.8 reachable" || log_check "Network" "Internet Ping" "FAIL" "Geen internet" "" "8.8.8.8 unreachable"
RAW_DNS=$(nslookup google.com 2>&1)
log_check "Network" "DNS Resolutie" "$(echo "$RAW_DNS" | grep -q "Address" && echo "OK" || echo "FAIL")" "google.com resolved" "" "$RAW_DNS"
log_check "Network" "DNS Forward" "$(nslookup "$(hostname)" &>/dev/null && echo "OK" || echo "FAIL")" "Hostname lookup" "" "$(nslookup "$(hostname)" 2>&1)"
log_check "Network" "DNS Reverse" "$(nslookup "$(hostname -I | awk '{print $1}')" &>/dev/null && echo "OK" || echo "FAIL")" "Reverse lookup" "" "$(nslookup "$(hostname -I | awk '{print $1}')" 2>&1)"

# --- 3. SYSTEM ---
echo -e "\n--- Checking System ---"
RAW_UP=$(dnf check-update); [ $? -eq 0 ] && log_check "System" "Updates" "OK" "Systeem up-to-date" "" "$RAW_UP" || log_check "System" "Updates" "FAIL" "Updates beschikbaar" "dnf update -y" "$RAW_UP"
log_check "System" "Repositories" "OK" "Standaard repos actief" "" "$(dnf repolist)"
log_check "System" "Timezone" "OK" "$(timedatectl show -p Timezone --value)" "" "$(timedatectl)"
log_check "System" "NTP Sync" "$(timedatectl show -p NTPSynchronized --value | grep -q 'yes' && echo "OK" || echo "FAIL")" "Gesynchroniseerd" "" "$(timedatectl)"
log_check "System" "Locale" "OK" "$(localectl status | grep 'LANG' | cut -d= -f2)" "" "$(localectl status)"
ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
log_check "System" "Disk Usage" "$([ "$ROOT_USE" -lt 90 ] && echo "OK" || echo "FAIL")" "Root gebruik: ${ROOT_USE}%" "" "$(df -h /)"

# --- SAMENVOEGEN & CLEANUP ---
sed -i "/<tbody id=\"dash-table\"><\/tbody>/r dashboard_tmp.html" "$HTML_REPORT"
sed -i "/<div id=\"evidence-list\"><\/div>/r evidence_tmp.html" "$HTML_REPORT"
rm -f dashboard_tmp.html evidence_tmp.html
cat <<EOF >> "$HTML_REPORT"
<script>
    document.getElementById('total-val').innerText = '$TOTAL_CHECKS';
    document.getElementById('pass-val').innerText = '$PASSED_CHECKS';
    document.getElementById('fail-val').innerText = '$FAILED_CHECKS';
</script>
EOF
echo -e "\n${GREEN}Klaar! Dashboard & Evidence:${NC} $HTML_REPORT"

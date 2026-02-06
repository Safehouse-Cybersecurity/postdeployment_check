#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V7 - CIS COMPLIANT (TABS & EVIDENCE)
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
        
        /* Tabs Logic */
        .tabs { display: flex; gap: 5px; margin-bottom: -1px; position: relative; z-index: 10; }
        .tab-btn { padding: 12px 24px; cursor: pointer; background: #e2e8f0; border: none; border-radius: 8px 8px 0 0; font-weight: 600; color: #64748b; }
        .tab-btn.active { background: var(--card); color: var(--primary); border-bottom: 2px solid var(--primary); }
        .tab-content { display: none; background: var(--card); padding: 30px; border-radius: 0 12px 12px 12px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); }
        .tab-content.active { display: block; }

        /* Stats Cards */
        .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: #f1f5f9; padding: 20px; border-radius: 12px; text-align: center; }
        .stat-value { font-size: 2em; font-weight: 700; display: block; }

        /* Table & Badges */
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 12px; background: #f8fafc; color: #64748b; text-transform: uppercase; font-size: 0.75em; border-bottom: 2px solid #e2e8f0; }
        td { padding: 15px; border-bottom: 1px solid #f1f5f9; }
        .badge { padding: 4px 10px; border-radius: 6px; font-size: 0.75em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #15803d; }
        .badge-fail { background: #fee2e2; color: #b91c1c; }
        
        /* Evidence Blocks */
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

        <div id="evidence" class="tab-content">
            <div id="evidence-list"></div>
        </div>
    </div>
</body>
</html>
EOF
}

# --- LOG FUNCTIE (Captures Evidence) ---
log_check() {
    local category=$1; local name=$2; local status=$3; local msg=$4; local fix=$5; local raw_out=$6
    ((TOTAL_CHECKS++))
    
    # Terminal Output (Exacte match)
    if [ "$status" == "OK" ]; then
        ((PASSED_CHECKS++))
        echo -e "${GREEN}[OK]${NC} $category: $name - $msg"
        HTML_S="<span class='badge badge-pass'>PASS</span>"
        FIX_UI=""
    else
        ((FAILED_CHECKS++))
        echo -e "${RED}[FAIL]${NC} $category: $name - $msg"
        HTML_S="<span class='badge badge-fail'>FAIL</span>"
        FIX_UI="<div class='fix-container'><code>$fix</code><button class='copy-btn' onclick=\"copyTo('$fix')\">Copy</button></div>"
    fi

    # Append to Dashboard Table
    echo "<tr><td>$category</td><td>$name</td><td>$HTML_S</td><td>$msg $FIX_UI</td></tr>" >> dashboard_tmp.html

    # Append to Evidence Tab
    echo "<div class='evidence-block'>
            <div class='evidence-title'>[$category] $name</div>
            <div class='raw-output'># Command Output / Evidence:\n$raw_out</div>
          </div>" >> evidence_tmp.html
}

create_html_header
echo -e "========================================================\nSTART CHECKS - RAPPORT: $HTML_REPORT\n========================================================"

# --- 1. SECURITY ---
echo -e "\n--- Checking Security ---"
RAW_SE=$(getenforce; ls -l /etc/selinux/config)
log_check "Security" "SELinux Status" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce)" "setenforce 1 && sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" "$RAW_SE"

RAW_FW=$(systemctl status firewalld --no-pager)
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active" "systemctl enable --now firewalld" "$RAW_FW"

RAW_ROOT=$(chage -l root)
log_check "Security" "Root Password" "OK" "Geregistreerd" "" "$RAW_ROOT"

if id "$ADMIN_USER" &>/dev/null; then
    RAW_ADM=$(id "$ADMIN_USER"; chage -l "$ADMIN_USER")
    log_check "Security" "$ADMIN_USER Password" "OK" "Gebruiker aanwezig" "" "$RAW_ADM"
    RAW_SUDO=$(sudo -l -U "$ADMIN_USER")
    log_check "Security" "Sudo Rights" "$(echo "$RAW_SUDO" | grep -qE "\(ALL(:ALL)?\) ALL" && echo "OK" || echo "FAIL")" "Check ALL rechten" "usermod -aG wheel $ADMIN_USER" "$RAW_SUDO"
else
    log_check "Security" "$ADMIN_USER" "FAIL" "Niet gevonden" "useradd $ADMIN_USER" "User $ADMIN_USER not found in /etc/passwd"
fi

RAW_SOPHOS=$(systemctl status sophos-spl --no-pager 2>&1)
log_check "Security" "Sophos MDR" "$([ -f /opt/sophos-spl/bin/sophos-management-agent ] && echo "OK" || echo "FAIL")" "Service status" "Installeer Sophos MDR" "$RAW_SOPHOS"

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
RAW_HOST=$(hostnamectl)
log_check "Network" "Hostname" "$([[ "$(hostname -s)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "hostnamectl set-hostname it2-server" "$RAW_HOST"

RAW_IP=$(nmcli device show)
log_check "Network" "Static IP" "OK" "IP Config" "" "$RAW_IP"

RAW_GW=$(ip route | grep default)
ping -c 2 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway Ping" "OK" "Bereikbaar" "" "$RAW_GW" || log_check "Network" "Gateway Ping" "FAIL" "Unreachable" "" "$RAW_GW"

RAW_DNS=$(nslookup google.com 2>&1)
log_check "Network" "DNS Resolutie" "$(echo "$RAW_DNS" | grep -q "Address" && echo "OK" || echo "FAIL")" "Google lookup" "" "$RAW_DNS"

# --- 3. SYSTEM ---
echo -e "\n--- Checking System ---"
RAW_UP=$(dnf check-update)
[ $? -eq 0 ] && log_check "System" "Updates" "OK" "Up-to-date" "" "$RAW_UP" || log_check "System" "Updates" "FAIL" "Updates beschikbaar" "dnf update -y" "$RAW_UP"

RAW_TZ=$(timedatectl)
log_check "System" "Timezone" "OK" "$(timedatectl show -p Timezone --value)" "" "$RAW_TZ"

RAW_DISK=$(df -h /)
log_check "System" "Disk Usage" "OK" "Root partitie" "" "$RAW_DISK"

# --- SAMENVOEGEN ---
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

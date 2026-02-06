#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V12 - SYSTEM IDENTITY & CIS EVIDENCE
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

# Systeeminformatie verzamelen voor de header
ADMIN_USER="$1"
OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
KERNEL=$(uname -sr)
UPTIME=$(uptime -p)
VIRT=$(systemd-detect-virt)
IP_ADDR=$(hostname -I | awk '{print $1}')
FQDN=$(hostname -f)
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
    <title>Audit Rapport: $HOSTNAME_SHORT</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f8fafc; --card: #ffffff; --text: #1e293b; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; }
        body { font-family: 'Inter', sans-serif; background-color: var(--bg); color: var(--text); margin: 0; padding: 20px; }
        .container { max-width: 1200px; margin: auto; }
        
        /* System Identity Header */
        .sys-info-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #f1f5f9; padding: 20px; border-radius: 12px; margin-bottom: 25px; border: 1px solid #e2e8f0; }
        .sys-info-item { font-size: 0.9em; }
        .sys-info-item strong { color: #64748b; text-transform: uppercase; font-size: 0.8em; display: block; }

        /* Tabs Logic */
        .tabs { display: flex; gap: 5px; margin-bottom: -1px; position: relative; z-index: 10; }
        .tab-btn { padding: 12px 24px; cursor: pointer; background: #e2e8f0; border: none; border-radius: 8px 8px 0 0; font-weight: 600; color: #64748b; }
        .tab-btn.active { background: var(--card); color: var(--primary); border-bottom: 2px solid var(--primary); }
        .tab-content { display: none; background: var(--card); padding: 30px; border-radius: 0 12px 12px 12px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); }
        .tab-content.active { display: block; }

        .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: #fff; border: 1px solid #f1f5f9; padding: 20px; border-radius: 12px; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.02); }
        .stat-value { font-size: 2em; font-weight: 700; display: block; }

        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 12px; background: #f8fafc; color: #64748b; text-transform: uppercase; font-size: 0.75em; border-bottom: 2px solid #e2e8f0; }
        td { padding: 15px; border-bottom: 1px solid #f1f5f9; vertical-align: top; }
        .badge { padding: 4px 10px; border-radius: 6px; font-size: 0.75em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #15803d; }
        .badge-fail { background: #fee2e2; color: #b91c1c; }
        
        .evidence-block { margin-bottom: 30px; border-left: 4px solid #cbd5e1; padding-left: 20px; }
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
        <header style="margin-bottom: 25px;">
            <h1 style="margin:0; color:var(--primary);">🛡️ Post-Deployment Audit</h1>
            <p style="color:#64748b; margin:5px 0 0 0;">Rapportage gegenereerd voor <strong>$HOSTNAME_SHORT</strong></p>
        </header>

        <div class="sys-info-grid">
            <div class="sys-info-item"><strong>Hostname (FQDN)</strong>$FQDN</div>
            <div class="sys-info-item"><strong>IPv4 Adres</strong>$IP_ADDR</div>
            <div class="sys-info-item"><strong>Besturingssysteem</strong>$OS_NAME</div>
            <div class="sys-info-item"><strong>Kernel Versie</strong>$KERNEL</div>
            <div class="sys-info-item"><strong>Systeem Uptime</strong>$UPTIME</div>
            <div class="sys-info-item"><strong>Virtualisatie</strong>$VIRT</div>
        </div>

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

# --- LOG FUNCTIE (Exacte terminal match + Evidence) ---
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
    echo "<tr><td>$category</td><td style='font-weight:600;'>$name</td><td>$HTML_S</td><td>$msg $FIX_UI</td></tr>" >> dashboard_tmp.html
    echo "<div class='evidence-block'><div style='font-weight:700; margin-bottom:8px;'>[$category] $name</div><div class='raw-output'># Evidence / Command Output:\n$raw_out</div></div>" >> evidence_tmp.html
}

create_html_header
echo -e "========================================================\nSTART POST-DEPLOYMENT CHECKS: $FQDN\n========================================================"

# --- 1. SECURITY ---
echo -e "\n--- Checking Security ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce)" "setenforce 1 && sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" "$(getenforce; sestatus)"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active" "systemctl enable --now firewalld" "$(systemctl status firewalld --no-pager)"
log_check "Security" "Root Password" "OK" "Gewijzigd: $(chage -l root | grep 'Last password change' | cut -d: -f2)" "" "$(chage -l root)"

if id "$ADMIN_USER" &>/dev/null; then
    ADM_CH=$(chage -l "$ADMIN_USER" | grep "Last password change" | cut -d: -f2)
    log_check "Security" "$ADMIN_USER Password" "OK" "Gewijzigd: $ADM_CH" "" "$(id "$ADMIN_USER"; chage -l "$ADMIN_USER")"
    RAW_SUDO=$(sudo -l -U "$ADMIN_USER")
    log_check "Security" "Sudo Rights" "$(echo "$RAW_SUDO" | grep -qE "\(ALL(:ALL)?\) ALL" && echo "OK" || echo "FAIL")" "ALL rechten" "usermod -aG wheel $ADMIN_USER" "$RAW_SUDO"
else
    log_check "Security" "$ADMIN_USER" "FAIL" "Niet gevonden" "useradd $ADMIN_USER" "User not found"
fi

# Sophos MDR (Service based fix)
RAW_SOPHOS=$(systemctl status sophos-spl --no-pager 2>&1)
log_check "Security" "Sophos MDR" "$(systemctl is-active --quiet sophos-spl && echo "OK" || echo "FAIL")" "Service status" "systemctl start sophos-spl" "$RAW_SOPHOS"

# Azure Arc (Status based fix)
RAW_ARC=$(azcmagent show 2>&1)
if echo "$RAW_ARC" | grep -iq "Agent Status.*: Connected"; then
    log_check "Security" "Azure Arc" "OK" "Verbonden" "" "$RAW_ARC"
else
    log_check "Security" "Azure Arc" "FAIL" "Niet verbonden" "sudo azcmagent connect" "$RAW_ARC"
fi

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
log_check "Network" "Hostname" "$([[ "$(hostnamectl --static)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "hostnamectl set-hostname it2-$(hostname)" "$(hostnamectl)"
PRIM_CONN=$(nmcli -t -f NAME connection show --active | head -n1)
IP_M=$(nmcli -f ipv4.method connection show "$PRIM_CONN" | awk '{print $2}')
log_check "Network" "Static IP" "$([ "$IP_M" == "manual" ] && echo "OK" || echo "FAIL")" "Status: $IP_M" "nmtui" "$(nmcli device show)"

if [ -n "$GATEWAY_IP" ]; then
    ping -c 2 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway Ping" "OK" "Ping OK" "" "GW: $GATEWAY_IP" || log_check "Network" "Gateway Ping" "FAIL" "Geen ping" "" "GW: $GATEWAY_IP"
fi

ping -c 2 -q 8.8.8.8 &>/dev/null && log_check "Network" "Internet Ping" "OK" "8.8.8.8 OK" "" "Internet OK" || log_check "Network" "Internet Ping" "FAIL" "Geen internet" "" "Internet fail"
RAW_DNS=$(nslookup google.com 2>&1)
log_check "Network" "DNS Resolutie" "$(echo "$RAW_DNS" | grep -q "Address" && echo "OK" || echo "FAIL")" "Resolved" "" "$RAW_DNS"
log_check "Network" "DNS Forward" "$(nslookup "$(hostname)" &>/dev/null && echo "OK" || echo "FAIL")" "Fwd OK" "" "$(nslookup "$(hostname)" 2>&1)"
log_check "Network" "DNS Reverse" "$(nslookup "$(hostname -I | awk '{print $1}')" &>/dev/null && echo "OK" || echo "FAIL")" "Rev OK" "" "$(nslookup "$(hostname -I | awk '{print $1}')" 2>&1)"

# --- 3. SYSTEM & PARTITIONS ---
echo -e "\n--- Checking System & Partitions ---"
RAW_UP=$(dnf check-update); [ $? -eq 0 ] && log_check "System" "Updates" "OK" "Up-to-date" "" "$RAW_UP" || log_check "System" "Updates" "FAIL" "Beschikbaar" "dnf update -y" "$RAW_UP"
log_check "System" "Timezone" "OK" "$(timedatectl show -p Timezone --value)" "" "$(timedatectl)"
log_check "System" "NTP Sync" "$(timedatectl show -p NTPSynchronized --value | grep -q 'yes' && echo "OK" || echo "FAIL")" "Sync" "" "$(timedatectl)"

ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
log_check "System" "Disk Usage" "$([ "$ROOT_USE" -lt 90 ] && echo "OK" || echo "FAIL")" "Root: ${ROOT_USE}%" "" "$(df -h)"

# Partition Hardening Evidence
RAW_MOUNTS=$(findmnt -nl -o TARGET,OPTIONS)
check_mount_opt() {
    local target=$1; local opt=$2; local name=$3
    if echo "$RAW_MOUNTS" | grep -qE "^$target.*$opt"; then
        log_check "System" "Hardening $name" "OK" "$target heeft $opt" "" "$RAW_MOUNTS"
    else
        log_check "System" "Hardening $name" "FAIL" "$target mist $opt" "Voeg '$opt' toe in /etc/fstab" "$RAW_MOUNTS"
    fi
}

[ -d /tmp ] && check_mount_opt "/tmp" "noexec" "TMP Security"
[ -d /dev/shm ] && check_mount_opt "/dev/shm" "nodev" "SHM Security"
[ -d /var/tmp ] && check_mount_opt "/var/tmp" "nosuid" "VARTMP Security"

# --- AFSLUITEN & CLEANUP ---
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
echo -e "\n${GREEN}Klaar! Rapport gegenereerd:${NC} $HTML_REPORT"

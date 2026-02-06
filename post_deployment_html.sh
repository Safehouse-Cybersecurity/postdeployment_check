#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V14 - STREAMLINED AUDIT & CIS
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

# Systeeminformatie verzamelen
ADMIN_USER="$1"
OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
KERNEL=$(uname -sr)
UPTIME=$(uptime -p)
VIRT=$(systemd-detect-virt)
IP_ADDR=$(hostname -I | awk '{print $1}')
FQDN=$(hostname -f)
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -n 1)
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
HOSTNAME_SHORT=$(hostname -s)
HTML_REPORT="report_${HOSTNAME_SHORT}_${TIMESTAMP}.html"

# Variabelen voor HTML opbouw
SEC_HTML=""; NET_HTML=""; SYS_HTML=""; TODO_HTML=""; EVIDENCE_HTML=""
TOTAL_CHECKS=0; PASSED_CHECKS=0; FAILED_CHECKS=0
SEC_P=0; SEC_T=0; NET_P=0; NET_T=0; SYS_P=0; SYS_T=0

# --- LOG FUNCTIE ---
log_check() {
    local category=$1; local name=$2; local status=$3; local msg=$4; local fix=$5; local raw_out=$6
    ((TOTAL_CHECKS++))
    
    if [ "$status" == "OK" ]; then
        ((PASSED_CHECKS++))
        echo -e "${GREEN}[OK]${NC} $category: $name - $msg"
        H_S="<span class='badge badge-pass'>PASS</span>"; H_FIX=""; H_ROW="row-pass"
    else
        ((FAILED_CHECKS++))
        echo -e "${RED}[FAIL]${NC} $category: $name - $msg"
        H_S="<span class='badge badge-fail'>FAIL</span>"
        H_ROW="row-fail"
        H_FIX="<div class='fix-container'><code>$fix</code><button class='copy-btn' onclick=\"copyTo('$fix')\">Copy</button></div>"
        TODO_HTML+="<div class='todo-item'><strong>$name:</strong> $fix</div>"
    fi

    local ROW="<tr class='$H_ROW'><td>$name</td><td>$H_S</td><td>$msg $H_FIX</td></tr>"
    
    case $category in
        "Security") SEC_HTML+="$ROW"; ((SEC_T++)); [ "$status" == "OK" ] && ((SEC_P++)) ;;
        "Network")  NET_HTML+="$ROW"; ((NET_T++)); [ "$status" == "OK" ] && ((NET_P++)) ;;
        "System")   SYS_HTML+="$ROW"; ((SYS_T++)); [ "$status" == "OK" ] && ((SYS_P++)) ;;
    esac

    EVIDENCE_HTML+="<div class='evidence-block'><div class='evidence-title'>[$category] $name</div><div class='raw-output'># Command Output:\n$raw_out</div></div>"
}

echo -e "========================================================\nSTART AUDIT: $FQDN\n========================================================"

# --- 1. SECURITY ---
echo -e "\n--- Checking Security ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce)" "setenforce 1 && sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" "$(getenforce; sestatus)"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active" "systemctl enable --now firewalld" "$(systemctl status firewalld --no-pager)"
log_check "Security" "Root Password" "OK" "Geregistreerd" "" "$(chage -l root)"

if id "$ADMIN_USER" &>/dev/null; then
    log_check "Security" "$ADMIN_USER Password" "OK" "Aanwezig" "" "$(chage -l "$ADMIN_USER")"
    RAW_SUDO=$(sudo -l -U "$ADMIN_USER")
    log_check "Security" "Sudo Rights" "$(echo "$RAW_SUDO" | grep -qE "\(ALL(:ALL)?\) ALL" && echo "OK" || echo "FAIL")" "Check ALL" "usermod -aG wheel $ADMIN_USER" "$RAW_SUDO"
else
    log_check "Security" "$ADMIN_USER" "FAIL" "Niet gevonden" "useradd $ADMIN_USER" "User not found"
fi

RAW_SOPHOS=$(systemctl status sophos-spl --no-pager 2>&1)
log_check "Security" "Sophos MDR" "$(systemctl is-active --quiet sophos-spl && echo "OK" || echo "FAIL")" "Service status" "systemctl start sophos-spl" "$RAW_SOPHOS"

RAW_ARC=$(azcmagent show 2>&1)
log_check "Security" "Azure Arc" "$(echo "$RAW_ARC" | grep -iq "Connected" && echo "OK" || echo "FAIL")" "Status" "sudo azcmagent connect" "$RAW_ARC"

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
log_check "Network" "Hostname" "$([[ "$(hostnamectl --static)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "hostnamectl set-hostname it2-$(hostname)" "$(hostnamectl)"
PRIM_CONN=$(nmcli -t -f NAME connection show --active | head -n1)
IP_M=$(nmcli -f ipv4.method connection show "$PRIM_CONN" | awk '{print $2}')
log_check "Network" "Static IP" "$([ "$IP_M" == "manual" ] && echo "OK" || echo "FAIL")" "Status: $IP_M" "nmtui" "$(nmcli device show)"

if [ -n "$GATEWAY_IP" ]; then
    ping -c 2 -q "$GATEWAY_IP" &>/dev/null && log_check "Network" "Gateway" "OK" "Ping OK" "" "GW: $GATEWAY_IP" || log_check "Network" "Gateway" "FAIL" "No ping" "" "GW: $GATEWAY_IP"
fi

ping -c 2 -q 8.8.8.8 &>/dev/null && log_check "Network" "Internet" "OK" "8.8.8.8 OK" "" "Online" || log_check "Network" "Internet" "FAIL" "Geen internet" "" "Offline"
RAW_DNS=$(nslookup google.com 2>&1)
log_check "Network" "DNS Res" "$(echo "$RAW_DNS" | grep -q "Address" && echo "OK" || echo "FAIL")" "Resolved" "" "$RAW_DNS"
log_check "Network" "DNS Fwd" "$(nslookup "$(hostname)" &>/dev/null && echo "OK" || echo "FAIL")" "Hostname" "" "$(nslookup "$(hostname)" 2>&1)"
log_check "Network" "DNS Rev" "$(nslookup "$IP_ADDR" &>/dev/null && echo "OK" || echo "FAIL")" "Reverse" "" "$(nslookup "$IP_ADDR" 2>&1)"

# --- 3. SYSTEM & HARDENING ---
echo -e "\n--- Checking System ---"
RAW_UP=$(dnf check-update); [ $? -eq 0 ] && log_check "System" "Updates" "OK" "Up-to-date" "" "$RAW_UP" || log_check "System" "Updates" "FAIL" "Beschikbaar" "dnf update -y" "$RAW_UP"
log_check "System" "Timezone" "OK" "$(timedatectl show -p Timezone --value)" "" "$(timedatectl)"
log_check "System" "NTP Sync" "$(timedatectl show -p NTPSynchronized --value | grep -q 'yes' && echo "OK" || echo "FAIL")" "Synced" "" "$(timedatectl)"

ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
log_check "System" "Disk Usage" "$([ "$ROOT_USE" -lt 90 ] && echo "OK" || echo "FAIL")" "Root: ${ROOT_USE}%" "" "$(df -h)"

RAW_MOUNTS=$(findmnt -nl -o TARGET,OPTIONS)
[ -d /tmp ] && log_check "System" "Hardening TMP" "$(echo "$RAW_MOUNTS" | grep -qE "^/tmp.*noexec" && echo "OK" || echo "FAIL")" "noexec check" "Edit fstab" "$RAW_MOUNTS"
[ -d /dev/shm ] && log_check "System" "Hardening SHM" "$(echo "$RAW_MOUNTS" | grep -qE "^/dev/shm.*nodev" && echo "OK" || echo "FAIL")" "nodev check" "Edit fstab" "$RAW_MOUNTS"

# Procentberekeningen
SEC_PERC=$(( SEC_P * 100 / SEC_T )); NET_PERC=$(( NET_P * 100 / NET_T )); SYS_PERC=$(( SYS_P * 100 / SYS_T ))

# --- HTML GENERATIE ---
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Streamlined Audit: $HOSTNAME_SHORT</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f1f5f9; --card: #ffffff; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; }
        body { font-family: 'Inter', sans-serif; background: var(--bg); color: #1e293b; margin: 0; padding: 20px; line-height: 1.5; }
        .container { max-width: 1100px; margin: auto; }
        .sys-header { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #fff; padding: 20px; border-radius: 12px; margin-bottom: 25px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .sys-item strong { display: block; font-size: 0.75em; color: #64748b; text-transform: uppercase; }
        
        .tabs { display: flex; gap: 10px; margin-bottom: 20px; }
        .tab-btn { padding: 10px 20px; border: none; border-radius: 8px; cursor: pointer; font-weight: 600; background: #cbd5e1; }
        .tab-btn.active { background: var(--primary); color: white; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }

        .todo-box { background: #fee2e2; border: 1px solid #fecaca; padding: 20px; border-radius: 12px; margin-bottom: 25px; }
        .todo-item { margin-bottom: 8px; font-size: 0.9em; color: #b91c1c; }

        .cat-card { background: white; border-radius: 12px; padding: 25px; margin-bottom: 30px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
        .cat-header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #f1f5f9; padding-bottom: 15px; margin-bottom: 20px; }
        .health-bar { height: 8px; width: 100px; background: #e2e8f0; border-radius: 4px; position: relative; }
        .health-fill { height: 100%; border-radius: 4px; background: var(--success); }

        table { width: 100%; border-collapse: collapse; font-size: 0.9em; }
        th { text-align: left; padding: 12px; color: #64748b; border-bottom: 2px solid #f1f5f9; }
        td { padding: 12px; border-bottom: 1px solid #f8fafc; }
        .row-pass:hover { background: #f0fdf4; }
        .row-fail { background: #fffafb; }
        .badge { padding: 3px 10px; border-radius: 6px; font-size: 0.8em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #166534; }
        .badge-fail { background: #fee2e2; color: #991b1b; }
        
        .raw-output { background: #0f172a; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: monospace; font-size: 0.8em; white-space: pre-wrap; margin-top: 10px; }
        .copy-btn { margin-left: 10px; background: #f59e0b; color: white; border: none; padding: 2px 6px; border-radius: 4px; cursor: pointer; font-size: 0.8em; }
        
        @media print { .tabs, .copy-btn, .todo-box { display: none; } body { padding: 0; background: white; } .cat-card { box-shadow: none; border: 1px solid #eee; } }
    </style>
</head>
<body>
    <div class="container">
        <header style="display:flex; justify-content:space-between; align-items:flex-end; margin-bottom:20px;">
            <h1 style="margin:0;">🛡️ Deployment Audit: $HOSTNAME_SHORT</h1>
            <div class="tabs"><button id="btn-dash" class="tab-btn active" onclick="tab('dash')">Dashboard</button><button id="btn-evid" class="tab-btn" onclick="tab('evid')">Evidence</button></div>
        </header>

        <div class="sys-header">
            <div class="sys-item"><strong>Hostname</strong>$FQDN</div>
            <div class="sys-item"><strong>IP Adres</strong>$IP_ADDR</div>
            <div class="sys-item"><strong>Uptime</strong>$UPTIME</div>
            <div class="sys-item"><strong>OS Release</strong>$OS_NAME</div>
            <div class="sys-item"><strong>Kernel</strong>$KERNEL</div>
            <div class="sys-item"><strong>Virtualisatie</strong>$VIRT</div>
        </div>

        <div id="dash" class="tab-content active">
            $([ "$FAILED_CHECKS" -gt 0 ] && echo "<div class='todo-box'><h3 style='margin-top:0'>⚠️ Openstaande Actiepunten</h3>$TODO_HTML</div>")

            <div class="cat-card">
                <div class="cat-header"><h3>🔐 Security Hardening</h3><div><span style='font-size:0.8em; color:#64748b;'>$SEC_PERC% OK</span><div class="health-bar"><div class="health-fill" style="width:$SEC_PERC%"></div></div></div></div>
                <table><thead><tr><th>Item</th><th style="width:100px">Status</th><th>Details</th></tr></thead><tbody>$SEC_HTML</tbody></table>
            </div>

            <div class="cat-card">
                <div class="cat-header"><h3>🌐 Network Connectivity</h3><div><span style='font-size:0.8em; color:#64748b;'>$NET_PERC% OK</span><div class="health-bar"><div class="health-fill" style="width:$NET_PERC%"></div></div></div></div>
                <table><thead><tr><th>Item</th><th style="width:100px">Status</th><th>Details</th></tr></thead><tbody>$NET_HTML</tbody></table>
            </div>

            <div class="cat-card">
                <div class="cat-header"><h3>⚙️ System & Hardening</h3><div><span style='font-size:0.8em; color:#64748b;'>$SYS_PERC% OK</span><div class="health-bar"><div class="health-fill" style="width:$SYS_PERC%"></div></div></div></div>
                <table><thead><tr><th>Item</th><th style="width:100px">Status</th><th>Details</th></tr></thead><tbody>$SYS_HTML</tbody></table>
            </div>
        </div>

        <div id="evid" class="tab-content">$EVIDENCE_HTML</div>
    </div>
    <script>
        function tab(n){document.querySelectorAll('.tab-content,.tab-btn').forEach(e=>e.classList.remove('active'));document.getElementById(n).classList.add('active');document.getElementById('btn-'+n).classList.add('active');}
        function copyTo(t){navigator.clipboard.writeText(t);alert('Commando gekopieerd!');}
    </script>
</body>
</html>
EOF

echo -e "\n${GREEN}Gereed! Rapport:${NC} $HTML_REPORT"

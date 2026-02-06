#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V15 - FULL CIS COMPLIANCE AUDIT
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
SEC_HTML=""; NET_HTML=""; SYS_HTML=""; CIS_HTML=""; TODO_HTML=""; EVIDENCE_HTML=""
TOTAL_CHECKS=0; PASSED_CHECKS=0; FAILED_CHECKS=0
SEC_P=0; SEC_T=0; NET_P=0; NET_T=0; SYS_P=0; SYS_T=0; CIS_P=0; CIS_T=0

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
        "CIS")      CIS_HTML+="$ROW"; ((CIS_T++)); [ "$status" == "OK" ] && ((CIS_P++)) ;;
    esac

    EVIDENCE_HTML+="<div class='evidence-block'><div class='evidence-title'>[$category] $name</div><div class='raw-output'># Command Output:\n$raw_out</div></div>"
}

echo -e "========================================================\nSTART CIS AUDIT: $FQDN\n========================================================"

# --- 1. SECURITY & AGENTS ---
echo -e "\n--- Checking Security & Agents ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce)" "setenforce 1" "$(sestatus)"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active" "systemctl enable --now firewalld" "$(systemctl status firewalld --no-pager)"
log_check "Security" "Sophos MDR" "$(systemctl is-active --quiet sophos-spl && echo "OK" || echo "FAIL")" "Service status" "systemctl start sophos-spl" "$(systemctl status sophos-spl --no-pager 2>&1)"
RAW_ARC=$(azcmagent show 2>&1)
log_check "Security" "Azure Arc" "$(echo "$RAW_ARC" | grep -iq "Connected" && echo "OK" || echo "FAIL")" "Agent Status" "azcmagent connect" "$RAW_ARC"

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
log_check "Network" "Hostname" "$([[ "$(hostnamectl --static)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "hostnamectl set-hostname it2-$(hostname)" "$(hostnamectl)"
log_check "Network" "Internet" "$(ping -c 2 -q 8.8.8.8 &>/dev/null && echo "OK" || echo "FAIL")" "8.8.8.8 reachable" "" "Internet Ping Check"
RAW_DNS=$(nslookup google.com 2>&1)
log_check "Network" "DNS Resolutie" "$(echo "$RAW_DNS" | grep -q "Address" && echo "OK" || echo "FAIL")" "Resolved" "" "$RAW_DNS"

# --- 3. SYSTEM & HARDENING ---
echo -e "\n--- Checking System & Hardening ---"
ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
log_check "System" "Disk Usage" "$([ "$ROOT_USE" -lt 90 ] && echo "OK" || echo "FAIL")" "Root: ${ROOT_USE}%" "" "$(df -h /)"
RAW_MOUNTS=$(findmnt -nl -o TARGET,OPTIONS)
[ -d /tmp ] && log_check "System" "Hardening TMP" "$(echo "$RAW_MOUNTS" | grep -qE "^/tmp.*noexec" && echo "OK" || echo "FAIL")" "noexec check" "Edit /etc/fstab" "$RAW_MOUNTS"

# --- 4. CIS COMPLIANCE AUDIT (NIEUW) ---
echo -e "\n--- Running CIS Compliance Audit ---"

# 4.1 SSH Hardening (CIS 5.2.x)
RAW_SSH=$(sshd -T)
SSH_ROOT=$(echo "$RAW_SSH" | grep -i "permitrootlogin" | awk '{print $2}')
log_check "CIS" "SSH Root Login" "$([ "$SSH_ROOT" == "no" ] && echo "OK" || echo "FAIL")" "Status: $SSH_ROOT" "Set PermitRootLogin no in /etc/ssh/sshd_config" "$RAW_SSH"

# 4.2 Permissions (CIS 6.1.x)
PERM_SHADOW=$(stat -c "%a" /etc/shadow)
log_check "CIS" "Permissions /etc/shadow" "$([[ "$PERM_SHADOW" == "0" || "$PERM_SHADOW" == "600" ]] && echo "OK" || echo "FAIL")" "Perms: $PERM_SHADOW" "chmod 000 /etc/shadow" "$(ls -l /etc/shadow)"

# 4.3 Kernel Hardening (CIS 3.2.x)
IP_FWD=$(sysctl net.ipv4.ip_forward | awk '{print $3}')
log_check "CIS" "IP Forwarding" "$([ "$IP_FWD" == "0" ] && echo "OK" || echo "FAIL")" "Status: $IP_FWD" "sysctl -w net.ipv4.ip_forward=0" "$(sysctl net.ipv4.ip_forward)"

# 4.4 Banners (CIS 1.7.x)
if [ -s /etc/issue ] && ! grep -qE '(\\v|\\r|\\m|\\s)' /etc/issue; then
    log_check "CIS" "Login Banner" "OK" "Aanwezig en veilig" "" "$(cat /etc/issue)"
else
    log_check "CIS" "Login Banner" "FAIL" "Ontbreekt of lekt info" "Vul /etc/issue met een waarschuwingstext" "$(cat /etc/issue)"
fi

# 4.5 Auditing (CIS 4.1.x)
RAW_AUDIT=$(auditctl -l)
log_check "CIS" "Audit Rules" "$([ "$RAW_AUDIT" != "No rules" ] && echo "OK" || echo "FAIL")" "Rules geladen" "Configureer auditd rules" "$RAW_AUDIT"

# Procentberekeningen
calc_perc() { echo $(( $1 * 100 / $2 )); }
SEC_PERC=$(calc_perc $SEC_P $SEC_T); NET_PERC=$(calc_perc $NET_P $NET_T); SYS_PERC=$(calc_perc $SYS_P $SYS_T); CIS_PERC=$(calc_perc $CIS_P $CIS_T)

# --- HTML GENERATIE ---
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>CIS Audit: $HOSTNAME_SHORT</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f1f5f9; --card: #ffffff; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; }
        body { font-family: 'Inter', sans-serif; background: var(--bg); color: #1e293b; margin: 0; padding: 20px; }
        .container { max-width: 1100px; margin: auto; }
        .sys-header { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #fff; padding: 20px; border-radius: 12px; margin-bottom: 25px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .sys-item strong { display: block; font-size: 0.75em; color: #64748b; text-transform: uppercase; }
        .tabs { display: flex; gap: 10px; margin-bottom: 20px; }
        .tab-btn { padding: 10px 20px; border: none; border-radius: 8px; cursor: pointer; font-weight: 600; background: #cbd5e1; }
        .tab-btn.active { background: var(--primary); color: white; }
        .tab-content { display: none; } .tab-content.active { display: block; }
        .todo-box { background: #fee2e2; border: 1px solid #fecaca; padding: 20px; border-radius: 12px; margin-bottom: 25px; }
        .cat-card { background: white; border-radius: 12px; padding: 25px; margin-bottom: 30px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
        .cat-header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #f1f5f9; padding-bottom: 15px; margin-bottom: 20px; }
        .health-bar { height: 8px; width: 100px; background: #e2e8f0; border-radius: 4px; }
        .health-fill { height: 100%; border-radius: 4px; background: var(--success); }
        table { width: 100%; border-collapse: collapse; font-size: 0.9em; }
        th { text-align: left; padding: 12px; color: #64748b; border-bottom: 2px solid #f1f5f9; }
        td { padding: 12px; border-bottom: 1px solid #f8fafc; }
        .badge { padding: 3px 10px; border-radius: 6px; font-size: 0.8em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #166534; }
        .badge-fail { background: #fee2e2; color: #991b1b; }
        .fix-container { background: #fffbeb; border: 1px solid #fef3c7; padding: 10px; border-radius: 6px; margin-top: 8px; display: flex; justify-content: space-between; }
        .raw-output { background: #0f172a; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; margin-top: 10px; }
        .copy-btn { background: #f59e0b; color: white; border: none; padding: 2px 6px; border-radius: 4px; cursor: pointer; }
        @media print { .tabs, .copy-btn, .todo-box { display: none; } }
    </style>
</head>
<body>
    <div class="container">
        <header style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
            <h1 style="margin:0;">🛡️ CIS Audit Dashboard</h1>
            <div class="tabs"><button id="btn-dash" class="tab-btn active" onclick="tab('dash')">Dashboard</button><button id="btn-evid" class="tab-btn" onclick="tab('evid')">Technical Evidence</button></div>
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
            $([ "$FAILED_CHECKS" -gt 0 ] && echo "<div class='todo-box'><h3>⚠️ Openstaande Actiepunten</h3>$TODO_HTML</div>")
            
            <div class="cat-card">
                <div class="cat-header"><h3>🛡️ CIS Compliance Audit</h3><div><span>$CIS_PERC% OK</span><div class="health-bar"><div class="health-fill" style="width:$CIS_PERC%"></div></div></div></div>
                <table><thead><tr><th>Item</th><th style="width:100px">Status</th><th>Details</th></tr></thead><tbody>$CIS_HTML</tbody></table>
            </div>

            <div class="cat-card">
                <div class="cat-header"><h3>🔐 Security & Agents</h3><div><span>$SEC_PERC% OK</span><div class="health-bar"><div class="health-fill" style="width:$SEC_PERC%"></div></div></div></div>
                <table><thead><tr><th>Item</th><th style="width:100px">Status</th><th>Details</th></tr></thead><tbody>$SEC_HTML</tbody></table>
            </div>

            <div class="cat-card">
                <div class="cat-header"><h3>🌐 Network & Connectivity</h3><div><span>$NET_PERC% OK</span><div class="health-bar"><div class="health-fill" style="width:$NET_PERC%"></div></div></div></div>
                <table><thead><tr><th>Item</th><th style="width:100px">Status</th><th>Details</th></tr></thead><tbody>$NET_HTML</tbody></table>
            </div>
        </div>

        <div id="evid" class="tab-content">$EVIDENCE_HTML</div>
    </div>
    <script>
        function tab(n){document.querySelectorAll('.tab-content,.tab-btn').forEach(e=>e.classList.remove('active'));document.getElementById(n).classList.add('active');document.getElementById('btn-'+n).classList.add('active');}
        function copyTo(t){navigator.clipboard.writeText(t);alert('Gekopieerd!');}
    </script>
</body>
</html>
EOF

echo -e "\n${GREEN}Gereed! Rapport:${NC} $HTML_REPORT"

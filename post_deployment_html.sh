#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V26 - DYNAMIC DNS DETAILS & 4-BOX UI
# ==============================================================================

# Kleuren voor terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}[ERROR]${NC} Geen admin user opgegeven!"
    exit 1
fi

# 1. Dynamische OS Detectie & Info
ADMIN_USER="$1"
OS_NAME=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
KERNEL=$(uname -sr)
UPTIME=$(uptime -p)
VIRT=$(systemd-detect-virt)
IP_ADDR=$(hostname -I | awk '{print $1}')
FQDN=$(hostname -f)
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -n 1)
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
HOSTNAME_SHORT=$(hostname -s)
HTML_REPORT="report_${HOSTNAME_SHORT}_${TIMESTAMP}.html"

# Variabelen voor HTML
CIS_HTML=""; SEC_HTML=""; NET_HTML=""; SYS_HTML=""; TODO_HTML=""; EVIDENCE_HTML=""; ONELINER_CMDS=""
TOTAL_CHECKS=0; PASSED_CHECKS=0; FAILED_CHECKS=0
SEC_P=0; SEC_T=0; NET_P=0; NET_T=0; SYS_P=0; SYS_T=0; CIS_P=0; CIS_T=0

# --- LOG FUNCTIE ---
log_check() {
    local category=$1; local name=$2; local status=$3; local msg=$4; local fix=$5; local raw_out=$6
    ((TOTAL_CHECKS++))
    
    if [ "$status" == "OK" ]; then
        ((PASSED_CHECKS++))
        echo -e "${GREEN}[OK]${NC} $category: $name - $msg"
        H_S="<span class='badge badge-pass'>PASS</span>"; H_ROW="row-pass"; H_FIX=""
    else
        ((FAILED_CHECKS++))
        echo -e "${RED}[FAIL]${NC} $category: $name - $msg"
        H_S="<span class='badge badge-fail'>FAIL</span>"; H_ROW="row-fail"
        H_FIX="<div class='fix-container'><code>$fix</code><button class='copy-btn' onclick=\"copyTo('$fix')\">Copy</button></div>"
        TODO_HTML+="<div class='todo-item'><strong>$name:</strong> $msg</div>"
        if [ -n "$fix" ]; then
            [ -n "$ONELINER_CMDS" ] && ONELINER_CMDS+=" && "
            ONELINER_CMDS+="$fix"
        fi
    fi

    local ROW="<tr class='$H_ROW'><td>$name</td><td style='width:80px'>$H_S</td><td>$msg $H_FIX</td></tr>"
    
    case $category in
        "CIS")      CIS_HTML+="$ROW"; ((CIS_T++)); [ "$status" == "OK" ] && ((CIS_P++)) ;;
        "Security") SEC_HTML+="$ROW"; ((SEC_T++)); [ "$status" == "OK" ] && ((SEC_P++)) ;;
        "Network")  NET_HTML+="$ROW"; ((NET_T++)); [ "$status" == "OK" ] && ((NET_P++)) ;;
        "System")   SYS_HTML+="$ROW"; ((SYS_T++)); [ "$status" == "OK" ] && ((SYS_P++)) ;;
    esac
    EVIDENCE_HTML+="<div class='evidence-block'><div class='evidence-title'>[$category] $name</div><div class='raw-output'>$raw_out</div></div>"
}

echo -e "========================================================\nSTART AUDIT: $OS_NAME ($FQDN)\n========================================================"

# --- 1. CIS COMPLIANCE ---
echo -e "\n--- Running CIS Compliance Audit ---"
SSH_ROOT=$(sshd -T 2>/dev/null | grep -i "permitrootlogin" | awk '{print $2}')
log_check "CIS" "SSH Root Login" "$([ "$SSH_ROOT" == "no" ] && echo "OK" || echo "FAIL")" "Root login: $SSH_ROOT" "sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && sudo systemctl restart sshd" "$(sshd -T 2>/dev/null | grep -i permitroot)"
RAW_AUDIT=$(auditctl -l 2>/dev/null)
AUDIT_FIX="echo '-w /etc/passwd -p wa -k identity' | sudo tee -a /etc/audit/rules.d/audit.rules > /dev/null && sudo augenrules --load"
log_check "CIS" "Audit Rules" "$(echo "$RAW_AUDIT" | grep -q "identity" && echo "OK" || echo "FAIL")" "Rules check" "$AUDIT_FIX" "$RAW_AUDIT"
log_check "CIS" "Perms /etc/shadow" "$([ "$(stat -c "%a" /etc/shadow 2>/dev/null)" == "0" ] && echo "OK" || echo "FAIL")" "Status: $(stat -c "%a" /etc/shadow 2>/dev/null)" "sudo chmod 000 /etc/shadow" "$(ls -l /etc/shadow)"

# --- 2. SECURITY & AGENTS ---
echo -e "\n--- Checking Security & Agents ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce 2>/dev/null)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce 2>/dev/null)" "sudo setenforce 1 && sudo sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" "$(sestatus 2>/dev/null)"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active" "sudo systemctl enable --now firewalld" "$(systemctl status firewalld --no-pager)"
log_check "Security" "Sophos MDR" "$(systemctl is-active --quiet sophos-spl && echo "OK" || echo "FAIL")" "Service status" "sudo systemctl start sophos-spl" "$(systemctl status sophos-spl --no-pager 2>&1)"
log_check "Security" "Azure Arc" "$(azcmagent show 2>&1 | grep -iq "Connected" && echo "OK" || echo "FAIL")" "Verbonden" "sudo azcmagent connect" "$(azcmagent show 2>&1)"

# --- 3. NETWORK CONNECTIVITY (Dynamic DNS Details) ---
echo -e "\n--- Checking Network Connectivity ---"
log_check "Network" "Hostname" "$([[ "$(hostnamectl --static)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "sudo hostnamectl set-hostname it2-$(hostname)" "$(hostnamectl)"

# Dynamic DNS Res
RAW_RES=$(nslookup google.com 2>&1)
if echo "$RAW_RES" | grep -q "Address"; then
    log_check "Network" "DNS Res" "OK" "Resolved" "" "$RAW_RES"
else
    log_check "Network" "DNS Res" "FAIL" "Resolution failed" "" "$RAW_RES"
fi

# Dynamic DNS Fwd
RAW_FWD=$(nslookup "$(hostname)" 2>&1)
if echo "$RAW_FWD" | grep -q "Address"; then
    log_check "Network" "DNS Fwd" "OK" "Forward lookup OK" "" "$RAW_FWD"
else
    log_check "Network" "DNS Fwd" "FAIL" "Forward lookup failed" "" "$RAW_FWD"
fi

# Dynamic DNS Rev
RAW_REV=$(nslookup "$IP_ADDR" 2>&1)
if echo "$RAW_REV" | grep -q "name ="; then
    log_check "Network" "DNS Rev" "OK" "Reverse lookup OK" "" "$RAW_REV"
else
    log_check "Network" "DNS Rev" "FAIL" "Reverse lookup failed" "" "$RAW_REV"
fi

# --- 4. SYSTEM & HARDENING ---
echo -e "\n--- Checking System & Hardening ---"
ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
log_check "System" "Disk Usage" "$([ "$ROOT_USE" -lt 90 ] && echo "OK" || echo "FAIL")" "Root: ${ROOT_USE}%" "" "$(df -h /)"
log_check "System" "Hardening TMP" "$(findmnt -nl -o TARGET,OPTIONS | grep -q "/tmp.*noexec" && echo "OK" || echo "FAIL")" "noexec" "sudo mount -o remount,noexec /tmp" "$(findmnt /tmp)"
log_check "System" "NTP Sync" "$(timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q 'yes' && echo "OK" || echo "FAIL")" "Synced" "sudo systemctl restart chronyd" "$(timedatectl)"

# Procenten berekenen
calc_perc() { [ "$2" -eq 0 ] && echo "100" || echo $(( $1 * 100 / $2 )); }
SEC_PERC=$(calc_perc $SEC_P $SEC_T); NET_PERC=$(calc_perc $NET_P $NET_T); SYS_PERC=$(calc_perc $SYS_P $SYS_T); CIS_PERC=$(calc_perc $CIS_P $CIS_T)

# --- HTML GENERATIE ---
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>$OS_NAME Audit Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f8fafc; --card: #ffffff; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; --warn: #f59e0b; }
        body { font-family: 'Inter', sans-serif; background: var(--bg); color: #1e293b; padding: 20px; margin: 0; }
        .container { max-width: 1100px; margin: auto; }
        .sys-header { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #fff; padding: 20px; border-radius: 12px; margin-bottom: 25px; border: 1px solid #e2e8f0; }
        .sys-item strong { display: block; font-size: 0.75em; color: #64748b; text-transform: uppercase; }
        .health-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 25px; }
        .health-card { background: white; padding: 15px; border-radius: 12px; text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .health-val { font-size: 1.8em; font-weight: 700; display: block; margin-bottom: 5px; }
        .h-bar { height: 6px; background: #e2e8f0; border-radius: 3px; margin-top: 5px; overflow: hidden; }
        .h-fill { height: 100%; transition: width 0.5s; }
        .tabs { display: flex; gap: 8px; margin-bottom: 20px; justify-content: flex-end; }
        .tab-btn { padding: 8px 16px; border: none; border-radius: 8px; cursor: pointer; font-weight: 600; background: #cbd5e1; color: #475569; }
        .tab-btn.active { background: var(--primary); color: white; }
        .tab-content { display: none; } .tab-content.active { display: block; }
        .todo-box { background: #fff1f2; border: 1px solid #fecaca; padding: 20px; border-radius: 12px; margin-bottom: 25px; }
        .cat-card { background: white; border-radius: 12px; padding: 20px; margin-bottom: 25px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .cat-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 15px; color: var(--primary); font-weight: 700; border-bottom: 1px solid #f1f5f9; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
        td { padding: 12px; border-bottom: 1px solid #f8fafc; vertical-align: top; }
        .badge { padding: 3px 10px; border-radius: 6px; font-size: 0.75em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #166534; }
        .badge-fail { background: #fee2e2; color: #991b1b; }
        .raw-output { background: #0f172a; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; font-size: 0.8em; }
        .fix-container { background: #fffbeb; padding: 10px; border-radius: 6px; border: 1px solid #fef3c7; display: flex; justify-content: space-between; align-items: center; margin-top: 5px; }
        .copy-btn { background: #f59e0b; color: white; border: none; padding: 3px 6px; border-radius: 4px; cursor: pointer; font-size: 0.8em; }
    </style>
</head>
<body>
    <div class="container">
        <header style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
            <h1 style="margin:0; font-size: 1.8em;">🛡️ $OS_NAME Audit Dashboard</h1>
            <div class="tabs">
                <button id="btn-dash" class="tab-btn active" onclick="tab('dash')">Dashboard</button>
                <button id="btn-evid" class="tab-btn" onclick="tab('evid')">Technical Evidence</button>
                <button id="btn-fix" class="tab-btn" onclick="tab('fix')" style="background:var(--warn); color:white;">⚡ Quick-Fix</button>
            </div>
        </header>

        <div class="sys-header">
            <div class="sys-item"><strong>Hostname</strong>$FQDN</div>
            <div class="sys-item"><strong>IP Adres</strong>$IP_ADDR</div>
            <div class="sys-item"><strong>Uptime</strong>$UPTIME</div>
            <div class="sys-item"><strong>OS Release</strong>$OS_NAME</div>
            <div class="sys-item"><strong>Kernel</strong>$KERNEL</div>
            <div class="sys-item"><strong>Virtualisatie</strong>$VIRT</div>
        </div>

        <div class="health-grid">
            <div class="health-card"><h4>Security</h4><span class="health-val">$SEC_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$SEC_PERC%; background:$([ "$SEC_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
            <div class="health-card"><h4>Network</h4><span class="health-val">$NET_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$NET_PERC%; background:$([ "$NET_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
            <div class="health-card"><h4>System</h4><span class="health-val">$SYS_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$SYS_PERC%; background:$([ "$SYS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
            <div class="health-card"><h4>CIS Audit</h4><span class="health-val">$CIS_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$CIS_PERC%; background:$([ "$CIS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
        </div>

        <div id="dash" class="tab-content active">
            $([ "$FAILED_CHECKS" -gt 0 ] && echo "<div class='todo-box'><h3>⚠️ Openstaande Actiepunten</h3>$TODO_HTML</div>")
            
            <div class="cat-card"><div class="cat-header">🛡️ CIS Compliance Audit<span>$CIS_PERC%</span></div><table><tbody>$CIS_HTML</tbody></table></div>
            <div class="cat-card"><div class="cat-header">🔐 Security & Agents<span>$SEC_PERC%</span></div><table><tbody>$SEC_HTML</tbody></table></div>
            <div class="cat-card"><div class="cat-header">🌐 Network Connectivity<span>$NET_PERC%</span></div><table><tbody>$NET_HTML</tbody></table></div>
            <div class="cat-card"><div class="cat-header">⚙️ System & Hardening<span>$SYS_PERC%</span></div><table><tbody>$SYS_HTML</tbody></table></div>
        </div>

        <div id="evid" class="tab-content">$EVIDENCE_HTML</div>
        
        <div id="fix" class="tab-content">
            <div class="cat-card">
                <h3>⚡ Oneliner Quick-Fix</h3>
                <p style="font-size:0.9em; color:#64748b;">Kopieer en plak onderstaande regel in je terminal:</p>
                <div class="raw-output" id="oneliner-text" style="font-weight:bold; color:var(--warn);">$ONELINER_CMDS</div>
                <button class="tab-btn" style="margin-top:15px; background:var(--primary); color:white;" onclick="copyTo(document.getElementById('oneliner-text').innerText)">Kopieer Oneliner</button>
            </div>
        </div>
    </div>
    <script>
        function tab(n){document.querySelectorAll('.tab-content,.tab-btn').forEach(e=>e.classList.remove('active'));document.getElementById(n).classList.add('active');document.getElementById('btn-'+n).classList.add('active');}
        function copyTo(t){navigator.clipboard.writeText(t);alert('Oneliner gekopieerd!');}
    </script>
</body>
</html>
EOF

echo -e "\n${GREEN}Gereed! Rapport V26 gegenereerd:${NC} $HTML_REPORT"

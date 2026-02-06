#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V16 - HEALTH CARDS & QUICK-FIX TAB
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
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
HOSTNAME_SHORT=$(hostname -s)
HTML_REPORT="report_${HOSTNAME_SHORT}_${TIMESTAMP}.html"

# Variabelen voor HTML opbouw
SEC_HTML=""; NET_HTML=""; SYS_HTML=""; CIS_HTML=""; TODO_HTML=""; EVIDENCE_HTML=""; QUICK_FIX_CMDS=""
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
        [ -n "$fix" ] && QUICK_FIX_CMDS+="$fix\n"
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

echo -e "========================================================\nSTART V16 AUDIT: $FQDN\n========================================================"

# --- 1. SECURITY & AGENTS ---
echo -e "\n--- Checking Security & Agents ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce)" "setenforce 1" "$(sestatus)"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active" "systemctl enable --now firewalld" "$(systemctl status firewalld --no-pager)"
log_check "Security" "Sophos MDR" "$(systemctl is-active --quiet sophos-spl && echo "OK" || echo "FAIL")" "Service status" "systemctl start sophos-spl" "$(systemctl status sophos-spl --no-pager 2>&1)"
RAW_ARC=$(azcmagent show 2>&1)
log_check "Security" "Azure Arc" "$(echo "$RAW_ARC" | grep -iq "Connected" && echo "OK" || echo "FAIL")" "Status" "sudo azcmagent connect" "$RAW_ARC"

# --- 2. NETWORK ---
echo -e "\n--- Checking Network ---"
log_check "Network" "Hostname" "$([[ "$(hostnamectl --static)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "hostnamectl set-hostname it2-$(hostname)" "$(hostnamectl)"
log_check "Network" "DNS Res" "$(nslookup google.com &>/dev/null && echo "OK" || echo "FAIL")" "Resolved" "" "$(nslookup google.com 2>&1)"
log_check "Network" "DNS Fwd" "$(nslookup "$(hostname)" &>/dev/null && echo "OK" || echo "FAIL")" "Fwd OK" "" "$(nslookup "$(hostname)" 2>&1)"
log_check "Network" "DNS Rev" "$(nslookup "$IP_ADDR" &>/dev/null && echo "OK" || echo "FAIL")" "Rev OK" "" "$(nslookup "$IP_ADDR" 2>&1)"

# --- 3. SYSTEM & HARDENING ---
echo -e "\n--- Checking System ---"
ROOT_USE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
log_check "System" "Disk Usage" "$([ "$ROOT_USE" -lt 90 ] && echo "OK" || echo "FAIL")" "Root: ${ROOT_USE}%" "" "$(df -h /)"
RAW_MOUNTS=$(findmnt -nl -o TARGET,OPTIONS)
[ -d /tmp ] && log_check "System" "Hardening TMP" "$(echo "$RAW_MOUNTS" | grep -qE "^/tmp.*noexec" && echo "OK" || echo "FAIL")" "noexec" "mount -o remount,noexec /tmp" "$RAW_MOUNTS"

# --- 4. CIS COMPLIANCE (Gedetailleerde Audit Rules) ---
echo -e "\n--- Running CIS Compliance Audit ---"

# 4.1 SSH
SSH_ROOT=$(sshd -T | grep -i "permitrootlogin" | awk '{print $2}')
log_check "CIS" "SSH Root Login" "$([ "$SSH_ROOT" == "no" ] && echo "OK" || echo "FAIL")" "Root login: $SSH_ROOT" "sed -i 's/PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd" "$(sshd -T)"

# 4.2 Auditd Rules (Gedetailleerd)
RAW_AUDIT=$(auditctl -l)
check_audit_rule() {
    local pattern=$1; local name=$2; local fix=$3
    if echo "$RAW_AUDIT" | grep -qE "$pattern"; then
        log_check "CIS" "Audit: $name" "OK" "Rule aanwezig" "" "$RAW_AUDIT"
    else
        log_check "CIS" "Audit: $name" "FAIL" "Rule ontbreekt" "$fix" "$RAW_AUDIT"
    fi
}
check_audit_rule "/etc/passwd.*identity" "User Changes" "echo '-w /etc/passwd -p wa -k identity' >> /etc/audit/rules.d/audit.rules"
check_audit_rule "/etc/shadow.*identity" "Privilege Changes" "echo '-w /etc/shadow -p wa -k identity' >> /etc/audit/rules.d/audit.rules"
check_audit_rule "sudoers.*priv_esc" "Sudo Usage" "echo '-w /etc/sudoers -p wa -k priv_esc' >> /etc/audit/rules.d/audit.rules"

# 4.3 Permissions
PERM_SHADOW=$(stat -c "%a" /etc/shadow)
log_check "CIS" "Perms /etc/shadow" "$([ "$PERM_SHADOW" == "0" ] && echo "OK" || echo "FAIL")" "Perms: $PERM_SHADOW" "chmod 000 /etc/shadow" "$(ls -l /etc/shadow)"

# Procentberekeningen
calc_perc() { [ "$2" -eq 0 ] && echo "100" || echo $(( $1 * 100 / $2 )); }
SEC_PERC=$(calc_perc $SEC_P $SEC_T); NET_PERC=$(calc_perc $NET_P $NET_T)
SYS_PERC=$(calc_perc $SYS_P $SYS_T); CIS_PERC=$(calc_perc $CIS_P $CIS_T)

# --- HTML GENERATIE ---
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>V16 Audit: $HOSTNAME_SHORT</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f8fafc; --card: #ffffff; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; --warn: #f59e0b; }
        body { font-family: 'Inter', sans-serif; background: var(--bg); color: #1e293b; margin: 0; padding: 20px; }
        .container { max-width: 1100px; margin: auto; }
        
        /* Health Cards */
        .health-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 25px; }
        .health-card { background: white; padding: 15px; border-radius: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); text-align: center; }
        .health-card h4 { margin: 0 0 10px 0; font-size: 0.75em; color: #64748b; text-transform: uppercase; }
        .health-val { font-size: 1.8em; font-weight: 700; display: block; margin-bottom: 5px; }
        .h-bar { height: 6px; background: #e2e8f0; border-radius: 3px; overflow: hidden; }
        .h-fill { height: 100%; transition: width 0.5s; }

        .sys-header { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #fff; padding: 20px; border-radius: 12px; margin-bottom: 20px; border: 1px solid #e2e8f0; }
        .sys-item strong { display: block; font-size: 0.75em; color: #64748b; text-transform: uppercase; }
        
        .tabs { display: flex; gap: 8px; margin-bottom: 20px; }
        .tab-btn { padding: 10px 18px; border: none; border-radius: 8px; cursor: pointer; font-weight: 600; background: #cbd5e1; color: #475569; }
        .tab-btn.active { background: var(--primary); color: white; }
        .tab-content { display: none; } .tab-content.active { display: block; }

        .todo-box { background: #fff1f2; border: 1px solid #fecaca; padding: 20px; border-radius: 12px; margin-bottom: 25px; }
        .cat-card { background: white; border-radius: 12px; padding: 20px; margin-bottom: 25px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        
        table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
        th { text-align: left; padding: 10px; color: #64748b; border-bottom: 2px solid #f1f5f9; }
        td { padding: 12px; border-bottom: 1px solid #f8fafc; }
        .badge { padding: 3px 8px; border-radius: 5px; font-size: 0.75em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #166534; }
        .badge-fail { background: #fee2e2; color: #991b1b; }
        
        .raw-output { background: #0f172a; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; font-size: 0.8em; }
        .fix-container { background: #fffbeb; padding: 8px; border-radius: 6px; margin-top: 5px; display: flex; justify-content: space-between; align-items: center; border: 1px solid #fef3c7; }
        .copy-btn { background: #f59e0b; color: white; border: none; padding: 3px 6px; border-radius: 4px; cursor: pointer; }
    </style>
</head>
<body>
    <div class="container">
        <header style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
            <h1 style="margin:0;">🛡️ CIS Audit Dashboard V16</h1>
            <div class="tabs">
                <button id="btn-dash" class="tab-btn active" onclick="tab('dash')">Dashboard</button>
                <button id="btn-evid" class="tab-btn" onclick="tab('evid')">Technical Evidence</button>
                <button id="btn-fix" class="tab-btn" onclick="tab('fix')" style="background:#f59e0b; color:white;">⚡ Quick-Fix</button>
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
            <div class="health-card">
                <h4>Security</h4><span class="health-val" style="color:$([ "$SEC_PERC" -eq 100 ] && echo "var(--success)" || ([ "$SEC_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))">$SEC_PERC%</span>
                <div class="h-bar"><div class="h-fill" style="width:$SEC_PERC%; background:$([ "$SEC_PERC" -eq 100 ] && echo "var(--success)" || ([ "$SEC_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))"></div></div>
            </div>
            <div class="health-card">
                <h4>Network</h4><span class="health-val" style="color:$([ "$NET_PERC" -eq 100 ] && echo "var(--success)" || ([ "$NET_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))">$NET_PERC%</span>
                <div class="h-bar"><div class="h-fill" style="width:$NET_PERC%; background:$([ "$NET_PERC" -eq 100 ] && echo "var(--success)" || ([ "$NET_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))"></div></div>
            </div>
            <div class="health-card">
                <h4>System</h4><span class="health-val" style="color:$([ "$SYS_PERC" -eq 100 ] && echo "var(--success)" || ([ "$SYS_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))">$SYS_PERC%</span>
                <div class="h-bar"><div class="h-fill" style="width:$SYS_PERC%; background:$([ "$SYS_PERC" -eq 100 ] && echo "var(--success)" || ([ "$SYS_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))"></div></div>
            </div>
            <div class="health-card">
                <h4>CIS Audit</h4><span class="health-val" style="color:$([ "$CIS_PERC" -eq 100 ] && echo "var(--success)" || ([ "$CIS_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))">$CIS_PERC%</span>
                <div class="h-bar"><div class="h-fill" style="width:$CIS_PERC%; background:$([ "$CIS_PERC" -eq 100 ] && echo "var(--success)" || ([ "$CIS_PERC" -lt 70 ] && echo "var(--fail)" || echo "var(--warn)"))"></div></div>
            </div>
        </div>

        <div id="dash" class="tab-content active">
            $([ "$FAILED_CHECKS" -gt 0 ] && echo "<div class='todo-box'><h3 style='margin-top:0; color:#991b1b;'>⚠️ Openstaande Actiepunten</h3>$TODO_HTML</div>")
            <div class="cat-card"><h3>🛡️ CIS Compliance Audit</h3><table><tbody>$CIS_HTML</tbody></table></div>
            <div class="cat-card"><h3>🔐 Security & Agents</h3><table><tbody>$SEC_HTML</tbody></table></div>
            <div class="cat-card"><h3>🌐 Network & System</h3><table><tbody>$NET_HTML $SYS_HTML</tbody></table></div>
        </div>

        <div id="evid" class="tab-content">$EVIDENCE_HTML</div>

        <div id="fix" class="tab-content">
            <div class="cat-card">
                <h3>⚡ Quick-Fix Script</h3>
                <p style="font-size:0.9em; color:#64748b;">Kopieer onderstaand script naar je server om alle gefaalde checks in één keer op te lossen.</p>
                <div class="raw-output" id="fix-script">#!/bin/bash\n# Quick-fix voor $HOSTNAME_SHORT\n\n$QUICK_FIX_CMDS\necho "Herstel voltooid!"</div>
                <button class="tab-btn" onclick="copyTo(document.getElementById('fix-script').innerText)" style="margin-top:15px; background:var(--primary); color:white;">Kopieer Volledig Script</button>
            </div>
        </div>
    </div>
    <script>
        function tab(n){document.querySelectorAll('.tab-content,.tab-btn').forEach(e=>e.classList.remove('active'));document.getElementById(n).classList.add('active');document.getElementById('btn-'+n).classList.add('active');}
        function copyTo(t){navigator.clipboard.writeText(t);alert('Gekopieerd!');}
    </script>
</body>
</html>
EOF

echo -e "\n${GREEN}Klaar! Dashboard V16 gegenereerd:${NC} $HTML_REPORT"

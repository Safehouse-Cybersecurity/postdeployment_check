#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V17 - FINAL AUDIT & HARDENING
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

# Systeeminformatie
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

# Opschonen oude rapporten (Housekeeping)
find . -name "report_${HOSTNAME_SHORT}_*.html" -mtime +7 -delete

# Variabelen voor HTML
SEC_HTML=""; NET_HTML=""; SYS_HTML=""; CIS_HTML=""; TODO_HTML=""; EVIDENCE_HTML=""; QUICK_FIX_CMDS=""
TOTAL_CHECKS=0; PASSED_CHECKS=0; FAILED_CHECKS=0
SEC_P=0; SEC_T=0; NET_P=0; NET_T=0; SYS_P=0; SYS_T=0; CIS_P=0; CIS_T=0

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
        [ -n "$fix" ] && QUICK_FIX_CMDS+="$fix\n"
    fi
    local ROW="<tr class='$H_ROW'><td>$name</td><td>$H_S</td><td>$msg $H_FIX</td></tr>"
    case $category in
        "Security") SEC_HTML+="$ROW"; ((SEC_T++)); [ "$status" == "OK" ] && ((SEC_P++)) ;;
        "Network")  NET_HTML+="$ROW"; ((NET_T++)); [ "$status" == "OK" ] && ((NET_P++)) ;;
        "System")   SYS_HTML+="$ROW"; ((SYS_T++)); [ "$status" == "OK" ] && ((SYS_P++)) ;;
        "CIS")      CIS_HTML+="$ROW"; ((CIS_T++)); [ "$status" == "OK" ] && ((CIS_P++)) ;;
    esac
    EVIDENCE_HTML+="<div class='evidence-block'><div class='evidence-title'>[$category] $name</div><div class='raw-output'>$raw_out</div></div>"
}

# --- 1. SECURITY & AGENTS ---
RAW_SE=$(getenforce)
log_check "Security" "SELinux" "$([ "$RAW_SE" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Status: $RAW_SE" "setenforce 1 && sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" "$(sestatus)"
log_check "Security" "Sophos" "$(systemctl is-active --quiet sophos-spl && echo "OK" || echo "FAIL")" "Active" "systemctl start sophos-spl" "$(systemctl status sophos-spl --no-pager 2>&1)"
RAW_ARC=$(azcmagent show 2>&1)
log_check "Security" "Azure Arc" "$(echo "$RAW_ARC" | grep -iq "Connected" && echo "OK" || echo "FAIL")" "Connected" "sudo azcmagent connect" "$RAW_ARC"

# --- 2. NETWORK & PORTS ---
log_check "Network" "Hostname" "$([[ "$(hostnamectl --static)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "hostnamectl set-hostname it2-server" "$(hostnamectl)"
# Port Audit (NIEUW)
RAW_PORTS=$(ss -tuln | grep LISTEN)
log_check "Network" "Open Ports" "OK" "Listening ports gecheckt" "" "$RAW_PORTS"

# --- 3. CIS COMPLIANCE ---
# SSH (VERBETERDE FIX)
SSH_ROOT=$(sshd -T | grep -i "permitrootlogin" | awk '{print $2}')
log_check "CIS" "SSH Root" "$([ "$SSH_ROOT" == "no" ] && echo "OK" || echo "FAIL")" "Root login: $SSH_ROOT" "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd" "$(sshd -T | grep -i permitroot)"

# Auditd (MET RELOAD FIX)
RAW_AUDIT=$(auditctl -l)
if echo "$RAW_AUDIT" | grep -q "identity"; then
    log_check "CIS" "Audit Rules" "OK" "Identity rules geladen" "" "$RAW_AUDIT"
else
    log_check "CIS" "Audit Rules" "FAIL" "Regels missen" "echo '-w /etc/passwd -p wa -k identity' >> /etc/audit/rules.d/audit.rules && augenrules --load" "$RAW_AUDIT"
fi

# --- 4. SYSTEM HARDENING ---
RAW_MOUNTS=$(findmnt -nl -o TARGET,OPTIONS)
[ -d /tmp ] && log_check "System" "Hardening TMP" "$(echo "$RAW_MOUNTS" | grep -q "noexec" && echo "OK" || echo "FAIL")" "noexec" "mount -o remount,noexec /tmp" "$RAW_MOUNTS"

# Procenten
calc_perc() { [ "$2" -eq 0 ] && echo "100" || echo $(( $1 * 100 / $2 )); }
SEC_PERC=$(calc_perc $SEC_P $SEC_T); NET_PERC=$(calc_perc $NET_P $NET_T); SYS_PERC=$(calc_perc $SYS_P $SYS_T); CIS_PERC=$(calc_perc $CIS_P $CIS_T)

# --- HTML GENERATIE ---
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Audit V17: $HOSTNAME_SHORT</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #f1f5f9; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; --warn: #f59e0b; }
        body { font-family: 'Inter', sans-serif; background: var(--bg); color: #1e293b; padding: 20px; }
        .container { max-width: 1100px; margin: auto; }
        .sys-header { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #fff; padding: 20px; border-radius: 12px; margin-bottom: 25px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .sys-item strong { display: block; font-size: 0.75em; color: #64748b; text-transform: uppercase; }
        .health-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 25px; }
        .health-card { background: white; padding: 15px; border-radius: 12px; text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .health-val { font-size: 1.8em; font-weight: 700; display: block; }
        .h-bar { height: 6px; background: #e2e8f0; border-radius: 3px; margin-top: 10px; overflow: hidden; }
        .h-fill { height: 100%; transition: width 0.5s; }
        .tabs { display: flex; gap: 10px; margin-bottom: 20px; }
        .tab-btn { padding: 10px 20px; border: none; border-radius: 8px; cursor: pointer; font-weight: 600; background: #cbd5e1; }
        .tab-btn.active { background: var(--primary); color: white; }
        .tab-content { display: none; } .tab-content.active { display: block; }
        .todo-box { background: #fee2e2; border: 1px solid #fecaca; padding: 20px; border-radius: 12px; margin-bottom: 25px; }
        .cat-card { background: white; border-radius: 12px; padding: 20px; margin-bottom: 25px; }
        table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
        td { padding: 12px; border-bottom: 1px solid #f8fafc; }
        .badge { padding: 3px 10px; border-radius: 6px; font-size: 0.8em; font-weight: 700; }
        .badge-pass { background: #dcfce7; color: #166534; }
        .badge-fail { background: #fee2e2; color: #991b1b; }
        .raw-output { background: #0f172a; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; font-size: 0.8em; }
        .fix-container { background: #fffbeb; padding: 10px; border-radius: 6px; border: 1px solid #fef3c7; display: flex; justify-content: space-between; align-items: center; margin-top: 5px; }
        .copy-btn { background: #f59e0b; color: white; border: none; padding: 3px 6px; border-radius: 4px; cursor: pointer; }
    </style>
</head>
<body>
    <div class="container">
        <header style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
            <h1 style="margin:0;">🛡️ Rocky 9 Audit Dashboard V17</h1>
            <div class="tabs"><button id="btn-dash" class="tab-btn active" onclick="tab('dash')">Dashboard</button><button id="btn-evid" class="tab-btn" onclick="tab('evid')">Evidence</button><button id="btn-fix" class="tab-btn" onclick="tab('fix')" style="background:var(--warn); color:white;">⚡ Quick-Fix</button></div>
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
            <div class="health-card"><h4>Security</h4><span class="health-val" style="color:$([ "$SEC_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")">$SEC_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$SEC_PERC%; background:$([ "$SEC_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
            <div class="health-card"><h4>Network</h4><span class="health-val" style="color:$([ "$NET_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")">$NET_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$NET_PERC%; background:$([ "$NET_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
            <div class="health-card"><h4>System</h4><span class="health-val" style="color:$([ "$SYS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")">$SYS_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$SYS_PERC%; background:$([ "$SYS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
            <div class="health-card"><h4>CIS Audit</h4><span class="health-val" style="color:$([ "$CIS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")">$CIS_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$CIS_PERC%; background:$([ "$CIS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
        </div>

        <div id="dash" class="tab-content active">
            $([ "$FAILED_CHECKS" -gt 0 ] && echo "<div class='todo-box'><h3>⚠️ Actie Vereist ($FAILED_CHECKS)</h3>$TODO_HTML</div>")
            <div class="cat-card"><h3>🛡️ CIS & Hardening</h3><table><tbody>$CIS_HTML</tbody></table></div>
            <div class="cat-card"><h3>🔐 Security & Network</h3><table><tbody>$SEC_HTML $NET_HTML</tbody></table></div>
        </div>

        <div id="evid" class="tab-content">$EVIDENCE_HTML</div>
        <div id="fix" class="tab-content"><div class="cat-card"><h3>⚡ Quick-Fix Script</h3><p>Run dit op de server:</p><div class="raw-output" id="qfix">#!/bin/bash\n# Fix voor $HOSTNAME_SHORT\n\n$QUICK_FIX_CMDS\necho "Fixes toegepast!"</div><button class="tab-btn" style="margin-top:10px; background:var(--primary); color:white;" onclick="copyTo(document.getElementById('qfix').innerText)">Kopieer Script</button></div></div>
    </div>
    <script>
        function tab(n){document.querySelectorAll('.tab-content,.tab-btn').forEach(e=>e.classList.remove('active'));document.getElementById(n).classList.add('active');document.getElementById('btn-'+n).classList.add('active');}
        function copyTo(t){navigator.clipboard.writeText(t);alert('Gekopieerd!');}
    </script>
</body>
</html>
EOF

echo -e "\n${GREEN}Klaar! Rapport:${NC} $HTML_REPORT"

#!/bin/bash

# ==============================================================================
# POST-DEPLOYMENT VERIFICATIE DASHBOARD V30 
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

if command -v dnf &>/dev/null; then PKG_MGR="dnf"; elif command -v apt &>/dev/null; then PKG_MGR="apt"; else PKG_MGR="yum"; fi

# Variabelen voor HTML (Strikte 6-box scheiding)
CIS_HTML=""; SEC_HTML=""; NET_HTML=""; SYS_HTML=""; STOR_HTML=""; HARD_HTML=""; TODO_HTML=""; EVIDENCE_HTML=""; ONELINER_CMDS=""
TOTAL_CHECKS=0; PASSED_CHECKS=0; FAILED_CHECKS=0
SEC_P=0; SEC_T=0; NET_P=0; NET_T=0; SYS_P=0; SYS_T=0; CIS_P=0; CIS_T=0; STOR_P=0; STOR_T=0; HARD_P=0; HARD_T=0

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
        "CIS")       CIS_HTML+="$ROW"; ((CIS_T++)); [ "$status" == "OK" ] && ((CIS_P++)) ;;
        "Security")  SEC_HTML+="$ROW"; ((SEC_T++)); [ "$status" == "OK" ] && ((SEC_P++)) ;;
        "Network")   NET_HTML+="$ROW"; ((NET_T++)); [ "$status" == "OK" ] && ((NET_P++)) ;;
        "System")    SYS_HTML+="$ROW"; ((SYS_T++)); [ "$status" == "OK" ] && ((SYS_P++)) ;;
        "Storage")   STOR_HTML+="$ROW"; ((STOR_T++)); [ "$status" == "OK" ] && ((STOR_P++)) ;;
        "Hardening") HARD_HTML+="$ROW"; ((HARD_T++)); [ "$status" == "OK" ] && ((HARD_P++)) ;;
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

# --- 2. SECURITY & AGENTS (Inclusief Qemu) ---
echo -e "\n--- Checking Security & Mandatory Agents ---"
log_check "Security" "SELinux Status" "$([ "$(getenforce 2>/dev/null)" == "Enforcing" ] && echo "OK" || echo "FAIL")" "Is $(getenforce 2>/dev/null)" "sudo setenforce 1 && sudo sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" "$(sestatus 2>/dev/null)"
log_check "Security" "Firewall" "$(systemctl is-active --quiet firewalld && echo "OK" || echo "FAIL")" "Service active" "sudo systemctl enable --now firewalld" "$(systemctl status firewalld --no-pager)"
log_check "Security" "Sophos MDR" "$(systemctl is-active --quiet sophos-spl && echo "OK" || echo "FAIL")" "Service status" "sudo systemctl start sophos-spl" "$(systemctl status sophos-spl --no-pager 2>&1)"
log_check "Security" "Azure Arc" "$(azcmagent show 2>&1 | grep -iq "Connected" && echo "OK" || echo "FAIL")" "Verbonden" "sudo azcmagent connect" "$(azcmagent show 2>&1)"
if systemctl list-unit-files | grep -q qemu-guest-agent; then
    log_check "Security" "Qemu Agent" "$(systemctl is-active --quiet qemu-guest-agent && echo "OK" || echo "FAIL")" "Status" "sudo systemctl enable --now qemu-guest-agent" "$(systemctl status qemu-guest-agent --no-pager)"
else
    log_check "Security" "Qemu Agent" "FAIL" "Niet geïnstalleerd" "sudo $PKG_MGR install qemu-guest-agent -y" "Package missing"
fi

# --- 3. NETWORK CONNECTIVITY ---
echo -e "\n--- Checking Network Connectivity ---"
log_check "Network" "Hostname" "$([[ "$(hostnamectl --static)" =~ ^it2.* ]] && echo "OK" || echo "FAIL")" "$(hostname)" "sudo hostnamectl set-hostname it2-$(hostname)" "$(hostnamectl)"
for check in "google.com:Address:DNS Res" "$(hostname):Address:DNS Fwd" "$IP_ADDR:name =:DNS Rev"; do
    IFS=: read -r target pattern label <<< "$check"
    RAW_NS=$(nslookup "$target" 2>&1)
    if echo "$RAW_NS" | grep -q "$pattern"; then log_check "Network" "$label" "OK" "${label//DNS /} OK" "" "$RAW_NS"
    else log_check "Network" "$label" "FAIL" "${label//DNS /} failed" "" "$RAW_NS"; fi
done

# --- 4. SYSTEM MANAGEMENT (Maintenance only) ---
echo -e "\n--- Checking System Management ---"
if [ "$PKG_MGR" == "apt" ]; then
    RAW_UP=$(apt list --upgradable 2>/dev/null | wc -l); [ "$RAW_UP" -le 1 ] && log_check "System" "Updates" "OK" "Up-to-date" "" "No updates" || log_check "System" "Updates" "FAIL" "Updates beschikbaar" "sudo apt update && sudo apt upgrade -y" "Updates found"
else
    RAW_UP=$(dnf check-update); [ $? -eq 0 ] && log_check "System" "Updates" "OK" "Up-to-date" "" "$RAW_UP" || log_check "System" "Updates" "FAIL" "Updates beschikbaar" "sudo dnf update -y" "$RAW_UP"
fi
log_check "System" "Timezone" "OK" "$(timedatectl show -p Timezone --value 2>/dev/null)" "" "$(timedatectl)"
log_check "System" "NTP Sync" "$(timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q 'yes' && echo "OK" || echo "FAIL")" "Synced" "sudo systemctl restart chronyd" "$(timedatectl)"

# --- 5. STORAGE & FILE SYSTEMS (All disks from image_8f4326.png) ---
echo -e "\n--- Checking Storage & File Systems ---"
while read -r line; do
    MP=$(echo "$line" | awk '{print $6}'); USE=$(echo "$line" | awk '{print $5}' | tr -d '%')
    log_check "Storage" "Disk: $MP" "$([ "$USE" -lt 90 ] && echo "OK" || echo "FAIL")" "Usage: ${USE}%" "" "$(df -h "$MP")"
done < <(df -h | grep -vE '^Filesystem|tmpfs|cdrom|devtmpfs')

# --- 6. PARTITION HARDENING ---
echo -e "\n--- Checking Partition Hardening ---"
RAW_MOUNTS=$(findmnt -nl -o TARGET,OPTIONS)
log_check "Hardening" "TMP Security" "$(echo "$RAW_MOUNTS" | grep -q "/tmp.*noexec" && echo "OK" || echo "FAIL")" "noexec" "sudo mount -o remount,noexec /tmp" "$RAW_MOUNTS"
log_check "Hardening" "SHM Security" "$(echo "$RAW_MOUNTS" | grep -q "/dev/shm.*nodev" && echo "OK" || echo "FAIL")" "nodev" "sudo mount -o remount,nodev /dev/shm" "$RAW_MOUNTS"
log_check "Hardening" "VARTMP Security" "$(echo "$RAW_MOUNTS" | grep -q "/var/tmp.*nosuid" && echo "OK" || echo "FAIL")" "nosuid" "sudo mount -o remount,nosuid /var/tmp" "$RAW_MOUNTS"

# Procenten berekenen
calc_perc() { [ "$2" -eq 0 ] && echo "100" || echo $(( $1 * 100 / $2 )); }
SEC_PERC=$(calc_perc $SEC_P $SEC_T); NET_PERC=$(calc_perc $NET_P $NET_T); SYS_PERC=$(calc_perc $SYS_P $SYS_T); CIS_PERC=$(calc_perc $CIS_P $CIS_T); STOR_PERC=$(calc_perc $STOR_P $STOR_T); HARD_PERC=$(calc_perc $HARD_P $HARD_T)

# --- HTML GENERATIE ---
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="nl"><head><meta charset="UTF-8"><title>$OS_NAME Audit Dashboard</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
<style>
:root { --bg: #f8fafc; --card: #ffffff; --primary: #0f172a; --success: #22c55e; --fail: #ef4444; --warn: #f59e0b; }
body { font-family: 'Inter', sans-serif; background: var(--bg); color: #1e293b; padding: 20px; margin: 0; }
.container { max-width: 1100px; margin: auto; }
.sys-header { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; background: #fff; padding: 20px; border-radius: 12px; margin-bottom: 25px; border: 1px solid #e2e8f0; }
.sys-item strong { display: block; font-size: 0.75em; color: #64748b; text-transform: uppercase; }
.health-grid { display: grid; grid-template-columns: repeat(6, 1fr); gap: 10px; margin-bottom: 25px; }
.health-card { background: white; padding: 12px; border-radius: 12px; text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.health-val { font-size: 1.4em; font-weight: 700; display: block; margin-bottom: 4px; }
.h-bar { height: 5px; background: #e2e8f0; border-radius: 3px; overflow: hidden; }
.h-fill { height: 100%; }
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
.copy-btn { background: #f59e0b; color: white; border: none; padding: 3px 6px; border-radius: 4px; cursor: pointer; font-size: 0.8em; }
</style></head>
<body><div class="container">
<header style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
<h1 style="margin:0; font-size: 1.6em;">🛡️ $OS_NAME Audit Dashboard</h1>
<div class="tabs"><button id="btn-dash" class="tab-btn active" onclick="tab('dash')">Dashboard</button><button id="btn-evid" class="tab-btn" onclick="tab('evid')">Evidence</button><button id="btn-fix" class="tab-btn" onclick="tab('fix')" style="background:var(--warn); color:white;">⚡ Quick-Fix</button></div></header>
<div class="sys-header">
<div class="sys-item"><strong>Hostname</strong>$FQDN</div><div class="sys-item"><strong>IP Adres</strong>$IP_ADDR</div><div class="sys-item"><strong>OS Release</strong>$OS_NAME</div></div>
<div class="health-grid">
<div class="health-card"><h4>Security</h4><span class="health-val">$SEC_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$SEC_PERC%; background:$([ "$SEC_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
<div class="health-card"><h4>Network</h4><span class="health-val">$NET_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$NET_PERC%; background:$([ "$NET_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
<div class="health-card"><h4>System</h4><span class="health-val">$SYS_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$SYS_PERC%; background:$([ "$SYS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
<div class="health-card"><h4>Storage</h4><span class="health-val">$STOR_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$STOR_PERC%; background:$([ "$STOR_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
<div class="health-card"><h4>CIS</h4><span class="health-val">$CIS_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$CIS_PERC%; background:$([ "$CIS_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div>
<div class="health-card"><h4>Harden</h4><span class="health-val">$HARD_PERC%</span><div class="h-bar"><div class="h-fill" style="width:$HARD_PERC%; background:$([ "$HARD_PERC" -eq 100 ] && echo "var(--success)" || echo "var(--warn)")"></div></div></div></div>
<div id="dash" class="tab-content active">
$([ "$FAILED_CHECKS" -gt 0 ] && echo "<div class='todo-box'><h3>⚠️ Openstaande Actiepunten</h3>$TODO_HTML</div>")
<div class="cat-card"><div class="cat-header">🛡️ CIS Compliance Audit<span>$CIS_PERC%</span></div><table><tbody>$CIS_HTML</tbody></table></div>
<div class="cat-card"><div class="cat-header">🔐 Security & Agents<span>$SEC_PERC%</span></div><table><tbody>$SEC_HTML</tbody></table></div>
<div class="cat-card"><div class="cat-header">🌐 Network Connectivity<span>$NET_PERC%</span></div><table><tbody>$NET_HTML</tbody></table></div>
<div class="cat-card"><div class="cat-header">⚙️ System Management<span>$SYS_PERC%</span></div><table><tbody>$SYS_HTML</tbody></table></div>
<div class="cat-card"><div class="cat-header">💽 Storage & File Systems<span>$STOR_PERC%</span></div><table><tbody>$STOR_HTML</tbody></table></div>
<div class="cat-card"><div class="cat-header">🧱 Partition Hardening<span>$HARD_PERC%</span></div><table><tbody>$HARD_HTML</tbody></table></div></div>
<div id="evid" class="tab-content">$EVIDENCE_HTML</div>
<div id="fix" class="tab-content"><div class="cat-card"><h3>⚡ Oneliner Quick-Fix</h3><p style="font-size:0.9em;">Kopieer en plak onderstaande regel in je terminal:</p><div class="raw-output" id="oneliner-text" style="font-weight:bold; color:var(--warn);">$ONELINER_CMDS</div><button class="tab-btn" style="margin-top:15px; background:var(--primary); color:white;" onclick="copyTo(document.getElementById('oneliner-text').innerText)">Kopieer Oneliner</button></div></div></div>
<script>
function tab(n){document.querySelectorAll('.tab-content,.tab-btn').forEach(e=>e.classList.remove('active'));document.getElementById(n).classList.add('active');document.getElementById('btn-'+n).classList.add('active');}
function copyTo(t){navigator.clipboard.writeText(t);alert('Gekopieerd!');}
</script></body></html>
EOF

echo -e "\n${GREEN}Gereed! Rapport V30 gegenereerd:${NC} $HTML_REPORT"

# 🛡️ Server Verification Framework (SVF) - V32

Het **Server Verification Framework** is een enterprise-grade audit-oplossing voor Linux-omgevingen. Dit script stelt engineers in staat om binnen enkele seconden een volledige compliance-check en health-audit uit te voeren direct na de deployment van een server (Post-Deployment Validation).



---

## 📋 Overzicht
Het SVF-framework voert een non-destructieve audit uit en genereert een interactief, "self-contained" HTML5-dashboard. Het is ontworpen met een **Distro-Agnostische** architectuur, waardoor het naadloos functioneert op zowel RHEL-gebaseerde systemen (Rocky, Alma) als Debian-gebaseerde systemen (Ubuntu).

---

## 🏗️ De 6 Pilaren van de Audit

De audit is strikt onderverdeeld in zes logische secties, elk voorzien van een eigen **Health Card** en real-time statusindicatie:

| Module | Omschrijving | Focuspunten |
| :--- | :--- | :--- |
| **CIS Audit** | Hardening conform CIS-standaarden. | SSH Root login, auditd kernel rules, shadow file permissions. |
| **Security & Agents** | Validatie van beheer- en security agents. | SELinux, Firewall, Sophos MDR, Azure Arc, Qemu Guest Agent. |
| **Connectivity** | Netwerkintegriteit & DNS. | Dynamische DNS checks (Forward/Reverse/Resolution), Hostname. |
| **System Mgmt** | Onderhoud & Systeemstatus. | OS Updates (dnf/apt), Timezone, NTP Synchronisatie. |
| **Storage Audit** | Capaciteitsbeheer (Real-time). | Used / Total weergave per partitie (bijv. 5.2G / 150G). |
| **Hardening** | Kernel-level mount beveiliging. | Mount-vlaggen: noexec, nodev, nosuid verificatie. |

---

## 🛠️ Key Features

* **Universal Engine:** Automatische detectie van pakketbeheerders en service-managers (dnf, apt, yum, systemctl).
* **Oneliner Quick-Fix:** Een intelligent tabblad in het dashboard dat alle gedetecteerde fouten vertaalt naar één enkele copy-paste opdracht.
* **Tee-Proof Redirection:** De fix-oneliner maakt gebruik van tee-pipe logica om "Permission denied" fouten bij beveiligde systeembestanden te voorkomen.
* **Technical Evidence:** Volledige transparantie door de ruwe command-output (stdout/stderr) van elke check op te slaan in een apart tabblad.

---

## 🚀 Implementatie

### 1. Voorbereiding
Download het script naar de doelsever en verleen executie-rechten:
`chmod +x svf_v32.sh`

### 2. Uitvoering
Draai het framework met root-privileges en specificeer de lokale beheerder voor validatie:
`sudo ./svf_v32.sh <admin_user>`

---

## 📂 Rapportage & Output

Na voltooiing genereert het script een uniek bestand in de huidige map:
`report_<hostname>_<timestamp>.html`

* **Dashboard:** Visueel overzicht voor management en audit-trails.
* **Technical Evidence:** Gedetailleerde logs voor deep-dive engineering.
* **Quick-Fix:** Direct toepasbare oneliner voor het behalen van 100% compliance.

---

## 🔍 Technische Specificaties

* **Taal:** Bash (POSIX compliant)
* **UI:** HTML5 / CSS3 (Inter font-stack, responsief, geen externe dependencies)
* **Compatibiliteit:** Rocky Linux 8/9/10, RHEL 8+, Ubuntu 20.04+, Debian 11+
* **Dependencies:** nslookup, auditd, util-linux

---

## ⚖️ Licentie
Dit framework is ontwikkeld voor intern gebruik en optimalisatie van post-deployment workflows. Aanpassingen aan specifieke hardening-richtlijnen zijn toegestaan.

<#
.SYNOPSIS
    Generalize Windows Server 2025 (VEILIGE VERSIE)
.DESCRIPTION
    Dit script schoont het systeem op, stelt regio-instellingen in (NL),
    verwijdert Sophos ID's en start Sysprep.
    
    AANPASSING: Edge en WebView2 worden NIET verwijderd om crashes in Server 2025 te voorkomen.
    VERBOSITY: Uitgebreide logging toegevoegd.
#>

param(
    [switch]$SkipSophos,
    [switch]$SkipSysprep
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'

Clear-Host
Write-Host "`n==============================================" -ForegroundColor Cyan
Write-Host "   Windows Server 2025 Template Voorbereiding" -ForegroundColor Cyan
Write-Host "   Aangepast voor stabiliteit & Verbose logging" -ForegroundColor Cyan
Write-Host "==============================================`n" -ForegroundColor Cyan

# ---------------------------------------------------------
# STAP 1: Tijdelijke bestanden opruimen
# ---------------------------------------------------------
Write-Host "[1/6] Tijdelijke bestanden opruimen..." -ForegroundColor Yellow

# Windows Temp
Write-Host "      -> Bezig met legen van C:\Windows\Temp..." -ForegroundColor Gray
Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# User Temp (AppData)
Write-Host "      -> Bezig met legen van User Temp folders..." -ForegroundColor Gray
Remove-Item "$env:LOCALAPPDATA\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Windows Update Downloads (SoftwareDistribution)
Write-Host "      -> Bezig met legen van Windows Update cache..." -ForegroundColor Gray
Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "      KLAAR: Alle tijdelijke mappen zijn leeg." -ForegroundColor Green


# ---------------------------------------------------------
# STAP 2: Event Logs wissen
# ---------------------------------------------------------
Write-Host "`n[2/6] Event Logs wissen..." -ForegroundColor Yellow
Write-Host "      -> Alle Windows logboeken worden nu geleegd (Application, System, Security, etc)..." -ForegroundColor Gray

$logs = wevtutil el
foreach ($log in $logs) {
    # We onderdrukken foutmeldingen omdat sommige logs gelockt zijn door het systeem, dat is normaal.
    wevtutil cl "$log" 2>$null
}
Write-Host "      KLAAR: Logboeken zijn gewist." -ForegroundColor Green


# ---------------------------------------------------------
# STAP 3: Netwerk Reset
# ---------------------------------------------------------
Write-Host "`n[3/6] Netwerk instellingen resetten..." -ForegroundColor Yellow

Write-Host "      -> IP-adres vrijgeven (ipconfig /release)..." -ForegroundColor Gray
ipconfig /release *>$null

Write-Host "      -> DNS Cache flushen (ipconfig /flushdns)..." -ForegroundColor Gray
ipconfig /flushdns *>$null

Write-Host "      KLAAR: Netwerk is neutraal gemaakt." -ForegroundColor Green


# ---------------------------------------------------------
# STAP 4: Regio & Taal instellen
# ---------------------------------------------------------
Write-Host "`n[4/6] Regio & Taal instellen (NL Format, US-Int Keyboard)..." -ForegroundColor Yellow

try {
    # 1. Systeemlocatie voor non-unicode (legacy apps)
    Write-Host "      -> System Locale zetten op nl-NL..." -ForegroundColor Gray
    Set-WinSystemLocale -SystemLocale nl-NL

    # 2. Datumnotatie, tijd, valuta
    Write-Host "      -> Cultuur (datum/tijd/valuta) zetten op nl-NL..." -ForegroundColor Gray
    Set-Culture nl-NL

    # 3. Geo-ID (Locatie voor weer/nieuws etc) - 176 is Nederland
    Write-Host "      -> Geografische locatie zetten op Nederland (ID: 176)..." -ForegroundColor Gray
    Set-WinHomeLocation -GeoId 176

    # 4. Toetsenbord instellen
    Write-Host "      -> Toetsenbord instellen op US-International (QWERTY)..." -ForegroundColor Gray
    $LangList = New-WinUserLanguageList "en-US"
    $LangList[0].InputMethodTips.Clear()
    $LangList[0].InputMethodTips.Add("0409:00020409") # Code voor US-Int
    Set-WinUserLanguageList $LangList -Force

    # 5. Instellingen kopiëren naar Welcome Screen en Default User (voor nieuwe gebruikers)
    Write-Host "      -> Instellingen kopiëren naar Welcome Screen & Default User Profile..." -ForegroundColor Gray
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    # 6. Tijdzone
    Write-Host "      -> Tijdzone forceren op W. Europe Standard Time..." -ForegroundColor Gray
    Set-TimeZone -Id "W. Europe Standard Time"

    Write-Host "      KLAAR: Regio instellingen succesvol toegepast." -ForegroundColor Green
}
catch {
    Write-Host "      FOUT: Er ging iets mis met de regio instellingen: $_" -ForegroundColor Red
}


# ---------------------------------------------------------
# STAP 5: Sophos Identiteit verwijderen (indien aanwezig)
# ---------------------------------------------------------
if (-not $SkipSophos) {
    Write-Host "`n[5/6] Controleren op Sophos Endpoint..." -ForegroundColor Yellow

    $sophosServices = Get-Service -Name "Sophos*" -ErrorAction SilentlyContinue
    $sophosInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -like "*Sophos*" }

    if ($sophosServices -or $sophosInstalled) {
        Write-Host "      -> Sophos gedetecteerd. Services stoppen..." -ForegroundColor Gray
        if ($sophosServices) {
            $sophosServices | Stop-Service -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }

        $cleaned = $false
        
        # MCS Persist map verwijderen
        $persistPath = "$env:ProgramData\Sophos\Management Communications System\Endpoint\Persist"
        if (Test-Path $persistPath) {
            Remove-Item "$persistPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "      -> Verwijderd: MCS Persist folder (unieke ID)" -ForegroundColor Gray
            $cleaned = $true
        }

        # Machine ID file verwijderen
        $machineIdPath = "$env:ProgramData\Sophos\AutoUpdate\data\machine_ID.txt"
        if (Test-Path $machineIdPath) {
            Remove-Item $machineIdPath -Force -ErrorAction SilentlyContinue
            Write-Host "      -> Verwijderd: machine_ID.txt" -ForegroundColor Gray
            $cleaned = $true
        }

        # Register ID's verwijderen
        $regPath = "HKLM:\SOFTWARE\Sophos\Management Communications System\Endpoint"
        if ((Test-Path $regPath) -and (Get-ItemProperty $regPath -Name "Id" -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty $regPath -Name "Id" -Force -ErrorAction SilentlyContinue
            Write-Host "      -> Verwijderd: Register ID Value" -ForegroundColor Gray
            $cleaned = $true
        }

        if ($cleaned) {
            Write-Host "      KLAAR: Sophos is geneutraliseerd en zal zich opnieuw registreren na clone." -ForegroundColor Green
        } else {
            Write-Host "      LET OP: Sophos is geïnstalleerd maar geen unieke ID data gevonden." -ForegroundColor Yellow
        }
    } else {
        Write-Host "      -> Geen Sophos installatie gevonden. Stap overgeslagen." -ForegroundColor Gray
    }
} else {
    Write-Host "`n[5/6] Sophos cleanup overgeslagen (Parameter -SkipSophos gebruikt)." -ForegroundColor Gray
}


# ---------------------------------------------------------
# STAP 6: Sysprep Uitvoeren
# ---------------------------------------------------------
if (-not $SkipSysprep) {
    Write-Host "`n[6/6] Sysprep starten..." -ForegroundColor Yellow
    Write-Host "      LET OP: De server wordt afgesloten zodra Sysprep klaar is." -ForegroundColor Magenta
    Write-Host "      Commando: sysprep.exe /generalize /oobe /shutdown /mode:vm" -ForegroundColor Gray
    
    Start-Sleep -Seconds 3
    
    Start-Process "$env:SystemRoot\System32\Sysprep\sysprep.exe" `
        -ArgumentList "/generalize /oobe /shutdown /mode:vm" `
        -Wait
} else {
    Write-Host "`n[6/6] Sysprep overgeslagen (Parameter -SkipSysprep gebruikt)." -ForegroundColor Gray
    Write-Host "      Je kunt Sysprep later handmatig uitvoeren." -ForegroundColor Yellow
}

Write-Host "`nScript voltooid." -ForegroundColor Green

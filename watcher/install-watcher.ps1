# ---------------------------------------------------------------------------
# install-watcher.ps1
#
# JEDNORAZOVO nastaví, aby sa update-rates.ps1 spúšťal automaticky pri
# každom prihlásení do Windows, na pozadí (bez okna) — netreba už nikdy
# ručne otvárať PowerShell.
#
# Spusti tento skript RAZ (v tom istom priečinku ako update-rates.ps1):
#   pwsh .\install-watcher.ps1
#
# Ak treba niečo neskôr zmeniť (napr. iný interval kontroly), stačí upraviť
# update-rates.ps1 a tento inštalačný skript spustiť znova — naplánovanú
# úlohu len prepíše, nič sa nezduplikuje.
# ---------------------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "Tento skript potrebuje PowerShell 7+. Nainštaluj z https://aka.ms/powershell a spusti znova cez 'pwsh install-watcher.ps1'."
    exit 1
}

$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshCommand) {
    Write-Error "Nenašiel sa 'pwsh' (PowerShell 7). Nainštaluj z https://aka.ms/powershell."
    exit 1
}
$PwshPath = $pwshCommand.Source

$ScriptPath = Join-Path $PSScriptRoot "update-rates.ps1"
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Nenašiel sa update-rates.ps1 v priečinku '$PSScriptRoot'. Musí byť v tom istom priečinku ako tento inštalačný skript."
    exit 1
}

# Pre istotu odblokovať (keby bol súbor len teraz stiahnutý z internetu).
try { Unblock-File -Path $ScriptPath } catch {}

$TaskName = "ZmenarenWatcher"

$action = New-ScheduledTaskAction `
    -Execute $PwshPath `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

# "At LogOn" (nie "At Startup"): beží to v rámci prihláseného používateľa,
# takže fungujú aj Windows bublinkové upozornenia (tie potrebujú prihlásený
# pracovný stol) a netreba nikde ukladať heslo k účtu.
$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)  # bez časového limitu — má bežať stále

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Automaticky odosiela kurzy zo Zmenárne (Monetka) do Google Sheetu." `
        -Force `
        -ErrorAction Stop `
        | Out-Null
} catch {
    Write-Host ""
    Write-Host "CHYBA: Naplánovanú úlohu sa nepodarilo vytvoriť: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Najčastejšia príčina (aj keď je 'At LogOn' bez potreby hesla) je, že" -ForegroundColor Yellow
    Write-Host "tento Windows účet nemá právo vytvárať naplánované úlohy. Skús toto okno" -ForegroundColor Yellow
    Write-Host "zavrieť a otvoriť PowerShell 7 cez 'Spustiť ako správca' (pravý klik na" -ForegroundColor Yellow
    Write-Host "ikonu → Run as administrator), potom znova spusti:" -ForegroundColor Yellow
    Write-Host "  cd C:\zmenaren-watcher"
    Write-Host "  pwsh .\install-watcher.ps1"
    exit 1
}

Write-Host ""
Write-Host "Hotovo! Watcher je teraz nastavený, aby sa spúšťal automaticky."
Write-Host "- Spustí sa sám pri každom prihlásení do Windows, na pozadí bez okna."
Write-Host "- Nájdeš ho v Plánovači úloh Windows pod názvom '$TaskName'."
Write-Host "- Priebeh sa zapisuje do: $(Join-Path $PSScriptRoot 'watcher.log')"
Write-Host ""
Write-Host "Chceš ho spustiť hneď teraz (bez reštartu/odhlásenia)? Spusti:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"

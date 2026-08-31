# ---------------------------------------------------------------------------
# update-rates.ps1
#
# Sleduje priečinok, kam Monetka exportuje kurzový .txt súbor, a pri KAŽDEJ
# zmene (nie na časovač) rozparsuje kurzy a zapíše ich do Google Sheetu,
# odkiaľ si ich ťahá stránka index.html.
#
# STAV: zápisová časť (Write-RatesToGoogleSheet / Get-GoogleAccessToken) je
# hotová. Parsovacia časť (Parse-MonetkaExport) je zámerne prázdna, kým
# nemáme reálnu vzorku exportu z Monetky (formát stĺpcov, oddeľovač,
# kódovanie) — doplní sa hneď ako vzorka príde.
#
# POŽIADAVKA: PowerShell 7+ (podpisovanie JWT cez RSA.ImportFromPem, ktoré
# staršia Windows PowerShell 5.1 nemá). Skript sa spúšťa príkazom "pwsh", nie
# "powershell". PowerShell 7 je bezplatná inštalácia od Microsoftu, ktorá
# funguje popri 5.1 bez konfliktu: https://aka.ms/powershell
# ---------------------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "Tento skript potrebuje PowerShell 7+ (kvôli podpisovaniu JWT pre Google). Nainštaluj z https://aka.ms/powershell a spusti skript cez 'pwsh update-rates.ps1', nie cez 'powershell'."
    exit 1
}

# TODO: doplniť po vytvorení Google Cloud service accountu (JSON kľúč) —
# pozri README.md, časť "Google Cloud service account"
$ServiceAccountKeyPath = "C:\zmenaren-watcher\service-account.json"

# TODO: ID Google Sheetu (rovnaké ako CONFIG.SHEET_ID v index.html) + názov hárku
$SpreadsheetId = ""
$SheetName     = "Kurzy"

# TODO: presná cesta k priečinku/súboru, kam Monetka exportuje kurzy
$WatchFolder   = "C:\Monetka\Export"
$WatchFilter   = "*.txt"

function Parse-MonetkaExport {
    param([string]$FilePath)

    # TODO: doplniť po vzorke exportu. Očakávaný výstup — pole objektov:
    # @{ code = "USD"; buy = 1.100; sell = 1.060 }, ...
    # (buy/sell = koľko jednotiek danej meny dostanete za 1 EUR)
    #
    # Bežné veci na doriešiť podľa reálneho súboru:
    #  - oddeľovač (tabulátor / bodkočiarka / čiarka / pevná šírka stĺpcov)
    #  - kódovanie (často Windows-1250 pri slovenských/českých programoch)
    #  - smer nákup/predaj — over, že v Monetke platí rovnaká konvencia
    #    (nákup > predaj), inak tu stĺpce jednoducho prehodíme

    throw "Parse-MonetkaExport zatiaľ nie je implementované — čaká sa na vzorku exportu."
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

# Podpíše JWT service accountom a vymení ho za krátkodobý access token —
# štandardný Google "server-to-server" OAuth flow (bez prehliadača/používateľa).
function Get-GoogleAccessToken {
    param([string]$KeyPath)

    $key = Get-Content $KeyPath -Raw | ConvertFrom-Json
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $header = @{ alg = "RS256"; typ = "JWT" } | ConvertTo-Json -Compress
    $claims = @{
        iss   = $key.client_email
        scope = "https://www.googleapis.com/auth/spreadsheets"
        aud   = "https://oauth2.googleapis.com/token"
        iat   = $now
        exp   = $now + 3600
    } | ConvertTo-Json -Compress

    $headerB64 = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($header))
    $claimsB64 = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($claims))
    $signingInput = "$headerB64.$claimsB64"

    $rsa = [Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem($key.private_key)
    $signature = $rsa.SignData(
        [Text.Encoding]::UTF8.GetBytes($signingInput),
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $jwt = "$signingInput." + (ConvertTo-Base64Url $signature)

    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/token" -Body @{
        grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        assertion  = $jwt
    }
    return $tokenResponse.access_token
}

function Write-RatesToGoogleSheet {
    param([array]$Rates)

    if (-not $SpreadsheetId) {
        Write-Warning "SpreadsheetId nie je nastavené — kurzy sa nezapíšu."
        return
    }

    $accessToken = Get-GoogleAccessToken -KeyPath $ServiceAccountKeyPath
    $headers = @{ Authorization = "Bearer $accessToken" }

    # Sheet má stĺpce: Mena | Nakupujeme | Predávame | Nakup. predch. | Predaj predch.
    # Načítame CELÝ existujúci hárok a menu k riadku priradíme podľa stĺpca A
    # (kód meny) — nezávisí to teda od poradia, v akom Monetka kurzy exportuje,
    # ani od poradia riadkov v samotnom hárku.
    $range = "$SheetName!A2:E1000"
    $getUrl = "https://sheets.googleapis.com/v4/spreadsheets/$SpreadsheetId/values/$([uri]::EscapeDataString($range))"
    $existing = (Invoke-RestMethod -Uri $getUrl -Headers $headers -Method Get).values
    if (-not $existing) { $existing = @() }

    $updates = @()
    $nextNewRow = $existing.Count + 2  # hárok má dáta od riadku 2 (riadok 1 = hlavička)

    foreach ($r in $Rates) {
        $rowIndex = -1
        for ($i = 0; $i -lt $existing.Count; $i++) {
            if ($existing[$i][0] -eq $r.code) { $rowIndex = $i; break }
        }

        if ($rowIndex -ge 0) {
            $old = $existing[$rowIndex]
            # "predch." sa posunie len ak sa kurz oproti starému SKUTOČNE zmenil —
            # inak zostáva ukazovať poslednú reálnu zmenu, nie každý needitovaný zápis.
            $changed = ([double]$old[1] -ne $r.buy) -or ([double]$old[2] -ne $r.sell)
            $prevBuy  = if ($changed) { [double]$old[1] } else { [double]$old[3] }
            $prevSell = if ($changed) { [double]$old[2] } else { [double]$old[4] }
            $rowNum = $rowIndex + 2
        } else {
            # Mena, ktorá v hárku ešte nemá riadok — pridá sa na koniec bez histórie.
            $prevBuy = $r.buy
            $prevSell = $r.sell
            $rowNum = $nextNewRow
            $nextNewRow++
        }

        $updates += @{
            range  = "$SheetName!A${rowNum}:E${rowNum}"
            values = @(, @($r.code, $r.buy, $r.sell, $prevBuy, $prevSell))
        }
    }

    $body = @{ valueInputOption = "USER_ENTERED"; data = $updates } | ConvertTo-Json -Depth 6
    $batchUrl = "https://sheets.googleapis.com/v4/spreadsheets/$SpreadsheetId/values:batchUpdate"
    Invoke-RestMethod -Uri $batchUrl -Headers $headers -Method Post -Body $body -ContentType "application/json" | Out-Null

    Write-Host "Zapísaných $($Rates.Count) kurzov do Google Sheetu."
}

Write-Host "Sledujem priečinok: $WatchFolder (filter: $WatchFilter)"

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchFolder
$watcher.Filter = $WatchFilter
$watcher.EnableRaisingEvents = $true

$action = {
    param($source, $eventArgs)
    $path = $eventArgs.FullPath
    Write-Host "Zmena zaznamenaná: $path"
    try {
        Start-Sleep -Milliseconds 500  # počkať, kým Monetka dopíše súbor
        $rates = Parse-MonetkaExport -FilePath $path
        Write-RatesToGoogleSheet -Rates $rates
        Write-Host "Kurzy aktualizované."
    } catch {
        Write-Warning "Chyba pri spracovaní exportu: $_"
    }
}

Register-ObjectEvent $watcher "Changed" -Action $action | Out-Null
Register-ObjectEvent $watcher "Created" -Action $action | Out-Null

Write-Host "Watcher beží. Nechaj toto okno otvorené (alebo nastav ako službu/naplánovanú úlohu)."
while ($true) { Start-Sleep -Seconds 3600 }

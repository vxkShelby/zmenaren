# ---------------------------------------------------------------------------
# update-rates.ps1
#
# Pravidelne kontroluje, či sa zmenil čas poslednej úpravy kurzového exportu
# z Monetky, a pri zmene rozparsuje kurzy a zapíše ich do Google Sheetu,
# odkiaľ si ich ťahá stránka index.html.
#
# STAV: hotovo — zápis do Google Sheetu aj parsovanie exportu z Monetky
# (podľa vzorky "ExportKL.txt": kódovanie Windows-1250, stĺpce oddelené
# medzerami, formát Mena/Platnosť/Nákup/Predaj/...).
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
$SpreadsheetId = "19eNa65B_kWDJVdm5vUAcr42v4GoWZNabtgpjE0zLjgA"
$SheetName     = "Kurzy"

# Priečinok, kam Monetka exportuje kurzový lístok, a presný názov súboru.
$WatchFolder   = "C:\DatalockHotel\MonetkaEuro\Zmenaren\Import"
$WatchFilter   = "ExportKL.txt"

# Ako často (v sekundách) sa kontroluje, či sa súbor zmenil.
$PollIntervalSeconds = 10

# Rozparsuje kurzový lístok "ExportKL.txt" z Monetky. Reálna ukážka vyzerá takto:
#
#   Marta Medvecká - MARTA S|01.09.2026 09:23:39
#           Platnost   Nakup  Predaj  B.nak.  B.pre.   Stred  Devizy
#   USD    120260901   1.196   1.125   1.000   1.000   1.000   1.000
#   CZK    120260901  24.800  23.500   1.000   1.000   1.000   1.000
#   ...
#
# Prvé dva riadky (meno pokladníka/čas, popis stĺpcov) sa jednoducho preskočia —
# dátové riadky rozoznávame podľa toho, že prvé pole je presne 3-písmenový kód
# meny. Stĺpce sú oddelené medzerami (nie tabulátorom/bodkočiarkou), počet
# medzier sa líši (čísla sú zarovnané doprava na pevnú šírku), preto sa delí
# jednoducho podľa ľubovoľného počtu medzier za sebou.
#
# Nakup/Predaj = presne "Nakupujeme"/"Predávame" na stránke — Monetka používa
# rovnakú konvenciu (koľko jednotiek cudzej meny za 1 EUR, Nákup > Predaj),
# stĺpce sa teda NEMUSIA prehadzovať. Overené na CZK riadku (24,80 / 23,50 —
# presne reálny príklad z predajne).
#
# Súbor je vo Windows-1250 (nie UTF-8) — vidno to na "Medveck�" namiesto
# "Medvecká" vo vzorke, keby sa čítal ako UTF-8.
#
# Meny, ktoré sa momentálne neobchodujú (napr. DKK), má Monetka v exporte
# aj tak uvedené, ale s Nákup aj Predaj na 0 — také riadky sa zapíšu ako sú
# (0/0), stránka si ich sama zobrazí ako "–" namiesto "0,00".
function Parse-MonetkaExport {
    param([string]$FilePath)

    try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
    $encoding = [System.Text.Encoding]::GetEncoding(1250)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $lines = $encoding.GetString($bytes) -split "`r?`n"

    $rates = @()
    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line) { continue }

        $fields = $line -split '\s+'
        if ($fields.Count -lt 4) { continue }
        if ($fields[0] -notmatch '^[A-Za-z]{3}$') { continue }  # preskočí hlavičku/popis stĺpcov

        $code = $fields[0].ToUpper()
        $buy  = [double]::Parse($fields[2], [Globalization.CultureInfo]::InvariantCulture)
        $sell = [double]::Parse($fields[3], [Globalization.CultureInfo]::InvariantCulture)

        # Meny, ktoré sa momentálne neobchodujú, má Monetka v exporte s
        # nákupom aj predajom na 0 (napr. DKK) — také riadky sa zapíšu tak,
        # ako sú (0/0); index.html si ich sám zobrazí ako "–" namiesto "0,00",
        # nech mena ostane v lístku vidieť, len bez konkrétneho kurzu.
        if ($buy -eq 0 -and $sell -eq 0) {
            $rates += [PSCustomObject]@{ code = $code; buy = 0; sell = 0 }
            continue
        }

        if ($buy -lt $sell) {
            Write-Warning "$code`: Nakup ($buy) je nižšie ako Predaj ($sell) — over v Monetke, zvyčajne to má byť naopak. Zapisuje sa tak, ako je."
        }

        $rates += [PSCustomObject]@{ code = $code; buy = $buy; sell = $sell }
    }

    if ($rates.Count -eq 0) {
        throw "V súbore '$FilePath' sa nenašiel žiadny platný riadok s kurzom."
    }
    return $rates
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

$TargetFile = Join-Path $WatchFolder $WatchFilter

Write-Host "Sledujem súbor: $TargetFile (kontrola každých $PollIntervalSeconds s.)"
Write-Host "Watcher beží. Nechaj toto okno otvorené (alebo nastav ako naplánovanú úlohu)."

# Jednoduché a spoľahlivé riešenie: namiesto sledovania udalostí systému
# súborov (FileSystemWatcher) — to sa dá pokaziť antivírusom, spôsobom akým
# konkrétny program zapisuje súbor (dočasný súbor + premenovanie), alebo
# sieťovým diskom — sa jednoducho v pravidelnom intervale pozrie, či sa zmenil
# čas poslednej úpravy súboru. O pár sekúnd oneskorenia pri zmene kurzu nejde,
# funguje to ale vždy a rovnako, nech Monetka zapisuje akokoľvek.
$lastWriteTime = $null

while ($true) {
    try {
        if (Test-Path $TargetFile) {
            $currentWriteTime = (Get-Item $TargetFile).LastWriteTimeUtc
            if ($null -eq $lastWriteTime -or $currentWriteTime -ne $lastWriteTime) {
                $lastWriteTime = $currentWriteTime
                Write-Host "Zmena zaznamenaná: $TargetFile ($currentWriteTime UTC)"
                Start-Sleep -Milliseconds 500  # počkať, kým Monetka dopíše súbor
                $rates = Parse-MonetkaExport -FilePath $TargetFile
                Write-RatesToGoogleSheet -Rates $rates
                Write-Host "Kurzy aktualizované."
            }
        } else {
            Write-Warning "Súbor '$TargetFile' zatiaľ neexistuje."
        }
    } catch {
        Write-Warning "Chyba pri spracovaní exportu: $_"
    }
    Start-Sleep -Seconds $PollIntervalSeconds
}

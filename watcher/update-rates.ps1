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

# Súbor s priebežným záznamom (čo watcher robil/kedy) — užitočné najmä keď
# beží skryto na pozadí (naplánovaná úloha), keď nevidno žiadne okno.
$LogPath = Join-Path $PSScriptRoot "watcher.log"

# Windows bublinkové upozornenia (pri úspešnom odoslaní kurzov aj pri chybe).
# Nastav na $false, ak by boli nechcené/rušivé.
$ShowNotifications = $true

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
#
# Prvý riadok obsahuje aj čas, kedy Monetka kurzy naozaj vygenerovala
# ("...|01.09.2026 09:23:39") — to je presnejší zdroj pravdy pre "Aktualizované"
# na stránke ako čas súboru na disku (ten sa vie zmeniť aj bez zmeny kurzov)
# alebo čas spracovania vo watchri (ten by sa falošne posunul pri každom
# reštarte watchera). Vracia sa spolu s kurzami ako ExportTime — ak sa z
# nejakého dôvodu nenájde/nedá rozobrať, volajúci použije čas súboru ako zálohu.
function Parse-MonetkaExport {
    param([string]$FilePath)

    try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
    $encoding = [System.Text.Encoding]::GetEncoding(1250)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $lines = $encoding.GetString($bytes) -split "`r?`n"

    $rates = @()
    $exportTime = $null
    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line) { continue }

        if (-not $exportTime -and $line -match '\|(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2}):(\d{2})') {
            try {
                $exportTime = Get-Date -Year ([int]$Matches[3]) -Month ([int]$Matches[2]) -Day ([int]$Matches[1]) `
                                        -Hour ([int]$Matches[4]) -Minute ([int]$Matches[5]) -Second ([int]$Matches[6])
            } catch {
                $exportTime = $null
            }
            continue
        }

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
    return [PSCustomObject]@{ Rates = $rates; ExportTime = $exportTime }
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

# Podpíše JWT service accountom a vymení ho za krátkodobý access token —
# štandardný Google "server-to-server" OAuth flow (bez prehliadača/používateľa).
function Get-GoogleAccessToken {
    param([string]$KeyPath)

    if (-not (Test-Path $KeyPath)) {
        throw "Súbor s kľúčom service accountu '$KeyPath' neexistuje. Skontroluj presnú cestu a názov súboru."
    }
    $key = Get-Content $KeyPath -Raw | ConvertFrom-Json
    if (-not $key.private_key -or $key.private_key -notmatch '-----BEGIN PRIVATE KEY-----') {
        throw "Súbor '$KeyPath' sa načítal, ale pole 'private_key' je prázdne alebo poškodené (dĺžka: $($key.private_key.Length) znakov). Skús znova stiahnuť/uložiť JSON kľúč zo service accountu — nesmie sa preformátovať iným programom (napr. Word), len uložiť tak, ako je."
    }
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
    param([array]$Rates, [DateTime]$UpdateTimestampUtc = [DateTime]::UtcNow)

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
    # valueRenderOption=UNFORMATTED_VALUE — bez toho by Google vrátil čísla
    # naformátované podľa jazyka hárku (napr. "1,683" ako TEXT), čo pri
    # spätnom čítaní v PowerShelli (iné kultúrne nastavenie ako Sheet) mohlo
    # zle interpretovať čiarku/bodku a "prehltnúť" desatinnú časť.
    $range = "$SheetName!A2:E1000"
    $getUrl = "https://sheets.googleapis.com/v4/spreadsheets/$SpreadsheetId/values/$([uri]::EscapeDataString($range))?valueRenderOption=UNFORMATTED_VALUE"
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

    # Osobitný riadok s časom tejto (skutočnej) aktualizácie — na pevnom
    # riadku 20, s dostatočným odstupom od aktuálnych 12 mien, aby nekolidoval
    # ani pri pridaní pár ďalších mien do zoznamu. index.html ho vyčlení podľa
    # kódu "LAST_UPDATE" v stĺpci A a ukáže namiesto času vlastného fetchu,
    # nech "Aktualizované" na stránke ukazuje čas SKUTOČNEJ zmeny kurzu, nie
    # každé obnovenie stránky (tá si dáta ťahá každých 60 s, aj keď sa nič
    # nezmenilo). $UpdateTimestampUtc je čas, kedy Monetka kurzy naozaj
    # vygenerovala (z hlavičky exportu) — nie čas súboru na disku ani čas,
    # kedy to watcher spracoval, aby sa "Aktualizované" falošne neposúvalo pri
    # každom reštarte watchera.
    #
    # Kód aj časová značka idú do JEDNÉHO stĺpca A ("LAST_UPDATE|2026-09-01T...Z"),
    # NIE do A+B — stĺpec B má takmer vo všetkých riadkoch číslo (kurz), takže
    # Google Sheets "gviz" API (ktoré si stránka ťahá) si stĺpec B automaticky
    # odvodí ako číselný a text v ňom (dátum v tomto jedinom riadku) potichu
    # zahodí (vráti null) — stránka by tak nikdy nedostala platnú časovú
    # značku. Stĺpec A je vždy text (kódy mien), tam sa prenesie spoľahlivo.
    # Stĺpec B v tomto riadku sa vyprázdni, nech tam nestraší stará hodnota.
    # Samostatný zápis (nie súčasť dávky vyššie), nech je jednoduchý na
    # odladenie. valueInputOption=RAW = uloží sa vždy presne ako čistý text,
    # Google Sheets si to nebude "chytro" prekladať na dátum/číslo.
    $lastUpdateRange = "$SheetName!A20:B20"
    $lastUpdateUrl = "https://sheets.googleapis.com/v4/spreadsheets/$SpreadsheetId/values/$([uri]::EscapeDataString($lastUpdateRange))?valueInputOption=RAW"
    $lastUpdateValue = "LAST_UPDATE|$($UpdateTimestampUtc.ToString("yyyy-MM-ddTHH:mm:ssZ"))"
    $lastUpdateBody = @{ values = @(, @($lastUpdateValue, "")) } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Uri $lastUpdateUrl -Headers $headers -Method Put -Body $lastUpdateBody -ContentType "application/json" | Out-Null

    Write-Log "Zapísaných $($Rates.Count) kurzov do Google Sheetu."
}

# Vypíše do konzoly (ak nejaká je) a zároveň pripíše do watcher.log — keď
# beží skryto na pozadí, konzola nie je vidno, ale log súbor áno.
function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Write-Host $line
    # utf8BOM (nie obyčajné utf8) — BOM na začiatku súboru pomáha Poznámkovému
    # bloku aj iným editorom spoľahlivo rozoznať UTF-8, nech sa diakritika
    # nezobrazuje rozbitá.
    try { Add-Content -Path $LogPath -Value $line -Encoding utf8BOM } catch {}
}

# Windows bublinkové upozornenie pri paneli úloh. Ak beží skryto/bez
# prihláseného pracovného stola, jednoducho sa ticho preskočí (nepadne).
$script:NotifyIcon = $null
function Show-Notification {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")] [string]$Type = "Info"
    )
    if (-not $ShowNotifications) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        if (-not $script:NotifyIcon) {
            $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
            $script:NotifyIcon.Text = "Zmenáreň — watcher"
            $script:NotifyIcon.Visible = $true
        }
        $script:NotifyIcon.BalloonTipIcon = $Type
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Message
        $script:NotifyIcon.ShowBalloonTip(6000)
    } catch {
        # Notifikácie sa nedajú zobraziť (napr. beží bez prihláseného pracovného
        # stola) — nevadí, log súbor aj tak zaznamená, čo sa stalo.
    }
}

# Zostaví jednoduchý "odtlačok" kurzov (kód+nákup+predaj pre každú menu,
# zoradené), aby sa dalo spoľahlivo porovnať, či sa OBSAH naozaj zmenil —
# nielen čas súboru. Monetka totiž vie export znova uložiť aj bez toho, aby
# sa čokoľvek reálne zmenilo (napr. pravidelné automatické uloženie), a bez
# tohto porovnania by watcher pri každom takom uložení zbytočne zapisoval do
# Sheetu a "Aktualizované" na stránke by skákalo aj bez skutočnej zmeny kurzu.
function Get-RatesSnapshot {
    param([array]$Rates)
    ($Rates | Sort-Object code | ForEach-Object { "$($_.code)=$($_.buy),$($_.sell)" }) -join ";"
}

$TargetFile = Join-Path $WatchFolder $WatchFilter

Write-Log "Sledujem súbor: $TargetFile (kontrola každých $PollIntervalSeconds s.)"
Write-Log "Watcher beží."

# Jednoduché a spoľahlivé riešenie: namiesto sledovania udalostí systému
# súborov (FileSystemWatcher) — to sa dá pokaziť antivírusom, spôsobom akým
# konkrétny program zapisuje súbor (dočasný súbor + premenovanie), alebo
# sieťovým diskom — sa jednoducho v pravidelnom intervale pozrie, či sa zmenil
# čas poslednej úpravy súboru. O pár sekúnd oneskorenia pri zmene kurzu nejde,
# funguje to ale vždy a rovnako, nech Monetka zapisuje akokoľvek.
$lastWriteTime = $null
$lastRatesSnapshot = $null

while ($true) {
    try {
        if (Test-Path $TargetFile) {
            $currentWriteTime = (Get-Item $TargetFile).LastWriteTimeUtc
            if ($null -eq $lastWriteTime -or $currentWriteTime -ne $lastWriteTime) {
                $lastWriteTime = $currentWriteTime
                Start-Sleep -Milliseconds 500  # počkať, kým Monetka dopíše súbor
                $parsed = Parse-MonetkaExport -FilePath $TargetFile
                $rates = $parsed.Rates
                # Čas zo samotného exportu (Monetka) je spoľahlivejší než čas
                # súboru — ak sa z nejakého dôvodu nenašiel, čas súboru je záloha.
                $exportTimeUtc = if ($parsed.ExportTime) { $parsed.ExportTime.ToUniversalTime() } else { $currentWriteTime }
                $snapshot = Get-RatesSnapshot -Rates $rates

                if ($snapshot -ne $lastRatesSnapshot) {
                    Write-Log "Zmena kurzov zaznamenaná: $TargetFile (súbor: $currentWriteTime UTC, export: $exportTimeUtc UTC)"
                    Write-RatesToGoogleSheet -Rates $rates -UpdateTimestampUtc $exportTimeUtc
                    $lastRatesSnapshot = $snapshot
                    Write-Log "Kurzy aktualizované ($($rates.Count) mien)."
                    Show-Notification -Title "Zmenáreň" -Message "Kurzy boli úspešne odoslané ($($rates.Count) mien)." -Type Info
                } else {
                    Write-Log "Súbor sa síce znova uložil, ale kurzy sú rovnaké ako predtým — Sheet sa nezapisuje."
                }
            }
        } else {
            Write-Log "VAROVANIE: Súbor '$TargetFile' zatiaľ neexistuje."
        }
    } catch {
        Write-Log "CHYBA pri spracovaní exportu: $_"
        Show-Notification -Title "Zmenáreň — chyba" -Message "Kurzy sa nepodarilo aktualizovať: $_" -Type Error
    }
    Start-Sleep -Seconds $PollIntervalSeconds
}

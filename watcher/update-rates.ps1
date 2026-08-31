# ---------------------------------------------------------------------------
# update-rates.ps1
#
# Sleduje priečinok, kam Monetka exportuje kurzový .txt súbor, a pri KAŽDEJ
# zmene (nie na časovač) rozparsuje kurzy a zapíše ich do Google Sheetu,
# odkiaľ si ich ťahá stránka index.html.
#
# STAV: KOSTRA — parsovacia časť (Parse-MonetkaExport) je zámerne prázdna,
# kým nemáme reálnu vzorku exportu z Monetky (formát stĺpcov, oddeľovač,
# kódovanie). Doplní sa hneď ako vzorka príde.
# ---------------------------------------------------------------------------

# TODO: doplniť po vytvorení Google Cloud service accountu (JSON kľúč)
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

function Write-RatesToGoogleSheet {
    param([array]$Rates)

    # TODO: autentifikácia cez service account (JWT) + Google Sheets API v4.
    #
    # Sheet má stĺpce: Mena | Nakupujeme | Predávame | Nakup. predch. | Predaj predch.
    # Pri KAŽDOM zápise treba pre každú menu:
    #   1. GET aktuálny riadok zo Sheetu (staré Nakupujeme/Predávame)
    #   2. PUT nový riadok, kde:
    #        - Nakup. predch./Predaj predch. = stará hodnota z kroku 1
    #        - Nakupujeme/Predávame          = nová hodnota z Parse-MonetkaExport
    #      (ak sa kurz oproti starému nezmenil, "predch." sa netýka meniť —
    #       zostáva ukazovať poslednú SKUTOČNÚ zmenu, nie každý needitovaný zápis)
    #   PUT https://sheets.googleapis.com/v4/spreadsheets/{id}/values/{range}
    #   s telom { "values": [ ["USD", 1.100, 1.060, 1.100, 1.060], ... ] }
    #
    # Zámerne nechávam ako TODO — doplní sa spolu s krokom "vytvoriť service account"
    # v README.md (jednorazové nastavenie v Google Cloud Console).

    Write-Host "TODO: zápis do Google Sheetu zatiaľ nie je implementovaný."
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

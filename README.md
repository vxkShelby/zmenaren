# Zmenáreň OC Laugaricio — automatický kurzový lístok

Cieľ projektu: kurzy vyexportované z programu **Monetka** sa majú automaticky
objaviť na stránke `zmenaren` na `oclaugaricio.sk`, bez ručného prepisovania.

## Otváracia doba a živý status (Otvorené / Čoskoro zatvárame / Zatvorené)

`index.html` zobrazuje v hlavičke okrem "PO–NE 10:00–19:00" aj štítok, ktorý sa
sám prepína podľa aktuálneho času **v Trenčíne** (časové pásmo Europe/Bratislava,
nezávisí od toho, kde je návštevník stránky). Logika je v `<script>` bloku pod
`REGULAR_HOURS`.

**Ako pridať deň, keď má OC Laugaricio zatvorené (sviatok):**
Doplň riadok do `HOLIDAY_CLOSURES` v `index.html`, napr.:
```js
const HOLIDAY_CLOSURES = [
  { date: "2026-12-25", label: "1. sviatok vianočný" },
];
```
Pozor — nie je to automatické podľa slovenského kalendára, pridávajú sa len tie
dni, kedy má **OC Laugaricio reálne zatvorené** (potvrdiť s vedením OC).

**Ako nahlásiť mimoriadne/neplánované zatvorenie** (napr. dovolenka, choroba):
Doplň riadok do `MANUAL_CLOSURES` s dnešným/budúcim dátumom:
```js
const MANUAL_CLOSURES = [
  { date: "2026-09-05", note: "Dnes mimoriadne zatvorené" },
];
```
Po skončení zatvorenia riadok zmaž alebo zakomentuj.

Toto vieš upraviť aj sama/sám priamo v repozitári na GitHube (Edit ✏️ pri
súbore `index.html` → uložiť → GitHub Pages sa aktualizuje do minúty), alebo mi
jednoducho napíš dátum a dôvod a doplním to za teba.

*(Neskôr, keď bude zapojený Google Sheet na kurzy, sa dá tou istou cestou
presunúť aj otváracia doba/zatvorenia do Sheetu — vtedy by šlo upravovať úplne
bez zásahu do kódu, len zaškrtnutím v tabuľke.)*

## Logo

V `assets/logo/` je nové logo — monogram "Z" poskladaný z dvoch šípok (číta sa
súčasne ako písmeno Z aj ako obojsmerná výmena/zmena), navy + krémová +
mosadzná paleta, wordmark v type Big Shoulders. Súbory majú priehľadné pozadie
(PNG, 2000 px, pripravené na tlač aj web):

- `icon-ink.png` / `icon-cream.png` — samotný monogram (na svetlé / na tmavé pozadie)
- `logo-horizontal-ink.png` / `logo-horizontal-cream.png` — monogram + nápis "ZMENÁREŇ TRENČÍN"

Použitie: nahradiť placeholder `logo-white.png` na oclaugaricio.sk (skúsiť
`logo-horizontal-cream.png`, keďže pôvodný súbor mal v názve "white" — teda
zrejme tmavé/farebné pozadie za logom), profilovka na Facebooku
(`icon-ink.png` alebo `icon-cream.png` podľa pozadia), prípadne tlačoviny.
Monogram je od verzie s Facebook odkazom aj priamo v hlavičke `index.html`.

**Ďalšie varianty na výber** (rovnaký monogram, iné spracovanie):

- `variant-a-serif-*.png` — "Zmenáreň" sadzba v serife Ibarra Real Nova
  (rovnaký font ako má OC Laugaricio na webe)
- `variant-b-cobrand-*.png` — monogram + "ZMENÁREŇ" + deliaca čiara +
  "OC LAUGARICIO", navy/mosadzná paleta
- `variant-c-laugaricio-colors.png` — ako "b", ale s reálnou červeno-oranžovou
  paletou OC Laugaricio (podľa fotiek exteriéru/loga)
- `variant-d-twotone.png` / `variant-d-twotone-icon.png` — monogram v dvoch
  farbách naraz (horná šípka červená, dolná oranžová) — obe farby OC
  Laugaricio priamo v značke, najvýraznejší variant
- `variant-e-rounded.png` — mäkšie zaoblené hrany monogramu, navy/mosadz,
  jemnejší/prémiovejší dojem
- `variant-f-mono-red.png` — celé jednofarebné (červené), najlepšie na
  jednofarebnú tlač/vývesný štít z diaľky
- `variant-g-medallion.png` / `variant-g-medallion-mono.png` — komplexnejšia
  "medaila"/pečať: ryhovaný mincový okraj, "ZMENÁREŇ" a "OC LAUGARICIO ·
  TRENČÍN" po obvode, dvojfarebný monogram v strede. Mono verzia (jedna
  farba) je pre pečiatku/rytie/gravírovanie alebo tlač na tmavé pozadie.

**Verzia so symbolom €** (namiesto monogramu "Z" — vlastná geometrická
kresba €, nie len písmo z fontu, nech štýlovo sedí s ostatným):

- `euro-icon-ink.png` / `euro-icon-cream.png` — samotný € symbol
- `euro-logo-horizontal-ink.png` / `euro-logo-horizontal-cream.png` — € + "ZMENÁREŇ TRENČÍN"
- `euro-twotone-icon.png` / `euro-twotone-lockup.png` — € v dvoch farbách
  OC Laugaricio (horný oblúk+priečka červená, dolný oranžová)

Hlavička `index.html` teraz používa tento € symbol (namiesto pôvodného Z).

Odporúčanie: **variant D** (dvojfarebný) najviac spája vlastnú identitu s
OC Laugaricio a je najuniverzálnejší na bežné použitie (web, FB, vizitky);
**variant G** (medaila) je najkomplexnejší/najslávnostnejší — vhodný ako
"pečať" na vývesný štít, tabuľu s kurzami, alebo vizitku, kde je priestor
na detail; **variant B** (navy/mosadz) je najneutrálnejší, ak logo bude
žiť aj úplne mimo OC Laugaricio.

## Ako to funguje (celý reťazec)

```
Monetka (.txt export)
        │  (watcher sleduje priečinok, reaguje na zmenu súboru)
        ▼
watcher/update-rates.ps1   (beží na PC v predajni, Windows)
        │  (zápis cez Google Sheets API)
        ▼
Google Sheet "Kurzy"        (voľne dostupná "databáza" kurzov, zadarmo)
        │  (číta sa cez verejný gviz JSON endpoint)
        ▼
index.html (táto stránka, GitHub Pages)   ← https://vxkshelby.github.io/zmenaren/
        │  (vložené ako iframe)
        ▼
oclaugaricio.sk/obchody-a-restauracie/zmenaren/
```

Zmenáreň nepotrebuje žiadny prístup do WordPressu OC Laugaricio. OC potrebuje
spraviť jedinú vec: raz vložiť `<iframe>` odkazujúci na GitHub Pages URL
(pozri nižšie). Odvtedy sa stránka aktualizuje sama — vy meníte kurzy/dizajn
tu v repozitári, GitHub to automaticky nasadí, iframe to hneď zobrazí.

## Stav projektu

- [x] `index.html` — vizuál kurzového lístka, s ukážkovými dátami kým nie je
      napojený Google Sheet (bezpečné na náhľad hneď teraz)
- [x] `watcher/update-rates.ps1` — watcher hotový vrátane zápisu do Google
      Sheetu (`Write-RatesToGoogleSheet` cez service account JWT);
      **parsovacia časť (`Parse-MonetkaExport`) čaká na vzorku exportu**
- [x] Zapnúť GitHub Pages pre tento repozitár — **hotovo, živé na
      https://vxkshelby.github.io/zmenaren/** (repozitár bolo treba
      najprv zverejniť — GitHub Pages na súkromnom repozitári vyžaduje
      platený plán). Zatiaľ nasadené z branchu
      `claude/code-sync-across-devices-fyd65x`, nie `main` — pozn. nižšie.
- [ ] Vytvoriť Google Sheet (krok 1 nižšie) + Google Cloud service account
      (krok 2 nižšie) — obe treba spraviť ty, keďže vyžadujú tvoj Google účet
- [ ] Vzorka `.txt` exportu z Monetky → doplní sa parser (krok 3 nižšie)
- [ ] Poslať vedeniu OC Laugaricio embed kód (nižšie)

## Čo treba doplniť — krok za krokom

### 1. Google Sheet
Vytvoriť Google Sheet s hárkom (napr. `Kurzy`) v tvare — riadok pre každú
obchodovanú menu (základná mena je EUR, tá sa neuvádza ako riadok).

**Konvencia: koľko jednotiek cudzej meny dostanete za 1 EUR.** `Nakupujeme`
je preto vždy vyššie číslo ako `Predávame` (zmenáreň si tak necháva maržu) —
presne ako v reálnom príklade z predajne: CZK 24,80 (nákup) / 23,50 (predaj).

Posledné dva stĺpce (`Nakup. predch.` / `Predaj predch.`) sú hodnoty **pred**
poslednou zmenou — z nich si `index.html` dopočíta stĺpec "Zmena" (▲/▼ oproti
poslednému kurzu). Watcher pri každom zápise najprv presunie aktuálnu hodnotu
do týchto dvoch stĺpcov a až potom zapíše nový kurz do `Nakupujeme`/`Predávame`.

| Mena | Nakupujeme | Predávame | Nakup. predch. | Predaj predch. |
|------|-----------:|----------:|----------------:|----------------:|
| AUD  | 1.680      | 1.620     | 1.665            | 1.605            |
| USD  | 1.100      | 1.060     | 1.100            | 1.060            |
| CAD  | 1.510      | 1.450     | 1.525            | 1.465            |
| CZK  | 24.80      | 23.50     | 24.75            | 23.45            |
| GBP  | 0.870      | 0.840     | 0.870            | 0.840            |
| HUF  | 402.0      | 388.0     | 405.0            | 391.0            |
| CHF  | 0.945      | 0.915     | 0.938            | 0.908            |
| PLN  | 4.350      | 4.210     | 4.350            | 4.210            |
| RON  | 5.050      | 4.910     | 5.060            | 4.920            |
| DKK  | 7.550      | 7.350     | 7.540            | 7.340            |
| SEK  | 11.500     | 11.000    | 11.550           | 11.050           |
| NOK  | 11.700     | 11.200    | 11.680           | 11.180           |

(Toto sú len ilustračné čísla na overenie formátu — reálne hodnoty pôjdu
priamo z Monetky, takže presnosť/zaokrúhľovanie sa napokon riadi tým, čo
exportuje ona.)

Zdieľať ho ako **"Ktokoľvek s odkazom — Zobrazovať"**, nech ho `index.html`
vie čítať. ID hárku (z URL) sa potom doplní do `CONFIG.SHEET_ID`
v `index.html` a do `$SpreadsheetId` v `watcher/update-rates.ps1`.

### 2. Google Cloud service account (na zápis z watchera) — hotovo v kóde ✅
Zápisová časť (`Write-RatesToGoogleSheet` v `watcher/update-rates.ps1`) je už
naprogramovaná — funguje bez ohľadu na to, aký formát nakoniec bude mať
Monetka export (to sa doplní do `Parse-MonetkaExport` samostatne, viď krok 3).
Aby fungovala, treba raz nastaviť service account v Google Cloud Console —
je to bezplatné, žiadna platobná karta sa nevyžaduje:

1. Choď na **console.cloud.google.com** → hore vytvor nový projekt (napr.
   "zmenaren-watcher").
2. V hľadaní hore napíš **"Google Sheets API"** → otvor ju → **Enable**.
3. V ľavom menu **APIs & Services → Credentials** → **Create Credentials**
   → **Service account**. Zadaj ľubovoľné meno (napr. "zmenaren-writer") →
   **Create and continue** → **Done** (role netreba riešiť, pridáme ho
   priamo k Sheetu v kroku nižšie).
4. Klikni na novovytvorený service account → záložka **Keys** → **Add key**
   → **Create new key** → typ **JSON** → **Create**. Stiahne sa `.json`
   súbor — **toto je jediný krok, kde vzniká tajný kľúč**, nedá sa stiahnuť
   druhýkrát (dá sa len vytvoriť nový).
5. Súbor premenuj podľa potreby a ulož na PC v predajni presne na cestu,
   akú má `$ServiceAccountKeyPath` v `update-rates.ps1` (predvolene
   `C:\zmenaren-watcher\service-account.json`). **Tento súbor sa nikdy
   nedáva do GitHub repozitára** (je to citlivý prístupový kľúč).
6. V tom JSON súbore nájdeš pole `"client_email"` (vyzerá ako
   `xxxxx@zmenaren-watcher.iam.gserviceaccount.com`) — tento e-mail pridaj
   ako **Editor** (zdieľať) priamo do Google Sheetu z kroku 1 (rovnako, ako
   by si zdieľal Sheet s kolegom).

Skript na zápis vyžaduje **PowerShell 7+** (kvôli podpisovaniu prístupu
k Google) — treba ho na PC v predajni nainštalovať z
[aka.ms/powershell](https://aka.ms/powershell) (bezplatné, funguje popri
existujúcej Windows PowerShell 5.1 bez konfliktu) a skript spúšťať príkazom
`pwsh update-rates.ps1`, nie cez staršie `powershell.exe`.

### 3. Vzorka exportu z Monetky
Potrebné, aby sa dala doplniť funkcia `Parse-MonetkaExport` v
`watcher/update-rates.ps1` — hlavne oddeľovač stĺpcov, kódovanie
(pravdepodobne Windows-1250) a presné poradie/formát hodnôt. Zároveň
overíme, či Monetka exportuje kurzy v rovnakej konvencii ("cudzia mena za
1 EUR", nákup > predaj) — ak nie, watcher pri zápise do Sheetu len
prehodí/prepočíta stĺpce, na `index.html` sa nič meniť nemusí.

### 4. GitHub Pages — hotovo ✅
Živé na **https://vxkshelby.github.io/zmenaren/**. Repozitár musel byť najprv
zverejnený (Settings → General → Danger Zone → Change visibility → Public) —
GitHub Pages na súkromnom repozitári vyžaduje platený plán (GitHub Pro),
na verejnom je úplne zadarmo bez akéhokoľvek časového obmedzenia.

Momentálne je zdroj nastavený na branch `claude/code-sync-across-devices-fyd65x`
(Settings → Pages → Branch). Až budú zmeny hotové a overené, dá sa v tom istom
nastavení prepnúť zdroj na `main`, prípadne najprv branch zmergovať do `main`.

### 5. Embed kód pre OC Laugaricio
Toto pošlete webmasterovi OC Laugaricio nech vloží do WordPressu (Custom
HTML blok) na stránku Zmenáreň:

```html
<iframe
  src="https://vxkshelby.github.io/zmenaren/"
  style="width:100%; max-width:1000px; height:1900px; border:0; display:block; margin:0 auto;"
  title="Aktuálny kurzový lístok — Zmenáreň OC Laugaricio">
</iframe>
```

Stránka je responzívna — pri šírke iframu nad ~660px sa kalkulačka zobrazí
vedľa tabuľky (nižší, širší layout, cca 1850px výšky pri šírke 1000px), pod
touto hranicou sa sama poskladá pod tabuľku pre mobil (vyšší layout, cca
2450px). Výška `1900px` vyššie počíta so širším desktopovým zobrazením —
ak pôjde iframe zobrazovať aj na užších mobilných šírkach OC stránky, treba
počítať s vyššou hodnotou (cca `2500px`) alebo požiadať webmastera o
automatické prispôsobenie výšky JavaScriptom (`postMessage`/`iframe-resizer`),
čo je čistejšie riešenie ako pevná výška — vieme doplniť, ak bude treba.

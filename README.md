# Zmenáreň OC Laugaricio — automatický kurzový lístok

Cieľ projektu: kurzy vyexportované z programu **Monetka** sa majú automaticky
objaviť na stránke `zmenaren` na `oclaugaricio.sk`, bez ručného prepisovania.

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
index.html (táto stránka, GitHub Pages)   ← https://<username>.github.io/zmenaren/
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
- [x] `watcher/update-rates.ps1` — kostra watchera, reaguje na zmenu súboru
      (nie na časovač); **parsovacia časť čaká na vzorku exportu z Monetky**
- [ ] Vzorka `.txt` exportu z Monetky → doplní sa parser
- [ ] Vytvoriť Google Sheet + Google Cloud service account (zápis do hárku)
- [ ] Zapnúť GitHub Pages pre tento repozitár (Settings → Pages)
- [ ] Poslať vedeniu OC Laugaricio embed kód (nižšie)

## Čo treba doplniť — krok za krokom

### 1. Google Sheet
Vytvoriť Google Sheet s hárkom (napr. `Kurzy`) v tvare — riadok pre každú
obchodovanú menu (základná mena je EUR, tá sa neuvádza ako riadok).

**Konvencia: koľko jednotiek cudzej meny dostanete za 1 EUR.** `Nakupujeme`
je preto vždy vyššie číslo ako `Predávame` (zmenáreň si tak necháva maržu) —
presne ako v reálnom príklade z predajne: CZK 24,80 (nákup) / 23,50 (predaj).

| Mena | Nakupujeme | Predávame |
|------|-----------:|----------:|
| AUD  | 1.680      | 1.620     |
| USD  | 1.100      | 1.060     |
| CAD  | 1.510      | 1.450     |
| CZK  | 24.80      | 23.50     |
| GBP  | 0.870      | 0.840     |
| HUF  | 402.0      | 388.0     |
| CHF  | 0.945      | 0.915     |
| PLN  | 4.350      | 4.210     |
| RON  | 5.050      | 4.910     |
| BGN  | 2.000      | 1.865     |
| DKK  | 7.550      | 7.350     |
| SEK  | 11.500     | 11.000    |

(Toto sú len ilustračné čísla na overenie formátu — reálne hodnoty pôjdu
priamo z Monetky, takže presnosť/zaokrúhľovanie sa napokon riadi tým, čo
exportuje ona.)

Zdieľať ho ako **"Ktokoľvek s odkazom — Zobrazovať"**, nech ho `index.html`
vie čítať. ID hárku (z URL) sa potom doplní do `CONFIG.SHEET_ID`
v `index.html` a do `$SpreadsheetId` v `watcher/update-rates.ps1`.

### 2. Google Cloud service account (na zápis z watchera)
Jednorazové nastavenie v Google Cloud Console — vytvoriť projekt, zapnúť
Google Sheets API, vytvoriť service account a stiahnuť JSON kľúč. Tento účet
sa potom pridá ako editor k Google Sheetu z kroku 1. Toto doplníme spolu,
keď bude parser hotový.

### 3. Vzorka exportu z Monetky
Potrebné, aby sa dala doplniť funkcia `Parse-MonetkaExport` v
`watcher/update-rates.ps1` — hlavne oddeľovač stĺpcov, kódovanie
(pravdepodobne Windows-1250) a presné poradie/formát hodnôt. Zároveň
overíme, či Monetka exportuje kurzy v rovnakej konvencii ("cudzia mena za
1 EUR", nákup > predaj) — ak nie, watcher pri zápise do Sheetu len
prehodí/prepočíta stĺpce, na `index.html` sa nič meniť nemusí.

### 4. Zapnúť GitHub Pages
V nastaveniach repozitára: **Settings → Pages → Source: Deploy from a
branch → main → / (root)**. Po uložení bude stránka dostupná na
`https://<username>.github.io/zmenaren/`.

### 5. Embed kód pre OC Laugaricio
Toto pošlete webmasterovi OC Laugaricio nech vloží do WordPressu (Custom
HTML blok) na stránku Zmenáreň:

```html
<iframe
  src="https://<username>.github.io/zmenaren/"
  style="width:100%; max-width:640px; height:520px; border:0; display:block; margin:0 auto;"
  title="Aktuálny kurzový lístok — Zmenáreň OC Laugaricio">
</iframe>
```

(Výšku `520px` doladíme podľa reálneho obsahu, keď bude nasadené.)

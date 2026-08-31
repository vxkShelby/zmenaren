# Zmenáreň OC Laugaricio — automatický kurzový lístok

Cieľ projektu: kurzy vyexportované z programu **Monetka** sa majú automaticky
objaviť na stránke `zmenaren` na `oclaugaricio.sk`, bez ručného prepisovania.

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
obchodovanú menu (základná mena je EUR, tá sa neuvádza ako riadok):

| Mena | Jednotka | Nákup | Predaj |
|------|----------|-------|--------|
| AUD  | 1        | 0.600 | 0.580  |
| USD  | 1        | 1.070 | 1.055  |
| CAD  | 1        | 0.760 | 0.740  |
| CZK  | 100      | 4.020 | 3.940  |
| GBP  | 1        | 1.180 | 1.155  |
| HUF  | 100      | 0.252 | 0.245  |
| CHF  | 1        | 1.045 | 1.020  |
| PLN  | 1        | 0.234 | 0.228  |
| RON  | 1        | 0.200 | 0.192  |

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
(pravdepodobne Windows-1250) a presné poradie/formát hodnôt.

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

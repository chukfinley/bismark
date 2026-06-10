# Bismark Wasser — Preis-Wächter

Eine App mit **einem Job**: für **Fürst Bismarck Mineralwasser Still 12×0,75 l**
(Glas-Mehrwegkasten) zeigen, **wo es in der Nähe gerade am günstigsten / reduziert**
ist — über alle Läden rund um Kiel. App auf → günstigsten Markt sehen → antippen →
Route in der Karten-App → hinfahren.

Zielprodukt: REWE-Artikel-ID **`8016195`**, Marke Fürst Bismarck Quelle
(Aumühle/Reinbek, gehört Refresco). Pfand Glas-Kasten: **3,30 €** (Rückgeld, kein
Teil des Warenpreises).

---

## Datenquellen (alles direkt per HTTP/JSON, kein eigenes Backend)

### 1. REWE — voller Live-Preis pro Markt ✅
Öffentliche JSON-API, **kein Cloudflare**:

```
GET https://www.rewe.de/api/stationary-product-search/products
      ?query=<text>&wwIdent=<marktID>
```
- `query` muss **Text** sein (nicht die Artikel-ID), z. B. `Fürst Bismarck Still 12x0,75l`.
- `wwIdent` = REWE-Markt-ID.
- Antwort: `products[].pricing = { current, regular, refund, grammage }` in **Cent**.
- **reduziert** := `current < regular`.  **Gesamt** := `current + refund`.
- Produkt per `id == "8016195"` rausfiltern. Fehlt es → nicht im Sortiment des Markts.
- Liefert **Alltags- UND Angebotspreis** je Filiale. Einzige Quelle mit Regalpreis.

> Achtung: Die **Produkt-Seite** `rewe.de/produkte/...` und der Marktwähler sind
> Cloudflare-/WAF-geschützt (Turnstile) — nur mit echtem (headed) Browser passierbar.
> Die `stationary-product-search`-API ist es **nicht**. Darum nutzen wir nur die API.
> (Früher genutzter Cookie-Trick: HttpOnly `wksMarketsCookie =
> {"stationary":{"wwIdent":<ID>,...}}`, URL-encodiert — nur für die Produktseite nötig.)

### 2. marktguru — Wochenangebote ALLER Ketten ✅
Aggregator für Prospekt-/Angebotspreise (Edeka, Kaufland, famila, Netto, Getränke
Hoffmann, Markant …). **kein Cloudflare**:

```
GET https://api.marktguru.de/api/v1/offers/search
      ?as=mobile&limit=40&q=Fürst%20Bismarck&zipCode=<plz>
Header:
  X-Apikey:    8Kk+pmbf7TgJ9nVj2cXeA7P5zBGv8iuutVVMRfOfvNE=
  X-Clientkey: QPJfH1Fq7Uw7CaEYQtpf2hcWqE+JgwRT6BY2ILqIUMU=
```
- Keys sind die öffentlichen Web-/App-Keys (aus dem Autocomplete-Call
  `/api/v1/search/suggestions` auf marktguru.de abgegriffen; können rotieren).
- Antwort: `results[]` mit `description` ("Classic, Medium oder Still 12 x 0,75 l Glas
  + Pfand 3,30 €"), `price` (Ware), `oldPrice`, `referencePrice` (€/l), `volume`,
  `quantity`, `validityDates[{from,to}]`, `advertisers[{name}]` (Kette, **nicht**
  Filiale), `brand`.
- Angebot gilt **kettenweit** in der Nähe der PLZ, nicht pro Filiale → in der App dem
  **nächstgelegenen Markt dieser Kette** zugeordnet.
- Beispiel live um Kiel: EDEKA 5,99 €, Getränke Hoffmann 6,60 €, Netto 9,98 €.

### 3. Hersteller-Händlerliste — Master-Marktliste ✅
Offizielle Händlersuche (WordPress „Agile Store Locator"), **komplette Liste offen**
via httpx:

```
GET https://stores.fuerstbismarckquelle.de/wp-admin/admin-ajax.php?action=asl_load_stores
```
- 2064 Händler bundesweit, JSON mit `lat`/`lng` + Adresse.
  (Quirk: Feld `country` steht fälschlich auf „United States" — ignorieren.)
- Gefiltert auf **≤ 50 km um Kiel** → `dealers_kiel.json` / `markets.json` (200 Läden;
  Hamburg & Lübeck fallen so automatisch raus).

---

## Wer führt das Wasser (≤ 50 km Kiel)

REWE 56 · EDEKA 66 · Getränke Hoffmann 19 · famila 18 · Markant 11 · Kaufland 4 ·
CITTI · Nahkauf · Schlemmer · E-aktiv · Frischemarkt.
**Lidl & Aldi führen es nicht** (im Browser geprüft — Eigenmarken).

| Kette | Online-Preis | Quelle |
|-------|--------------|--------|
| REWE | Alltags- **und** Angebotspreis je Filiale | REWE-API (`wwIdent`) |
| Edeka, Kaufland, famila, Netto, Getränke Hoffmann, Markant … | nur **wenn reduziert** (Wochenangebot) | marktguru-API (`zipCode`) |
| Lidl, Aldi | — | führen das Produkt nicht |

---

## App (Flutter, Android) — `bismark_app/`

Eine zentrale, **nach Preis sortierte** Liste aus beiden Quellen (günstigster oben,
egal woher). Bei **gleichem Preis** kommt der **nächstgelegene** Markt oben
(Entfernung aus GPS oder aus der eingegebenen PLZ; Default-PLZ **24238**, Selent).

- `price_service.dart` — REWE-Live-Preise (parallel über alle bekannten `wwIdent`).
- `offer_service.dart` — marktguru-Angebote für die PLZ.
- `deal.dart` — vereint beides zu `Deal`s, ordnet Ketten-Angebote dem nächsten
  Markt zu, sortiert Preis → Nähe.
- `markets.dart` — 200 Läden (autogeneriert aus `markets.json`); 21 REWE mit `wwIdent`
  = Live-Preis.
- `maps_util.dart` — öffnet `geo:` direkt in der Standard-Karten-App (kein
  Google-Maps-Link). Dafür `<queries>` geo-Intent im `AndroidManifest`.
- `map_page.dart` — Karte (Nebensache), Pins pro Kette + Standort.

Build/Install:
```
cd bismark_app
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Preis-Anzeige
Der **Warenpreis** ist die Schlagzeile (z. B. 5,49 €), **Pfand 3,30 € separat** als
Rückgeld (nicht aufaddiert). Reduziert = durchgestrichener Regulärpreis.

---

## CLI-Tools (Python, Recherche/Debug)

- `bismark.py` — REWE-Preise über die hartkodierte Marktliste, markiert reduziert &
  günstigsten (`--json`, `--only-reduced`).
- `rewe_scraper.py` — generischer Playwright-Fallback (beliebiges Produkt/Stadt).
- `build_map.py` — geocodet `markets.json` → `markets_map.html` (Leaflet).

---

## Bekannte Fakten / Stolpersteine

- **Raisdorf/Schwentinental REWE = 5,79 €**, Kieler REWE = **5,49 €** (Stand zuletzt
  geprüft). Raisdorf ist näher an Selent, aber **teurer** → steht korrekt unter den
  5,49-€-Märkten (Preis schlägt Nähe).
- REWE-Angebot erkennen wir sofort (`current<regular`); Edeka & Co. nur, wenn das
  Wasser **im Wochenprospekt** steht (Regalpreis steht online nicht).
- Aktuell 21 von 56 REWE mit Live-Preis (nur die mit bekanntem `wwIdent`). Rest nur
  auf der Karte. To-do: fehlende `wwIdent` nachtragen.
- marktguru-Angebote sind **kettenweit**, nicht pro Filiale.

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

**Alle `wwIdent` bekommt man aus der Sitemap** — der Marktwähler ist zwar
Cloudflare-geschützt, die Sitemap nicht:

```
https://www.rewe.de/robots.txt          -> Sitemap: /sitemaps/sitemap.xml
https://www.rewe.de/sitemaps/sitemap-maerkte.xml
-> 4.212 URLs:  /marktseite/<ort>/<wwIdent>/rewe-markt-<strasse>-<hausnr>/
```
Damit lassen sich die IDs über die Adresse zuordnen (`build_rewe_idents.py`):
**55 von 56** REWE rund um Kiel liefern jetzt einen Regalpreis (vorher 21).
Nahkauf-Märkte stehen ebenfalls mit ID in der Sitemap, die Preis-API antwortet
für sie aber **404** — sie bedient nur REWE-Filialen.

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

### 4. EDEKA — Wochenangebote **pro Filiale** ✅
Kein Regalpreis (EDEKA veröffentlicht keinen), aber der komplette Handzettel jedes
einzelnen Marktes als HTML — feiner als marktguru, das nur kettenweit weiß.

```
GET https://www.edeka.de/api/marketsearch/markets?searchstring=<PLZ|Ort>   (JSON)
GET <market.url>                       -> nennt die interne ID: /maerkte/<id>/
GET https://www.edeka.de/maerkte/<id>/angebote/                            (HTML)
```
- Marktsuche liefert **immer max. 10** Treffer, `limit`/`offset` werden ignoriert →
  pro PLZ einmal suchen (86 PLZ aus `markets.json` → **114 Märkte**, gecacht in
  `edeka_markets.json`).
- Angebotsseite: ~150–190 Angebote je Markt, je Karte Name, Preis,
  „Festpreis/Rabattierter Preis von X€ (-Y% Rabatt)", Gebinde + Pfand + Literpreis.
- Die Sortimente unterscheiden sich real je Markt (Vergleich zweier Märkte: 184 vs. 12
  Angebote, 5 gemeinsam) — kettenweite Angaben sind also zu grob.
- **Akamai**: normale Python-Clients bekommen 403. `curl_cffi` mit Chrome-Fingerprint
  kommt durch (`impersonate="chrome"`). Der Endpunkt `/api/offers?marketId=…` ist
  gesperrt („haha! better luck next time"), die HTML-Seite nicht.

### 5. Getränke Hoffmann — Angebote **pro Region** + kompletter Handzettel ✅
```
GET  /angebote                 -> form_build_id
POST /angebote  plz=<PLZ>&form_id=choose_branch_form&form_build_id=…
```
- Danach hält das Session-Cookie die Region; die Seite listet die ~15
  Highlight-Angebote sauber im HTML (Marke, Preis, Gebinde, Pfand, Literpreis,
  Gültigkeit).
- Auf derselben Seite steht `var flipbookPdf = '/sites/default/files/…KW37….pdf'` —
  der **komplette Handzettel**, PDF **mit Textebene** (`pdftotext -layout`), also alle
  Angebote der Woche statt nur der Highlights. Das PDF ist regionsabhängig
  (`1-1_HZ_GH1-1…` ohne Region, `2-1_HZ_GH2-1…` für 24238).
- Feiner als Region geht nicht — Filialpreise gibt es online nicht.

### 6. famila Nordost — Handzettel **pro Region** als Volltext ✅
```
GET /wp-json/wp/v2/markt?per_page=100&search=Kiel     (WordPress-REST, offen)
GET <markt-url>            -> /handzettel/famila_kw<KW>_<Region>/
GET /handzettel/<slug>/files/search/book_config.js    -> var textForPages = [...]
```
- `book_config.js` ist der Suchindex des FlipHTML5-Prospekts und enthält den
  **kompletten Text aller Seiten**. Alle Kieler famila teilen die Region `West`.
- Preise stehen im Layout getrennt („5.\n52"), darum Preis aus **Literpreis ×
  Gebinde** rechnen (zuverlässiger als die Ziffern-Fragmente).
- Live-Beispiel KW37: *Fürst Bismarck Mineralwasser, 12 PET-Flaschen à 1 l,
  1 l = 0,46 € → 5,52 € + 4,50 € Pfand.* Genau dieses Angebot fehlt der App bisher,
  weil marktguru zeitgleich **0 Treffer** für „Fürst Bismarck" liefert.
- Die ACF-Felder der REST-API sind leer, `handzettel`-Seiten rendern per JS — der
  Weg über `book_config.js` ist der einzige ohne Browser.

### 7. CITTI Markt (Kiel Mühlendamm) — Wochenangebote als PDF ✅
```
GET https://cittimarkt.de/angebote
-> …/redaktion/werbung/catalogs/wochenangebote_<KW>/pdf/complete.pdf   (+ Wein-,
   Profi-, Genuss-, Vorteilsheft-Kataloge)
```
PDF mit Textebene (~167 kB Text, ~220 Preiszeilen). Ein Markt, keine Filial-Logik.

### 8. Kaufland — Wochenangebote als JSON ✅
`www.kaufland.de` steht hinter einer Cloudflare-Challenge (auch headless
Playwright bleibt bei „Just a moment…" hängen). **`filiale.kaufland.de` nicht** —
dort liegt alles offen:

```
GET https://filiale.kaufland.de/angebote/uebersicht.html
GET https://filiale.kaufland.de/.klstorefinder.json           (alle Filialen, DE)
GET https://filiale.kaufland.de/.klstorebygeo.json?lat=&lng=  (nächste Filiale)
```
- Die Angebotsseite hat ~2.200 Angebots-Objekte als JSON im HTML:
  `{offerId, dateFrom, dateTo, title, subtitle, price, discount, basePrice,
  unit, detailDescription ("+ 0.25 Pfand"), formattedOldPrice}` →
  **1.190 eindeutige Angebote** mit Preis, Streichpreis, Rabatt-%, Literpreis.
- Filialwahl ändert die Seite nicht → Angebote sind bundesweit, Zuordnung über
  die nächste Filiale (Kiel Skandinaviendamm, Schwentinental, Rendsburg,
  Bad Segeberg).

### 9. Markant — Handzettel-Volltext ✅
`markant-markt.de` gibt es nicht mehr (NXDOMAIN) — die Kette liegt auf
**markant-online.de** und benutzt exakt denselben Bela-Aufbau wie famila:

```
GET https://www.markant-online.de/marktauswahl/   -> 33 Märkte
GET https://www.markant-online.de/markt/<slug>/   -> /handzettel/Markant_kw37_Basis/
GET /handzettel/<slug>/files/search/book_config.js -> Volltext aller Seiten
```
Serverseitig gerendert, kein Browser nötig. Alle Märkte teilen `…_Basis`
(+ regionale `Mittagstisch`-Varianten) → Scope ist die Kette, nicht die Filiale.

### 10. Was **nicht** geht
| Kette | Läden ≤50 km | Status |
|-------|--------------|--------|
| Nahkauf | 5 | **keine Quelle** — REWE hat den Handzettel zum 01.07. eingestellt, Angebote laufen nur noch über WhatsApp. Sitemap kennt keine Markt- oder Angebotsseiten. |
| Lidl, Aldi | — | führen das Produkt nicht. |

**Lehre (wie schon bei REWE):** wenn ein Host dichtmacht, ist meist ein anderer
Host derselben Kette offen. `www.kaufland.de` → Cloudflare, `filiale.kaufland.de`
→ offen. `markant-markt.de` → tot, `markant-online.de` → alles da.

---

## Wer führt das Wasser (≤ 50 km Kiel)

REWE 56 · EDEKA 66 · Getränke Hoffmann 19 · famila 18 · Markant 11 · Kaufland 4 ·
CITTI · Nahkauf · Schlemmer · E-aktiv · Frischemarkt.
**Lidl & Aldi führen es nicht** (im Browser geprüft — Eigenmarken).

| Kette | Was online steht | Genauigkeit | Quelle |
|-------|------------------|-------------|--------|
| REWE | Alltags- **und** Angebotspreis | **Filiale** | REWE-API (`wwIdent`) |
| EDEKA | nur Wochenangebote | **Filiale** | `scrapers/edeka.py` |
| Getränke Hoffmann | nur Wochenangebote (Highlights + ganzer Handzettel) | Region | `scrapers/hoffmann.py` |
| famila | nur Wochenangebote (ganzer Handzettel) | Region | `scrapers/famila.py` |
| CITTI | nur Wochenangebote | der eine Markt | `scrapers/citti.py` |
| Kaufland | nur Wochenangebote | Kette (4 Filialen zugeordnet) | `scrapers/kaufland.py` |
| Markant | nur Wochenangebote (Handzettel) | Kette | `scrapers/markant.py` |
| alle Ketten inkl. Netto … | nur wenn reduziert | Kette | marktguru-API (`zipCode`) |
| Nahkauf | — | — | siehe „Was nicht geht" |
| Lidl, Aldi | — | — | führen das Produkt nicht |

---

## „Steht im Händlerverzeichnis" heißt nicht „Preis online"

Das sind zwei verschiedene Dinge, und nur eines davon kann eine App lesen:

1. **Führt der Laden das Wasser?** Das sagt die Händlerliste des Herstellers —
   eine gepflegte Liste, kein Live-Bestand. Sie sagt nichts über Preis,
   Verfügbarkeit oder ob der Laden es noch führt.
2. **Steht der Preis irgendwo öffentlich?** Das macht in Deutschland fast
   niemand. Der Regalpreis einer Filiale ist kein veröffentlichtes Datum.

Deshalb gilt: **nur REWE veröffentlicht Regalpreise pro Filiale** (die
`stationary-product-search`-API der Marktseite). Alle anderen Ketten stellen
online **ausschließlich den Wochenprospekt** ein:

| Kette | Was online steht | Regalpreis online? |
|-------|------------------|--------------------|
| REWE | Artikel mit `current`/`regular`/`refund` je `wwIdent` | **ja** |
| EDEKA | Sortimentssuche ohne Preise, dazu Angebote je Filiale | nein (geprüft: 0 € auf der Sortimentsseite) |
| Getränke Hoffmann | 15 Highlight-Angebote + Handzettel-PDF | nein |
| famila / Markant | nur Handzettel | nein |
| Kaufland | ~1.190 Angebots-Objekte, alles Aktionen | nein |
| CITTI | Werbe-PDFs | nein |

Der einzige Getränke-Onlineshop der Kette, *HoffmannBringts*, liefert nur in
Berlin, Brandenburg und Bielefeld — für Kiel bringt er nichts.

**Folge:** Ein Laden aus der Händlerliste ohne Preis in der App heißt „führt das
Wasser vermutlich, verrät den Preis aber nicht". Er taucht auf, sobald das
Produkt im Wochenprospekt steht. Bei REWE steht der Preis immer.

---

## Zielprodukt — und nur das

**Fürst Bismarck Mineralwasser Still, Kasten 12 × 0,75 l Glas** (Pfand 3,30 €).
Anderes Wasser zählt nicht — auch **kein** Fürst Bismarck in anderem Gebinde
(z. B. 12 × 1 l PET). Die Prüfung steckt doppelt und wortgleich in
`bismark_app/lib/target.dart` (App) und `scrapers/target.py` (CLI):

1. Marke — Text enthält „Bismarck".
2. Gebinde — „0,75" (oder 0.75 / 750 ml) **und** ein 12er-Kasten; „PET"/„Einweg"
   schließt aus.
3. Sorte — „Still" ausdrücklich, oder ein Sammelangebot, das Still einschließt
   („Classic, Medium oder Still", „versch. Sorten").

Beispiele:

| Angebotstext | zählt |
|---|---|
| Fürst Bismarck Classic, Medium oder Still 12 × 0,75 l Glas + Pfand 3,30 € | ja |
| Fürst Bismarck Mineralwasser versch. Sorten 12 PET-Flaschen à 1 Liter | nein (PET, 1 l) |
| Hella Mineralwasser versch. Sorten 12 × 1 L | nein (falsche Marke) |

---

## App (Flutter, Android) — `bismark_app/`

Eine zentrale, **nach Preis sortierte** Liste aus beiden Quellen (günstigster oben,
egal woher). Bei **gleichem Preis** kommt der **nächstgelegene** Markt oben
(Entfernung aus GPS oder aus der eingegebenen PLZ; Default-PLZ **24238**, Selent).

- `price_service.dart` — REWE-Live-Preise (parallel über alle bekannten `wwIdent`).
- `target.dart` — der Zielprodukt-Filter (siehe oben). Greift für **alle** Quellen,
  auch für marktguru.
- `chain_offer_service.dart` — holt Angebote direkt bei den Ketten, ohne Backend:
  famila und Markant über den Handzettel-Volltext (`book_config.js`), Getränke
  Hoffmann über das PLZ-Formular, Kaufland über das JSON in der Angebotsseite.
  **EDEKA fehlt hier**: `www.edeka.de` wirft Darts TLS-Fingerprint mit 403 raus
  (nachgeprüft mit `bismark_app/tool/probe.dart`), dort bleibt marktguru zuständig.
  Der Python-Scraper kommt per `curl_cffi` durch — für EDEKA je Filiale also CLI.
- `offer_service.dart` — marktguru-Angebote für die PLZ.
- `deal.dart` — vereint alles zu `Deal`s und sortiert Preis → Nähe. Ein
  Ketten-/Regionsangebot bekommt **eine Zeile pro Filiale dieser Kette**, damit
  jeder Laden seinen eigenen Preis, seine Entfernung und seinen Maps-Tap hat
  (vorher landete es nur beim nächstgelegenen Markt).
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

- `find_offers.py` — **ein Produkt in allen Quellen suchen**
  (`./find_offers.py Bismarck`, `--zip 24103`, `--chains edeka,hoffmann`, `--json`).
- `build_edeka_cache.py` — baut/aktualisiert `edeka_markets.json` (PLZ → interne
  EDEKA-Markt-ID). Läuft ein paar Minuten, danach ist die Suche schnell.
- `scrapers/` — je Kette ein Modul (`edeka`, `hoffmann`, `famila`, `citti`,
  `kaufland`, `markant`; `flipbook` teilen sich famila und Markant) mit
  gemeinsamer `Offer`-Struktur. Braucht `curl_cffi` (TLS-Fingerprint) und für die
  PDFs `pdftotext` (poppler-utils).
- `bismark_app/tool/` — Dart-Prüfskripte: `probe.dart` (welche Quelle antwortet
  Dart überhaupt?), `check_chains.dart` (Ketten-Services live), `check_deals.dart`
  (Deal-Liste Ende-zu-Ende), `rewe_prices.dart` (REWE-Preisverteilung).
- `build_rewe_idents.py` — zieht fehlende REWE-`wwIdent` aus der Sitemap
  (`rewe_idents.json`), `gen_markets_dart.py` schreibt `markets.json` nach
  `bismark_app/lib/markets.dart`.
- `find_offers.py` filtert standardmäßig auf das Zielprodukt; `--loose` zeigt
  jeden Treffer zum Suchwort.
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
- 55 von 56 REWE liefern einen Live-Regalpreis (IDs aus der Sitemap). Der eine
  Rest, Kakabellenweg 11-13 in Eckernförde, steht nicht in der REWE-Sitemap.
- Die Sitemap kommt über `curl_cffi` gelegentlich falsch dekodiert an (kein
  einziges `<loc>` im Text). `build_rewe_idents.py` erzwingt darum `gzip` und
  versucht es notfalls erneut.
- marktguru-Angebote sind **kettenweit**, nicht pro Filiale.
- **marktguru liefert nicht immer etwas**: am 07.09.2026 waren es **0 Treffer** für
  „Fürst Bismarck" um 24238 — die App zeigte also gar kein Nicht-REWE-Angebot,
  obwohl famila das Wasser zeitgleich für 5,52 € (12×1 l PET) im Prospekt hatte.
  Darum die Direkt-Scraper je Kette.
- EDEKA/Hoffmann/famila/CITTI liefern **nur Angebote, nie Regalpreise**. Wer dort das
  Wasser zum Normalpreis sucht, sieht nichts — das ist eine Grenze der Quellen, kein
  Bug.
- EDEKA-Angebotsseiten liefern das Sortiment **je Markt verschieden** — kettenweite
  Angaben sind zu grob.
- Nur `www.kaufland.de` ist per Cloudflare dicht — `filiale.kaufland.de` liefert alle
  Angebote als JSON. Markant liegt nicht auf `markant-markt.de` (tot), sondern auf
  `markant-online.de`. Nahkauf schickt Angebote nur noch per WhatsApp.

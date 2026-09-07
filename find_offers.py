#!/usr/bin/env python3
"""Ein Produkt in ALLEN erreichbaren Quellen rund um Kiel suchen.

    ./find_offers.py                      # Fürst Bismarck, PLZ 24238
    ./find_offers.py "Hella" --zip 24103
    ./find_offers.py --chains edeka,hoffmann --json

Quellen und wie genau sie werden:
  REWE                 Regal- UND Angebotspreis je Filiale   (price_service / bismark.py)
  EDEKA                Wochenangebote je FILIALE             (scrapers/edeka.py)
  Getränke Hoffmann    Wochenangebote je REGION + Handzettel (scrapers/hoffmann.py)
  famila               Handzettel je REGION (Volltext)       (scrapers/famila.py)
  CITTI                Wochenangebote-PDF (ein Markt)        (scrapers/citti.py)
  marktguru            Angebote kettenweit, alle Ketten      (offer_service.dart)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from scrapers import citti, edeka, famila, hoffmann  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EDEKA_CACHE = os.path.join(HERE, "edeka_markets.json")


def edeka_hits(term: str, workers: int = 8) -> list[dict]:
    if not os.path.exists(EDEKA_CACHE):
        print("! edeka_markets.json fehlt - erst `./build_edeka_cache.py` laufen lassen",
              file=sys.stderr)
        return []
    cache = json.load(open(EDEKA_CACHE, encoding="utf-8"))
    out = []

    def one(item):
        iid, market = item
        return [o for o in edeka.offers(iid, market)
                if term.lower() in (o.title + " " + o.unit).lower()]

    with ThreadPoolExecutor(workers) as ex:
        for hits in ex.map(one, cache.items()):
            out.extend(o.as_dict() for o in hits)
    return out


def hoffmann_hits(term: str, zip_code: str) -> list[dict]:
    out = [o.as_dict() for o in hoffmann.offers(zip_code)
           if term.lower() in (o.title + " " + o.unit).lower()]
    text = hoffmann.leaflet_text(zip_code)
    low = text.lower()
    start = 0
    while (i := low.find(term.lower(), start)) != -1:
        out.append({"chain": "GETRAENKE_HOFFMANN", "scope": "Region (Handzettel)",
                    "title": term, "zip": zip_code,
                    "text": " ".join(text[max(0, i - 120): i + 300].split())})
        start = i + 1
    return out


def famila_hits(term: str, city: str) -> list[dict]:
    out = []
    for m in famila.markets(city):
        slug = famila.leaflet_slug(m["url"])
        if not slug:
            continue
        for h in famila.find(slug, term):
            out.append({"chain": "FAMILA", "scope": "Region (Handzettel)",
                        "store": m["name"], "leaflet": slug,
                        "price": h["price_estimate"], "per_liter": h["per_liter"],
                        "deposit": h["deposit"], "text": h["text"]})
        break  # eine Region reicht, alle Kieler Maerkte teilen sie sich
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("term", nargs="?", default="Bismarck")
    ap.add_argument("--zip", default="24238")
    ap.add_argument("--city", default="Kiel")
    ap.add_argument("--chains", default="edeka,hoffmann,famila,citti")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    want = {c.strip().lower() for c in a.chains.split(",")}

    results: list[dict] = []
    if "edeka" in want:
        results += edeka_hits(a.term)
    if "hoffmann" in want:
        results += hoffmann_hits(a.term, a.zip)
    if "famila" in want:
        results += famila_hits(a.term, a.city)
    if "citti" in want:
        results += [{"chain": "CITTI", "scope": "Markt", "store": "CITTI Kiel", **h}
                    for h in citti.find(a.term)]

    if a.json:
        print(json.dumps(results, ensure_ascii=False, indent=1))
        return 0
    if not results:
        print(f"'{a.term}': aktuell kein Angebot in EDEKA/Hoffmann/famila/CITTI.")
        return 1
    for r in sorted(results, key=lambda x: (x.get("price") is None, x.get("price") or 0)):
        price = f"{r['price']:.2f} €" if r.get("price") else "  ?  "
        where = r.get("store") or r.get("zip") or ""
        print(f"{price:>9}  {r['chain']:<20} {r.get('scope',''):<20} {where}")
        detail = r.get("unit") or r.get("text", "")
        if detail:
            print(f"           {detail[:150]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

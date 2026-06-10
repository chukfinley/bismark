#!/usr/bin/env python3
"""
Bismark Wasser-Wächter
======================

Einziger Job: zeigt fuer GENAU EIN Produkt (Fürst Bismarck Mineralwasser
Still 12x0,75l) in allen Maerkten der Umgebung den aktuellen Preis,
markiert wo es gerade REDUZIERT ist und wo es am GUENSTIGSTEN ist.

REWE: direkte JSON-API, kein Cloudflare, kein Browser noetig.
  GET /api/stationary-product-search/products?query=<text>&wwIdent=<marktID>
  -> products[].pricing = {current, regular, refund, grammage}
  reduziert  := current < regular

Edeka/Lidl: folgen (eigene Endpunkte) -- siehe README.

Usage:
    python bismark.py                 # Tabelle, sortiert nach Gesamtpreis
    python bismark.py --json out.json # zusaetzlich JSON fuer die App
    python bismark.py --only-reduced  # nur reduzierte Maerkte zeigen
"""

import argparse
import json
import sys
from dataclasses import dataclass, asdict

import httpx

from markets import MARKETS, address

# --- Das eine Produkt ------------------------------------------------------ #
PRODUCT_ID = "8016195"
PRODUCT_QUERY = "Fürst Bismarck Still 12x0,75l"
PRODUCT_NAME = "Fürst Bismarck Mineralwasser Still 12x0,75l"

SEARCH_API = "https://www.rewe.de/api/stationary-product-search/products"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")


@dataclass
class Offer:
    retailer: str
    ident: str | None
    name: str
    address: str
    available: bool = False
    price: float | None = None       # aktueller Preis (EUR)
    regular: float | None = None     # regulaerer Preis (EUR)
    pfand: float | None = None
    reduced: bool = False
    error: str = ""

    @property
    def total(self) -> float | None:
        if self.price is None:
            return None
        return round(self.price + (self.pfand or 0), 2)


def rewe_offer(client: httpx.Client, market: dict) -> Offer:
    o = Offer(retailer=market["retailer"], ident=market["ident"],
              name=market["name"], address=address(market))
    try:
        r = client.get(SEARCH_API,
                       params={"query": PRODUCT_QUERY, "wwIdent": market["ident"]},
                       timeout=20)
        if r.status_code == 404:
            o.available = False          # Markt nicht in der Produktsuche (z.B. Nahkauf)
            return o
        r.raise_for_status()
        prod = next((p for p in r.json().get("products", [])
                     if str(p.get("id")) == PRODUCT_ID), None)
        if not prod or "pricing" not in prod:
            o.available = False          # nicht im Sortiment dieses Marktes
            return o
        pr = prod["pricing"]
        o.available = True
        o.price = pr["current"] / 100
        o.regular = pr.get("regular", pr["current"]) / 100
        o.pfand = pr.get("refund", 0) / 100
        o.reduced = o.price < o.regular
    except Exception as e:
        o.error = str(e)[:80]
    return o


def collect() -> list[Offer]:
    offers: list[Offer] = []
    with httpx.Client(headers={"User-Agent": UA}) as client:
        for m in MARKETS:
            if m["retailer"] == "REWE" and m["ident"]:
                offers.append(rewe_offer(client, m))
            # Edeka/Lidl/Aldi: noch kein Scraper -> als Platzhalter ueberspringen
    return offers


def report(offers: list[Offer], only_reduced: bool):
    have = [o for o in offers if o.available and o.price is not None]
    have.sort(key=lambda o: o.total)
    reduced = [o for o in have if o.reduced]

    print(f"\n{'='*74}")
    print(f"  {PRODUCT_NAME}")
    print(f"{'='*74}")

    if reduced:
        print(f"\n  🔻 REDUZIERT in {len(reduced)} Markt(en):")
        for o in reduced:
            save = (o.regular - o.price)
            print(f"     {o.name} ({o.address})")
            print(f"        {o.price:.2f}€  (statt {o.regular:.2f}€, -{save:.2f}€) "
                  f"+ {o.pfand:.2f}€ Pfand = {o.total:.2f}€")
    else:
        print("\n  Aktuell nirgends reduziert.")

    rows = reduced if only_reduced else have
    print(f"\n  {'Markt':<32} {'Preis':>7} {'Regulär':>8} {'Pfand':>6} {'Gesamt':>8}  Status")
    print("  " + "-" * 76)
    for o in rows:
        loc = o.name[:31]
        tag = "🔻 reduziert" if o.reduced else ""
        print(f"  {loc:<32} {o.price:>6.2f}€ {o.regular:>7.2f}€ "
              f"{o.pfand:>5.2f}€ {o.total:>7.2f}€  {tag}")

    if have:
        best = have[0]
        print("  " + "-" * 76)
        print(f"  💶 Günstigster: {best.name} – {best.address}  →  "
              f"{best.total:.2f}€ (Ware {best.price:.2f}€ + Pfand {best.pfand:.2f}€)")

    missing = [o for o in offers if not o.available and not o.error]
    if missing:
        print(f"\n  Nicht im Sortiment ({len(missing)}): "
              + ", ".join(o.name + " " + o.address.split(",")[0] for o in missing))
    errs = [o for o in offers if o.error]
    if errs:
        print(f"\n  Fehler ({len(errs)}): "
              + "; ".join(f"{o.name}: {o.error}" for o in errs))


def main():
    ap = argparse.ArgumentParser(description="Bismark Wasser-Preiswächter")
    ap.add_argument("--json", dest="json_out", help="Ergebnis als JSON speichern")
    ap.add_argument("--only-reduced", action="store_true",
                    help="Nur reduzierte Märkte anzeigen")
    args = ap.parse_args()

    offers = collect()
    report(offers, args.only_reduced)

    if args.json_out:
        payload = {
            "product": {"id": PRODUCT_ID, "name": PRODUCT_NAME},
            "offers": [asdict(o) | {"total": o.total} for o in offers],
        }
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        print(f"\n  JSON gespeichert: {args.json_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

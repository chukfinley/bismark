#!/usr/bin/env python3
"""
REWE Markt-Preis-Scraper (stationär)

Findet den In-Store-Preis eines Produkts in allen REWE-Märkten einer Stadt.
Beispiel-Default: Fürst Bismarck Mineralwasser Still 12x0,75l (Kiste) rund um Kiel.

Funktionsweise (alles im echten Browser, an Cloudflare vorbei):
  1. Produktsuche via REWE-Such-API  -> Produkt-ID
  2. Marktsuche im Marktwähler       -> Markt-IDs (wwIdent) der Stadt
  3. Pro Markt: Cookie `wksMarketsCookie` auf die Markt-ID setzen,
     Produktseite laden, Preis / Pfand / Verfügbarkeit aus dem SSR-HTML lesen

Cookie-Trick: REWE rendert die Produktseite serverseitig anhand des
HttpOnly-Cookies {"stationary":{"wwIdent":<ID>,"serviceTypes":["STATIONARY"]}}.
Wir tauschen nur diesen Cookie und laden neu -- kein Klicken pro Markt nötig.

Usage:
    python rewe_scraper.py                          # Default: Still-Kiste @ Kiel
    python rewe_scraper.py --city Hamburg --query "Fürst Bismarck Classic 12x0,75l"
    python rewe_scraper.py --product-id 8016195 --city Kiel
    python rewe_scraper.py --search "Fürst Bismarck"   # nur Produkte auflisten
    python rewe_scraper.py --visible                # Browser sichtbar
    python rewe_scraper.py --json ergebnis.json     # Ergebnis als JSON speichern

Requirements:
    pip install playwright httpx && playwright install chromium
"""

import argparse
import json
import re
import sys
import urllib.parse
from dataclasses import dataclass, asdict, field
from pathlib import Path

import httpx

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("Bitte installieren: pip install playwright httpx && playwright install chromium")
    sys.exit(1)

BASE = "https://www.rewe.de"
SEARCH_API = f"{BASE}/api/stationary-product-search/products"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

DEFAULT_QUERY = "Fürst Bismarck Still 12x0,75l"
DEFAULT_CITY = "Kiel"


# --------------------------------------------------------------------------- #
# Produktsuche
# --------------------------------------------------------------------------- #
def search_products(query: str, limit: int = 25) -> list[dict]:
    """REWE-Produktsuche (öffentliche JSON-API, kein Browser nötig)."""
    try:
        r = httpx.get(SEARCH_API, params={"query": query, "limit": limit},
                      headers={"User-Agent": UA}, timeout=20)
        r.raise_for_status()
        return r.json().get("products", [])
    except Exception as e:
        print(f"Produktsuche fehlgeschlagen: {e}", file=sys.stderr)
        return []


def resolve_product(query: str, product_id: str | None) -> dict | None:
    """Produkt-ID auflösen: explizit oder bester Treffer aus der Suche."""
    products = search_products(query)
    if product_id:
        for p in products:
            if str(p.get("id")) == str(product_id):
                return p
        # ID gesetzt, aber nicht in Suche -> trotzdem nutzbar
        return {"id": str(product_id), "title": query}
    if not products:
        return None
    # Bester Treffer: exakter Titel sonst erster
    q = query.lower()
    for p in products:
        if p.get("title", "").lower() == q:
            return p
    return products[0]


# --------------------------------------------------------------------------- #
# Ergebnis-Datenklasse
# --------------------------------------------------------------------------- #
@dataclass
class MarketPrice:
    market_id: str
    name: str = ""
    address: str = ""
    available: bool = False
    price_eur: float | None = None
    pfand_eur: float | None = None
    base_price: str = ""          # z.B. "1 l = 0,61 €"
    status: str = ""              # "Im Sortiment...", "Nicht im Sortiment..."
    error: str = ""

    @property
    def total_eur(self) -> float | None:
        if self.price_eur is None:
            return None
        return round(self.price_eur + (self.pfand_eur or 0), 2)


# --------------------------------------------------------------------------- #
# Browser-Helfer
# --------------------------------------------------------------------------- #
def _accept_cookies(page):
    for sel in ("button[data-testid='uc-accept-all-button']",
                "button:has-text('Alle akzeptieren')",
                "button:has-text('Alle erlauben')"):
        try:
            page.click(sel, timeout=4000)
            return
        except Exception:
            continue


def discover_markets(page, city: str, max_markets: int) -> list[dict]:
    """Marktwähler öffnen, Stadt suchen, alle Markt-Karten einsammeln."""
    page.goto(f"{BASE}/angebote/", wait_until="domcontentloaded", timeout=40000)
    _accept_cookies(page)

    # Marktwähler öffnen (Button kommt in Dialog ODER im Header vor)
    for sel in ("[data-testid='market-chooser-dialog'] button:has-text('Markt wählen')",
                "button:has-text('Markt wählen')"):
        try:
            page.click(sel, timeout=5000)
            break
        except Exception:
            continue

    # Suchfeld füllen
    try:
        page.fill("[data-testid='wksMarketSearchInput']", city, timeout=8000)
    except Exception:
        page.fill("input[type='search'], searchbox", city, timeout=8000)
    page.wait_for_timeout(2500)

    # Lazy-Load: Liste scrollen bis Anzahl stabil
    seen, stable = {}, 0
    for _ in range(15):
        cards = page.evaluate("""() =>
            [...document.querySelectorAll('article[data-wks-market]')].map(a => {
                const t = a.innerText.split('\\n').map(s=>s.trim()).filter(Boolean);
                return {id: a.getAttribute('data-wks-market'), name: t[0]||'', address: t[1]||''};
            })""")
        for c in cards:
            seen[c["id"]] = c
        if len(seen) >= max_markets:
            break
        if len(cards) == 0:
            stable += 1
            if stable >= 3:
                break
        # letzte Karte in den View scrollen
        try:
            page.evaluate("""() => {
                const els = document.querySelectorAll('article[data-wks-market]');
                if (els.length) els[els.length-1].scrollIntoView();
            }""")
        except Exception:
            pass
        page.wait_for_timeout(1200)
        new = page.evaluate("() => document.querySelectorAll('article[data-wks-market]').length")
        if new <= len(cards):
            stable += 1
            if stable >= 3:
                break
        else:
            stable = 0

    return list(seen.values())[:max_markets]


def fetch_price(page, product_id: str, market: dict) -> MarketPrice:
    """Cookie auf Markt setzen, Produktseite laden, Preis parsen."""
    res = MarketPrice(market_id=market["id"],
                      name=market.get("name", ""),
                      address=market.get("address", ""))
    try:
        cookie_val = urllib.parse.quote(
            json.dumps({"stationary": {"wwIdent": market["id"],
                                       "serviceTypes": ["STATIONARY"]}},
                       separators=(",", ":")))
        page.context.add_cookies([{
            "name": "wksMarketsCookie",
            "value": cookie_val,
            "domain": ".rewe.de", "path": "/",
        }])
        page.goto(f"{BASE}/produkte/x/{product_id}/",
                  wait_until="domcontentloaded", timeout=30000)
        main = page.evaluate("() => document.querySelector('main')?.innerText || ''")

        if re.search(r"Nicht im Sortiment", main, re.I):
            res.available = False
            res.status = "Nicht im Sortiment dieses Marktes"
            return res

        # Preis: erster Betrag, der NICHT Grundpreis (1 l = ..) und NICHT Pfand ist.
        # Zeilenlayout: "12x0,75l (1 l = 0,61 €), zzgl. 3,30 € Pfand" / "5,49 €"
        pf = re.search(r"([\d.,]+)\s*€\s*Pfand", main, re.I)
        if pf:
            res.pfand_eur = float(pf.group(1).replace(".", "").replace(",", "."))
        bp = re.search(r"\(([^)]*1\s*l\s*=\s*[\d.,]+\s*€[^)]*)\)", main, re.I)
        if bp:
            res.base_price = bp.group(1).strip()

        # alleinstehende Preis-Zeile finden (z.B. "5,49 €")
        price = None
        for line in main.split("\n"):
            line = line.strip()
            m = re.fullmatch(r"(\d{1,3}[,.]\d{2})\s*€", line)
            if m:
                price = float(m.group(1).replace(",", "."))
                break
        if price is None:
            # Fallback: alle Beträge, Pfand/Grundpreis entfernen
            cands = [float(x.replace(",", "."))
                     for x in re.findall(r"(\d{1,3}[,.]\d{2})\s*€", main)]
            cands = [c for c in cands if c != res.pfand_eur]
            price = cands[0] if cands else None

        if price is not None:
            res.available = True
            res.price_eur = price
            sm = re.search(r"(Im Sortiment[^\n]*)", main, re.I)
            res.status = sm.group(1).strip() if sm else "Im Sortiment"
        else:
            res.status = "Preis nicht gefunden"
    except Exception as e:
        res.error = str(e)[:80]
    return res


# --------------------------------------------------------------------------- #
# Hauptlauf
# --------------------------------------------------------------------------- #
def run(query: str, city: str, product_id: str | None,
        max_markets: int, headless: bool, json_out: str | None):
    product = resolve_product(query, product_id)
    if not product:
        print(f"Kein Produkt gefunden für: {query!r}")
        return 1
    pid, ptitle = str(product["id"]), product.get("title", query)

    print(f"\n{'='*60}")
    print(f"Produkt : {ptitle}  (ID {pid})")
    print(f"Stadt   : {city}")
    print(f"{'='*60}\n")

    results: list[MarketPrice] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=["--disable-blink-features=AutomationControlled", "--no-sandbox"])
        ctx = browser.new_context(locale="de-DE",
                                  viewport={"width": 1366, "height": 900},
                                  user_agent=UA)
        page = ctx.new_page()

        print(f"Suche Märkte in {city} ...", flush=True)
        markets = discover_markets(page, city, max_markets)
        print(f"{len(markets)} Märkte gefunden.\n")

        for i, m in enumerate(markets, 1):
            print(f"  [{i}/{len(markets)}] {m['name']} – {m['address']} ... ",
                  end="", flush=True)
            r = fetch_price(page, pid, m)
            results.append(r)
            if r.available:
                pf = r.pfand_eur or 0
                print(f"{r.price_eur:.2f}€ (+{pf:.2f}€ Pfand) = {r.total_eur:.2f}€")
            else:
                print(r.status or r.error or "n/a")

        ctx.close()
        browser.close()

    _print_table(results, ptitle)

    if json_out:
        Path(json_out).write_text(
            json.dumps({"product": {"id": pid, "title": ptitle}, "city": city,
                        "results": [asdict(r) | {"total_eur": r.total_eur}
                                    for r in results]},
                       indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"\nJSON gespeichert: {json_out}")
    return 0


def _print_table(results: list[MarketPrice], title: str):
    ok = [r for r in results if r.available and r.price_eur is not None]
    ok.sort(key=lambda r: r.total_eur)
    print(f"\n{'='*72}")
    print(f"{title}")
    print(f"{'='*72}")
    if not ok:
        print("Kein Markt mit Preis gefunden.")
        return
    print(f"{'Markt':<34} {'Preis':>8} {'Pfand':>8} {'Gesamt':>9}")
    print("-" * 72)
    for r in ok:
        loc = (r.name + " " + r.address.split(",")[0]).strip()[:33]
        print(f"{loc:<34} {r.price_eur:>7.2f}€ {(r.pfand_eur or 0):>7.2f}€ "
              f"{r.total_eur:>8.2f}€")
    best = ok[0]
    print("-" * 72)
    print(f"Günstigster: {best.name} ({best.address}) -> {best.total_eur:.2f}€")
    not_stocked = [r for r in results if not r.available]
    if not_stocked:
        print(f"\nNicht im Sortiment ({len(not_stocked)}): "
              + ", ".join(r.address.split(",")[0] for r in not_stocked))


def main():
    ap = argparse.ArgumentParser(description="REWE Markt-Preis-Scraper")
    ap.add_argument("--query", default=DEFAULT_QUERY, help="Produkt-Suchbegriff")
    ap.add_argument("--city", default=DEFAULT_CITY, help="Stadt / PLZ / Ort")
    ap.add_argument("--product-id", help="Produkt-ID direkt vorgeben")
    ap.add_argument("--max-markets", type=int, default=40, help="Max. Märkte")
    ap.add_argument("--search", metavar="Q", help="Nur Produkte suchen & auflisten")
    ap.add_argument("--visible", action="store_true", help="Browser anzeigen")
    ap.add_argument("--json", dest="json_out", help="Ergebnis als JSON speichern")
    args = ap.parse_args()

    if args.search:
        ps = search_products(args.search)
        print(f"\n{len(ps)} Treffer:\n")
        for p in ps:
            print(f"  {p['id']:<10} {p.get('title','')}")
        return 0

    return run(args.query, args.city, args.product_id,
               args.max_markets, not args.visible, args.json_out)


if __name__ == "__main__":
    sys.exit(main())

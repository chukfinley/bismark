"""EDEKA: Wochenangebote pro FILIALE (nicht nur kettenweit wie marktguru).

Zwei Schritte:
  1. Marktsuche (JSON, offen):
     GET https://www.edeka.de/api/marketsearch/markets?searchstring=<PLZ|Ort>
     -> markets[]: id, name, contact.address, coordinates, url (…/eh/…/index.jsp)
     Achtung: liefert immer max. 10 Treffer, `limit`/`offset` werden ignoriert
     -> pro PLZ einmal suchen und die Treffer einsammeln.
  2. Die Marktseite nennt die interne Markt-ID: /maerkte/<id>/…
     Die Angebotsseite https://www.edeka.de/maerkte/<id>/angebote/ enthaelt
     ALLE Angebote des Marktes als HTML (Name, Preis, Gebinde, Rabatt).
     EDEKA veroeffentlicht KEINE Regalpreise - nur Angebote.

Cloudflare/Akamai: normale Python-Clients bekommen 403, curl_cffi mit
Chrome-Fingerprint kommt durch (siehe common.get).
"""
from __future__ import annotations

import json
import re
from concurrent.futures import ThreadPoolExecutor
from typing import Iterable

from .common import Offer, deposit, get, per_liter, to_float

SEARCH = "https://www.edeka.de/api/marketsearch/markets?searchstring={}"
OFFERS = "https://www.edeka.de/maerkte/{}/angebote/"

_CARD = re.compile(r"<article\b.*?</article>", re.S)
_NAME = re.compile(r'<span class="sr-only">Angebot:</span>\s*([^<]{2,120})')
_PRICE = re.compile(r'<span class="block px-2 sm:py-1">\s*([0-9]+[.,][0-9]{2})\s*</span>')
# "Festpreis von 1.99€" bzw. "Rabattierter Preis von 0.99€ (Insgesamt -50% Rabatt)"
_SR_PRICE = re.compile(r'(Festpreis|Rabattierter Preis) von ([0-9]+[.,][0-9]{2})€'
                       r'(?:[^<]*?-([0-9]+)% Rabatt)?')
_DESC = re.compile(r'<p class="line-clamp-2">\s*([^<]{2,200})')


def search_markets(term: str) -> list[dict]:
    """Maximal 10 EDEKA-Maerkte zu PLZ oder Ort."""
    r = get(SEARCH.format(term))
    if r.status_code != 200:
        return []
    return r.json().get("markets", [])


def market_internal_id(market: dict) -> str | None:
    """Interne /maerkte/<id>/-ID aus der Marktseite ziehen."""
    url = market.get("url")
    if not url:
        return None
    r = get(url)
    m = re.search(r"/maerkte/(\d+)/", r.text)
    return m.group(1) if m else None


def discover(terms: Iterable[str], workers: int = 8) -> dict[str, dict]:
    """PLZ-Liste -> {interne ID: Markt}. Ergebnis cachen, aendert sich selten."""
    found: dict[int, dict] = {}
    with ThreadPoolExecutor(workers) as ex:
        for markets in ex.map(search_markets, list(terms)):
            for m in markets:
                found[m["id"]] = m
    out: dict[str, dict] = {}
    with ThreadPoolExecutor(workers) as ex:
        for m, iid in zip(found.values(), ex.map(market_internal_id, found.values())):
            if iid:
                out[iid] = m
    return out


def offers(internal_id: str, market: dict | None = None) -> list[Offer]:
    r = get(OFFERS.format(internal_id))
    if r.status_code != 200:
        return []
    addr = (market or {}).get("contact", {}).get("address", {})
    city = addr.get("city", {})
    out, seen = [], set()
    for card in _CARD.findall(r.text):
        name = _NAME.search(card)
        if not name:
            continue
        title = re.sub(r"\s+", " ", name.group(1)).strip()
        sr = _SR_PRICE.search(card)
        prices = [sr.group(2)] if sr else _PRICE.findall(card)
        desc = _DESC.search(card)
        unit = re.sub(r"\s+", " ", desc.group(1)).strip() if desc else ""
        key = (title, prices[0] if prices else "", unit)
        if key in seen:
            continue
        seen.add(key)
        price = to_float(prices[0]) if prices else None
        discount = int(sr.group(3)) if sr and sr.group(3) else None
        out.append(Offer(
            chain="EDEKA",
            title=title,
            price=price,
            unit=unit,
            deposit=deposit(unit),
            per_liter=per_liter(unit),
            discount_pct=discount,
            scope="Markt",
            store=(market or {}).get("name", ""),
            store_id=str(internal_id),
            zip=city.get("zipCode", ""),
            city=city.get("name", ""),
            source=OFFERS.format(internal_id),
        ))
    return out


def load_cache(path: str) -> dict[str, dict]:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)

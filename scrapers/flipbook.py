"""FlipHTML5-Handzettel auslesen (Bela-Gruppe: famila, Markant).

Jeder Prospekt liegt unter /handzettel/<slug>/ und bringt seinen eigenen
Suchindex mit:

    /handzettel/<slug>/files/search/book_config.js  ->  var textForPages = [...]

Das ist der KOMPLETTE Text aller Prospektseiten. Preise stehen dort so
umbrochen wie im Layout ("5.\\n52"), darum den Preis lieber aus
Literpreis x Gebinde rechnen.
"""
from __future__ import annotations

import json
import re

from .common import get, to_float

_PAGES = re.compile(r"var textForPages\s*=\s*(\[.*\])\s*;?\s*$", re.S)
_LITER = re.compile(r"1 Liter\s*=\s*([0-9]+[.,][0-9]{2})")
_DEPOSIT = re.compile(r"zzgl\.\s*([0-9]+[.,][0-9]{2})\s*€?\s*Pfand")
_VOLUME = re.compile(
    r"(\d+)\s*(?:PET-Flaschen|Glasflaschen|Flaschen|x)\s*à?\s*([0-9,\.]+)\s*Liter")
# Preis direkt vor dem Produktnamen ("8,88 4,44 Fürst Bismarck …"), nur wenn
# er zum Literpreis passt - sonst ist es die Zahl des Nachbarangebots.
_PRICE_BEFORE = re.compile(r"(\d+,\d{2})\s+(?:[^\s\d]+\s+)?$")


def slug_from_page(url: str) -> str | None:
    """Handzettel-Slug aus einer Markt-/Übersichtsseite ziehen."""
    m = re.search(r"handzettel/([A-Za-z0-9_\-]+)", get(url).text)
    return m.group(1) if m else None


def slugs_from_page(url: str) -> list[str]:
    return sorted(set(re.findall(r"handzettel/([A-Za-z0-9_\-]+)", get(url).text)))


def pages(base: str, slug: str) -> list[str]:
    r = get(f"{base}/handzettel/{slug}/files/search/book_config.js")
    if r.status_code != 200:
        return []
    m = _PAGES.search(r.text)
    if not m:
        return []
    try:
        return [p.replace("\r\n", "\n") for p in json.loads(m.group(1))]
    except json.JSONDecodeError:
        return []


def find(base: str, slug: str, term: str, context: int = 400) -> list[dict]:
    """Fundstellen mit Umfeld, Literpreis, Pfand und geschätztem Kistenpreis."""
    hits = []
    for page_no, page in enumerate(pages(base, slug), start=1):
        for m in re.finditer(re.escape(term), page, re.I):
            after = page[m.start(): m.start() + context]
            seg = page[max(0, m.start() - context // 4): m.start() + context]
            lit, dep, vol = _LITER.search(after), _DEPOSIT.search(after), _VOLUME.search(after)
            price = None
            if lit and vol:
                per_l = to_float(lit.group(1))
                litres = int(vol.group(1)) * (to_float(vol.group(2)) or 0)
                if per_l and litres:
                    price = round(per_l * litres, 2)
                    before = _PRICE_BEFORE.search(page[max(0, m.start() - 40): m.start()])
                    exact = to_float(before.group(1)) if before else None
                    # Literpreis ist auf Cent gerundet: Abweichung <= 0,005 € je Liter
                    if exact and abs(exact - price) <= 0.005 * litres + 0.01:
                        price = exact
            hits.append({
                "leaflet": slug,
                "page": page_no,
                "text": " ".join(seg.split()),
                "per_liter": to_float(lit.group(1)) if lit else None,
                "deposit": to_float(dep.group(1)) if dep else None,
                "price_estimate": price,
            })
    return hits

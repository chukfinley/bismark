"""famila Nordost: Handzettel pro Region, als durchsuchbarer Volltext.

famila veroeffentlicht keine Preise als JSON. Der Handzettel liegt aber als
FlipHTML5-Buch pro Region:

  1. Marktliste offen ueber die WordPress-REST-API:
       GET /wp-json/wp/v2/markt?per_page=100&search=<Ort>
  2. Die Marktseite verlinkt den Handzettel der Region:
       /handzettel/famila_kw37_West/index.html
  3. Dessen Suchindex enthaelt den KOMPLETTEN Text aller Seiten:
       /handzettel/<slug>/files/search/book_config.js  ->  var textForPages = [...]

Der Text ist so umbrochen wie im Layout, Preise stehen oft getrennt
("5.\\n99"). Darum: Treffer + Umfeld liefern, Preis nur als beste Schaetzung
(Literpreis x Gebinde ist meist zuverlaessiger).
"""
from __future__ import annotations

import json
import re

from .common import get, to_float

BASE = "https://www.famila-nordost.de"
MARKETS = BASE + "/wp-json/wp/v2/markt?per_page=100"


def markets(search: str = "") -> list[dict]:
    url = MARKETS + (f"&search={search}" if search else "")
    r = get(url)
    return [{"id": m["id"], "name": m["title"]["rendered"], "url": m["link"]}
            for m in r.json()] if r.status_code == 200 else []


def leaflet_slug(market_url: str) -> str | None:
    """Handzettel-Slug (Region + KW) des Marktes, z. B. famila_kw37_West."""
    m = re.search(r"handzettel/([A-Za-z0-9_\-]+)", get(market_url).text)
    return m.group(1) if m else None


def leaflet_text(slug: str) -> list[str]:
    """Volltext des Handzettels, eine Zeichenkette pro Seite."""
    r = get(f"{BASE}/handzettel/{slug}/files/search/book_config.js")
    if r.status_code != 200:
        return []
    m = re.search(r"var textForPages\s*=\s*(\[.*\])\s*;?\s*$", r.text, re.S)
    if not m:
        return []
    try:
        pages = json.loads(m.group(1))
    except json.JSONDecodeError:
        return []
    return [p.replace("\r\n", "\n") for p in pages]


def find(slug: str, term: str, context: int = 400) -> list[dict]:
    """Alle Fundstellen eines Suchbegriffs mit Umfeld und geschaetztem Preis."""
    hits = []
    for page_no, page in enumerate(leaflet_text(slug), start=1):
        for m in re.finditer(re.escape(term), page, re.I):
            after = page[m.start(): m.start() + context]
            seg = page[max(0, m.start() - context // 4): m.start() + context]
            lit = re.search(r"1 Liter = ([0-9]+[.,][0-9]{2})", after)
            dep = re.search(r"zzgl\.\s*([0-9]+[.,][0-9]{2})\s*€?\s*Pfand", after)
            vol = re.search(r"(\d+)\s*(?:PET-Flaschen|Flaschen|x)\s*à?\s*([0-9,\.]+)\s*Liter", after)
            price = None
            if lit and vol:
                per_l = to_float(lit.group(1))
                litres = int(vol.group(1)) * (to_float(vol.group(2)) or 0)
                if per_l and litres:
                    price = round(per_l * litres, 2)
            hits.append({
                "page": page_no,
                "text": " ".join(seg.split()),
                "per_liter": to_float(lit.group(1)) if lit else None,
                "deposit": to_float(dep.group(1)) if dep else None,
                "price_estimate": price,
            })
    return hits

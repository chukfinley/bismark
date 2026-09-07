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

import re

from . import flipbook
from .common import get

BASE = "https://www.famila-nordost.de"
MARKETS = BASE + "/wp-json/wp/v2/markt?per_page=100"


def markets(search: str = "") -> list[dict]:
    url = MARKETS + (f"&search={search}" if search else "")
    r = get(url)
    return [{"id": m["id"], "name": m["title"]["rendered"], "url": m["link"]}
            for m in r.json()] if r.status_code == 200 else []


def leaflet_slug(market_url: str) -> str | None:
    """Handzettel-Slug (Region + KW) des Marktes, z. B. famila_kw37_West."""
    return flipbook.slug_from_page(market_url)


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
    return flipbook.find(BASE, slug, term, context)

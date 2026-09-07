"""Markant (Bela-Gruppe, 11 Läden ≤50 km): Handzettel pro Markt.

`markant-markt.de` gibt es nicht mehr — die Kette liegt auf
**markant-online.de** und benutzt denselben Aufbau wie famila:

  GET https://www.markant-online.de/marktauswahl/   -> alle Märkte
  GET https://www.markant-online.de/markt/<slug>/   -> verlinkt
      /handzettel/Markant_kw<KW>_<Variante>/…       (Basis, Mittagstisch, …)
  GET /handzettel/<slug>/files/search/book_config.js -> Volltext

Anders als bei famila ist die Seite serverseitig gerendert, ein Browser ist
nicht nötig.
"""
from __future__ import annotations

import re

from . import flipbook
from .common import get

BASE = "https://www.markant-online.de"


def markets() -> list[dict]:
    """Alle Markant-Märkte mit Slug und URL."""
    t = get(BASE + "/marktauswahl/").text
    slugs = sorted(set(re.findall(r"markant-online\.de/markt/([a-z0-9\-]+)/?", t)))
    return [{"slug": s, "url": f"{BASE}/markt/{s}/"} for s in slugs]


def leaflets(market_url: str) -> list[str]:
    return flipbook.slugs_from_page(market_url)


def find(market_url: str, term: str) -> list[dict]:
    out = []
    for slug in leaflets(market_url):
        out += flipbook.find(BASE, slug, term)
    return out

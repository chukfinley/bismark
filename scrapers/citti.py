"""CITTI Markt (Kiel Mühlendamm): Wochenangebote als PDF mit Textebene.

  GET https://cittimarkt.de/angebote
  -> Links auf .../redaktion/werbung/catalogs/<katalog>/pdf/complete.pdf
     (u. a. `wochenangebote_<KW>`, dazu Wein-, Profi-, Genuss-Kataloge)

Ein Markt, keine Filial-Logik. `pdftotext -layout` liefert den Text; die
Layout-Spalten stehen dabei nebeneinander, darum Treffer immer mit Umfeld
lesen.
"""
from __future__ import annotations

import re
import subprocess
import tempfile

from .common import get

BASE = "https://cittimarkt.de"
ANGEBOTE = BASE + "/angebote"
_PDF = re.compile(r'https?://[^"\']+/catalogs/([^/"\']+)/pdf/complete\.pdf')


def catalogs() -> dict[str, str]:
    """{Katalogname: PDF-URL} der aktuellen Werbung."""
    t = get(ANGEBOTE).text
    return {m.group(1): m.group(0) for m in _PDF.finditer(t)}


def catalog_text(url: str) -> str:
    pdf = get(url).content
    with tempfile.NamedTemporaryFile(suffix=".pdf") as fh:
        fh.write(pdf)
        fh.flush()
        try:
            return subprocess.run(["pdftotext", "-layout", fh.name, "-"],
                                  capture_output=True, text=True, timeout=300).stdout
        except FileNotFoundError:
            return ""


def find(term: str, only: str = "wochenangebote", context: int = 300) -> list[dict]:
    hits = []
    for name, url in catalogs().items():
        if only and only not in name:
            continue
        text = catalog_text(url)
        for m in re.finditer(re.escape(term), text, re.I):
            seg = text[max(0, m.start() - 100): m.start() + context]
            hits.append({"catalog": name, "text": " ".join(seg.split()), "source": url})
    return hits

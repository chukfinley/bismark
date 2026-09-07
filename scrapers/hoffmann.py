"""Getränke Hoffmann: Angebote pro REGION + kompletter Handzettel als PDF.

Die Seite waehlt die Region ueber ein Drupal-Formular:
  GET  /angebote                -> form_build_id aus dem HTML
  POST /angebote  plz=<PLZ>&form_id=choose_branch_form&form_build_id=…
  -> Session-Cookie haelt die Region, die Seite zeigt danach die
     Highlight-Angebote dieser Region (Marke, Preis, Gebinde, Pfand,
     Literpreis, Gueltigkeit) sauber im HTML.

Auf derselben Seite steht der komplette Handzettel als PDF
(`var flipbookPdf = '/sites/default/files/…KW37…pdf'`). Das PDF hat eine
Textebene -> `pdftotext -layout` liefert alle Angebote der Woche, nicht nur
die ~15 Highlights.

Pro Filiale gibt es keine eigenen Preise; feiner als Region wird es nicht.
"""
from __future__ import annotations

import re
import subprocess
import tempfile

from .common import Offer, deposit, per_liter, session, strip_tags, to_float

BASE = "https://www.getraenke-hoffmann.de"
ANGEBOTE = BASE + "/angebote"

_BLOCK = re.compile(
    r'<h3 class="p-sliderelement__headline">(.*?)</h3>\s*'
    r'<div class="p-sliderelement__text">(.*?)</div>\s*'
    r'(?:<div class="p-sliderelement__gueltigkeit">(.*?)</div>)?', re.S)
_PRICE = re.compile(r'<p class="red-big">\s*([0-9]+[.,][0-9]{2})\s*EUR')
_PDF = re.compile(r"var flipbookPdf = '([^']+)'")


def _region_page(zip_code: str) -> str:
    s = session()
    t = s.get(ANGEBOTE, timeout=30).text
    build = re.search(r'name="form_build_id" value="([^"]+)"', t)
    if not build:
        return t
    r = s.post(ANGEBOTE, timeout=30, data={
        "plz": zip_code, "op": "OK",
        "form_build_id": build.group(1),
        "form_id": "choose_branch_form",
    })
    return r.text


def offers(zip_code: str) -> list[Offer]:
    html = _region_page(zip_code)
    out = []
    for brand, body, valid in _BLOCK.findall(html):
        price = _PRICE.search(body)
        text = strip_tags(body)
        paras = [strip_tags(p) for p in re.findall(r"<p[^>]*>(.*?)</p>", body, re.S)]
        subtitle = paras[0].replace("\n", " ").strip() if paras else ""
        unit = " ".join(p.replace("\n", " ").split()
                        for p in paras[2:]) if False else " ".join(
            " ".join(p.split()) for p in paras[2:])
        out.append(Offer(
            chain="GETRAENKE_HOFFMANN",
            title=" ".join((strip_tags(brand) + " " + subtitle).split()),
            price=to_float(price.group(1)) if price else None,
            unit=unit,
            deposit=deposit(text),
            per_liter=per_liter(text),
            valid_to=" ".join(strip_tags(valid).replace("gültig:", "").split()),
            scope="Region",
            zip=zip_code,
            source=ANGEBOTE,
        ))
    return out


def leaflet_pdf_url(zip_code: str) -> str | None:
    m = _PDF.search(_region_page(zip_code))
    return BASE + m.group(1) if m else None


def leaflet_text(zip_code: str) -> str:
    """Kompletter Handzettel als Text (braucht `pdftotext`)."""
    url = leaflet_pdf_url(zip_code)
    if not url:
        return ""
    s = session()
    pdf = s.get(url, timeout=120).content
    with tempfile.NamedTemporaryFile(suffix=".pdf") as fh:
        fh.write(pdf)
        fh.flush()
        try:
            return subprocess.run(["pdftotext", "-layout", fh.name, "-"],
                                  capture_output=True, text=True, timeout=180).stdout
        except FileNotFoundError:
            return ""

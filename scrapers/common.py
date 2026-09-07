"""Gemeinsame HTTP-Helfer fuer die Ketten-Scraper.

curl_cffi statt httpx: EDEKA (Akamai) und einige andere blocken die
Standard-TLS-Signatur von Python-Clients. `impersonate="chrome"` reicht.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field, asdict
from typing import Optional

from curl_cffi import requests as creq

TIMEOUT = 30


def get(url: str, **kw) -> creq.Response:
    return creq.get(url, impersonate="chrome", timeout=TIMEOUT, **kw)


def session() -> creq.Session:
    return creq.Session(impersonate="chrome")


def strip_tags(html: str) -> str:
    t = re.sub(r"<br\s*/?>", "\n", html)
    t = re.sub(r"<[^>]+>", " ", t)
    t = t.replace("&nbsp;", " ").replace("&amp;", "&")
    return re.sub(r"[ \t]+", " ", t).strip()


def to_float(s: str) -> Optional[float]:
    if not s:
        return None
    s = s.strip().replace(".", ".").replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return None


@dataclass
class Offer:
    """Ein Angebot einer Kette, so genau lokalisiert wie die Quelle es hergibt."""

    chain: str                      # REWE / EDEKA / GETRAENKE_HOFFMANN / FAMILA / CITTI
    title: str                      # Produkt-/Markenname wie beworben
    price: Optional[float]          # Warenpreis in Euro (ohne Pfand)
    unit: str = ""                  # "12 x 0,75 l Glas" o.ae.
    deposit: Optional[float] = None  # Pfand in Euro
    per_liter: Optional[float] = None
    old_price: Optional[float] = None
    discount_pct: Optional[int] = None
    valid_to: str = ""
    scope: str = ""                 # "Markt", "Region", "Kette"
    store: str = ""                 # Marktname wenn bekannt
    store_id: str = ""
    zip: str = ""
    city: str = ""
    source: str = ""                # URL

    def as_dict(self) -> dict:
        return asdict(self)


# "zzgl. 3,30 Pfand" / "+ Pfand 3,30 €" / "(zzgl. € 3,10 Pfand)"
DEPOSIT_RE = re.compile(
    r"Pfand[^0-9]{0,6}([0-9]+[.,][0-9]{2})"
    r"|([0-9]+[.,][0-9]{2})\s*(?:€|EUR)?\s*Pfand", re.I)
# "Liter: 1,00 €" / "(1 l = 0,39)" / "1 Liter = 0.46 €"
LITER_RE = re.compile(
    r"(?:1\s*l(?:iter)?\s*[:=]|Liter\s*:)\s*€?\s*([0-9]+[.,][0-9]{2})", re.I)


def deposit(text: str):
    m = DEPOSIT_RE.search(text or "")
    if not m:
        return None
    return to_float(m.group(1) or m.group(2))


def per_liter(text: str):
    m = LITER_RE.search(text or "")
    return to_float(m.group(1)) if m else None

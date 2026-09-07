"""Kaufland: Wochenangebote als JSON, direkt in der Angebotsseite.

`www.kaufland.de` steht hinter einer Cloudflare-Challenge (auch headless
Playwright kommt nicht durch). **`filiale.kaufland.de` nicht** — dort liegt
alles offen:

  GET https://filiale.kaufland.de/angebote/uebersicht.html
      -> im HTML eingebettet ~2200 Angebots-Objekte:
         {offerId, dateFrom, dateTo, title, subtitle, price, discount,
          basePrice, unit, detailDescription (enthält "+ 0.25 Pfand"),
          formattedOldPrice, …}
  GET https://filiale.kaufland.de/.klstorefinder.json      -> ALLE Filialen
  GET https://filiale.kaufland.de/.klstorebygeo.json?lat=&lng=  -> nächste Filiale

Die Angebote sind bundesweit gleich (Filialwahl ändert die Seite nicht) —
Scope also "Kette", zugeordnet wird die nächstgelegene Filiale.
"""
from __future__ import annotations

import json
import math
import re

from .common import Offer, get, to_float

BASE = "https://filiale.kaufland.de"
OFFERS = BASE + "/angebote/uebersicht.html"
STORES = BASE + "/.klstorefinder.json"
NEAREST = BASE + "/.klstorebygeo.json?lat={}&lng={}"

_DEPOSIT = re.compile(r"\+\s*([0-9]+[.,][0-9]{2})\s*Pfand")
_BASE_PRICE = re.compile(r"1\s*l\s*=\s*([0-9]+[.,][0-9]{2})")


def _objects(html: str, key: str = '{"offerId"') -> list[dict]:
    """Alle JSON-Objekte einsammeln, die mit `key` beginnen (Klammerzähler)."""
    out, i = [], html.find(key)
    while i != -1:
        depth, j, in_str, esc = 0, i, False, False
        while j < len(html):
            c = html[j]
            if in_str:
                if esc:
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        try:
            out.append(json.loads(html[i:j + 1]))
        except json.JSONDecodeError:
            pass
        i = html.find(key, j + 1)
    return out


def stores() -> list[dict]:
    r = get(STORES)
    return r.json() if r.status_code == 200 else []


def nearest_store(lat: float, lng: float) -> dict | None:
    r = get(NEAREST.format(lat, lng))
    return r.json() if r.status_code == 200 else None


def offers(store: dict | None = None) -> list[Offer]:
    html = get(OFFERS).text
    out, seen = [], set()
    for o in _objects(html):
        if o.get("offerId") in seen:      # dieselbe Ware steht in mehreren Rubriken
            continue
        seen.add(o.get("offerId"))
        desc = f"{o.get('detailDescription','')} {o.get('basePrice','')} {o.get('unit','')}"
        dep = _DEPOSIT.search(desc)
        lit = _BASE_PRICE.search(o.get("basePrice", "") or "")
        out.append(Offer(
            chain="KAUFLAND",
            title=" ".join(f"{o.get('title','')} {o.get('subtitle','')}".split()),
            price=to_float(str(o.get("price"))) if o.get("price") is not None else None,
            unit=" ".join(f"{o.get('unit','')} {o.get('basePrice','')}".split()),
            deposit=to_float(dep.group(1)) if dep else None,
            per_liter=to_float(lit.group(1)) if lit else None,
            old_price=to_float(o.get("formattedOldPrice", "")),
            discount_pct=o.get("discount") or None,
            valid_to=o.get("dateTo", ""),
            scope="Kette",
            store=(store or {}).get("cn", ""),
            store_id=(store or {}).get("n", ""),
            zip=(store or {}).get("pc", ""),
            city=(store or {}).get("t", ""),
            source=OFFERS,
        ))
    return out


def nearby_stores(lat: float, lng: float, km: float = 50) -> list[dict]:
    def dist(s):
        dlat = math.radians(float(s["lat"]) - lat)
        dlng = math.radians(float(s["lng"]) - lng)
        a = (math.sin(dlat / 2) ** 2
             + math.cos(math.radians(lat)) * math.cos(math.radians(float(s["lat"])))
             * math.sin(dlng / 2) ** 2)
        return 6371 * 2 * math.asin(math.sqrt(a))
    out = []
    for s in stores():
        try:
            d = dist(s)
        except (KeyError, ValueError):
            continue
        if d <= km:
            out.append({**s, "dist_km": round(d, 1)})
    return sorted(out, key=lambda s: s["dist_km"])

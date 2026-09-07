#!/usr/bin/env python3
"""EDEKA-Marktliste (PLZ -> interne Markt-ID) einmalig bauen/aktualisieren.

Nimmt die PLZ aus markets.json (Haendlerliste der Fuerst-Bismarck-Quelle),
sucht dazu die EDEKA-Maerkte und loest deren interne /maerkte/<id>/-ID auf.
Ergebnis: edeka_markets.json  ->  {internalId: <Markt-JSON der EDEKA-API>}
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scrapers import edeka  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))

markets = json.load(open(os.path.join(HERE, "markets.json"), encoding="utf-8"))
zips = sorted({m for e in markets
               for m in re.findall(r"\b(\d{5})\b", e.get("address", ""))})
print(f"{len(zips)} PLZ aus markets.json")
cache = edeka.discover(zips)
print(f"{len(cache)} EDEKA-Maerkte mit interner ID")
with open(os.path.join(HERE, "edeka_markets.json"), "w", encoding="utf-8") as fh:
    json.dump(cache, fh, ensure_ascii=False, indent=1)

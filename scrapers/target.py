"""Das EINE Zielprodukt erkennen: Fürst Bismarck **Still**, 12 x 0,75 l Glas.

Anderes Wasser interessiert nicht - auch nicht Fürst Bismarck in anderen
Gebinden (12 x 1 l PET z. B.). Dieselben Regeln stecken in
`bismark_app/lib/target.dart`, damit App und CLI dasselbe zeigen.
"""
from __future__ import annotations

import re

_SIZE = ("0,75", "0.75", "750 ml")
_TWELVE = re.compile(r"12\s*(?:x|st|flaschen|glas|kasten|\*)|(?:kasten|kiste)\s*12")
_STILL = re.compile(r"\bstill\b", re.I)
_COLLECTIVE = re.compile(r"versch|alle sorten|sortenrein", re.I)


def is_target(text: str) -> bool:
    t = (text or "").lower()
    if "bismarck" not in t:
        return False
    if not any(s in t for s in _SIZE):
        return False
    if not _TWELVE.search(t):
        return False
    if "pet" in t or "einweg" in t:
        return False
    return bool(_STILL.search(t) or _COLLECTIVE.search(t))

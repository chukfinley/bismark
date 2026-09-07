#!/usr/bin/env python3
"""Fehlende REWE-`wwIdent` aus der REWE-Sitemap nachtragen.

Die Marktsuche auf rewe.de steckt hinter Cloudflare - die **Sitemap** nicht:

    https://www.rewe.de/robots.txt      -> Sitemap: /sitemaps/sitemap.xml
    https://www.rewe.de/sitemaps/sitemap-maerkte.xml
    -> 4200+ URLs der Form
       /marktseite/<ort>/<wwIdent>/rewe-markt-<strasse>-<hausnummer>/

Damit lässt sich zu jeder Adresse aus `markets.json` die Markt-ID finden, und
die `stationary-product-search`-API liefert für diese Filiale den Regalpreis.

Nahkauf-Märkte stehen zwar mit ID in der Sitemap, die Preis-API antwortet für
sie aber mit 404 - sie bedient nur REWE-Märkte.

Ergebnis: `rewe_idents.json` {Adresse: wwIdent} zum Einpflegen in markets.json.
"""
import json
import os
import re
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scrapers.common import get  # noqa: E402

SITEMAP = "https://www.rewe.de/sitemaps/sitemap-maerkte.xml"
HERE = os.path.dirname(os.path.abspath(__file__))


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s.lower())
    for a, b in (("ß", "ss"), ("ä", "a"), ("ö", "o"), ("ü", "u")):
        s = s.replace(a, b)
    s = s.replace("ae", "a").replace("oe", "o").replace("ue", "u")
    s = re.sub(r"stra(ss|s)e", "str", s)
    return re.sub(r"[^a-z0-9]+", "", s)


def street_core(address: str) -> str:
    """Straße ohne Hausnummer, normalisiert."""
    street = address.split(",")[0]
    street = re.sub(r"\s*\d+.*$", "", street)
    return norm(street)


def sitemap_markets(tries: int = 4) -> list[dict]:
    # curl_cffi liefert die Sitemap gelegentlich falsch dekodiert zurueck
    # (brotli/zstd) - dann fehlt jedes <loc>. Darum gzip erzwingen und notfalls
    # wiederholen.
    text = ""
    for _ in range(tries):
        text = get(SITEMAP, headers={"Accept-Encoding": "gzip"}).text
        if "<loc>" in text:
            break
    pat = re.compile(r"https://www\.rewe\.de/marktseite/([^/]+)/(\d+)/([^/]+)/?")
    out = []
    for loc in re.findall(r"<loc>([^<]+)</loc>", text):
        m = pat.match(loc)
        if m:
            out.append({"city": m.group(1), "ident": m.group(2),
                        "slug": m.group(3), "url": loc})
    return out


def main() -> int:
    rows = sitemap_markets()
    print(f"{len(rows)} REWE-Marktseiten in der Sitemap")
    markets = json.load(open(os.path.join(HERE, "markets.json"), encoding="utf-8"))

    found, ambiguous, nothing = {}, [], []
    for m in markets:
        if m["retailer"] not in ("REWE", "NAHKAUF") or m.get("ident"):
            continue
        core = street_core(m["address"])
        city = norm(m["address"].split(",")[-1].strip().split(" ", 1)[-1])
        # Ort zuerst: die Sitemap kürzt Straßennamen ab ("bornhoev-landstr")
        # und schreibt Kurorte als "bad-<ort>". Erst danach bundesweit suchen.
        in_city = [r for r in rows
                   if city and (norm(r["city"]).startswith(city[:6])
                                or norm(r["city"]).startswith("bad" + city[:6]))]
        pick = ([r for r in in_city if core and core in norm(r["slug"])]
                or [r for r in in_city if core[:6] and core[:6] in norm(r["slug"])]
                or [r for r in rows if core and core in norm(r["slug"])])
        if len(pick) == 1:
            found[m["address"]] = pick[0]["ident"]
        elif len(pick) > 1:
            # mehrere Märkte derselben Straße: über die Hausnummer entscheiden
            num = re.search(r"\d+", m["address"].split(",")[0])
            best = [r for r in pick if num and num.group(0) in r["slug"]]
            if len(best) == 1:
                found[m["address"]] = best[0]["ident"]
            else:
                ambiguous.append((m["address"], [r["url"] for r in pick]))
        else:
            nothing.append(m["address"])

    print(f"neu zugeordnet: {len(found)}  mehrdeutig: {len(ambiguous)}  "
          f"nicht in der Sitemap: {len(nothing)}")
    for a, urls in ambiguous:
        print("  ? ", a, urls[:3])
    for a in nothing:
        print("  - ", a)
    with open(os.path.join(HERE, "rewe_idents.json"), "w", encoding="utf-8") as fh:
        json.dump(found, fh, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

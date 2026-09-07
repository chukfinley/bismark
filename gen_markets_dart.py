#!/usr/bin/env python3
"""markets.json -> bismark_app/lib/markets.dart (autogeneriert)."""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "bismark_app", "lib", "markets.dart")


def dart_str(s):
    return '"' + s.replace('\\', r'\\').replace('"', r'\"').replace("$", r"\$") + '"'


def main():
    markets = json.load(open(os.path.join(HERE, "markets.json"), encoding="utf-8"))
    with_ident = sum(1 for m in markets if m.get("ident"))
    lines = [
        "// AUTOGENERIERT aus offizieller Fürst-Bismarck-Händlerliste, "
        f"≤50km Kiel ({len(markets)} Läden).",
        f"// {with_ident} REWE mit wwIdent = Live-Regalpreis (IDs aus der REWE-Sitemap,",
        "// siehe build_rewe_idents.py); alle anderen = führt das Wasser (Angebot folgt).",
        "// Neu erzeugen: python3 gen_markets_dart.py",
        "import 'models.dart';",
        "",
        "const List<Market> kMarkets = [",
    ]
    for m in markets:
        ident = dart_str(m["ident"]) if m.get("ident") else "null"
        lat = m.get("lat")
        lon = m.get("lon")
        lines.append(
            f'  Market(retailer: {dart_str(m["retailer"])}, ident: {ident}, '
            f'name: {dart_str(m["name"])}, address: {dart_str(m["address"])}, '
            f'lat: {lat if lat is not None else "null"}, '
            f'lon: {lon if lon is not None else "null"}),')
    lines += ["];", ""]
    open(OUT, "w", encoding="utf-8").write("\n".join(lines))
    print(f"{OUT}: {len(markets)} Märkte, {with_ident} mit wwIdent")


if __name__ == "__main__":
    main()

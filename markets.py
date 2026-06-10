#!/usr/bin/env python3
"""
Kuratierte Markt-Liste (Umkreis Kiel / Schwentinental / Selent).

Hardcoded -- keine Suche. `wwIdent` ist die REWE-Markt-ID fuer die
Preis-API (api/stationary-product-search/products?query=...&wwIdent=<id>).
Edeka/Aldi haben kein REWE-Ident -> ident=None (separater Scraper noetig).
"""

MARKETS = [
    # --- REWE Kiel ---------------------------------------------------------
    {"retailer": "REWE", "ident": "8544048", "name": "REWE Adrian Stern",      "street": "Holstenstr. 1",            "plz": "24103", "city": "Kiel"},
    {"retailer": "REWE", "ident": "830868",  "name": "REWE Markt",             "street": "Knooper Weg 41-43",        "plz": "24103", "city": "Kiel"},
    {"retailer": "REWE", "ident": "531083",  "name": "REWE Markt",             "street": "Wilhelminenstraße 10",     "plz": "24103", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561204",  "name": "REWE Markt",             "street": "Holtenauer Str. 69-71",    "plz": "24105", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561221",  "name": "REWE Markt",             "street": "Eckernförder Str. 362",    "plz": "24107", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561244",  "name": "REWE Markt",             "street": "Göteborgring 3",           "plz": "24109", "city": "Kiel"},
    {"retailer": "REWE", "ident": "830930",  "name": "Nahkauf",                "street": "Hamburger Chaussee 114",   "plz": "24113", "city": "Kiel"},
    {"retailer": "REWE", "ident": "830857",  "name": "REWE Markt",             "street": "Kirchhofallee 66a",        "plz": "24114", "city": "Kiel"},
    {"retailer": "REWE", "ident": "1356331", "name": "REWE Familie Grützmacher","street": "Sophienblatt 25-27",      "plz": "24114", "city": "Kiel"},
    {"retailer": "REWE", "ident": "565687",  "name": "REWE Moritz Breske oHG", "street": "Winterbeker Weg 44",       "plz": "24114", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561215",  "name": "REWE Markt",             "street": "Gutenbergstr. 77",         "plz": "24116", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561207",  "name": "REWE Markt",             "street": "Weißenburgstr. 15",        "plz": "24116", "city": "Kiel"},
    {"retailer": "REWE", "ident": "830851",  "name": "REWE Familie Borchers",  "street": "Karlstal 27a",             "plz": "24143", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561245",  "name": "REWE Markt",             "street": "Landskroner Weg 2",        "plz": "24146", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561205",  "name": "REWE Markt",             "street": "Schönberger Str. 133",     "plz": "24148", "city": "Kiel"},
    {"retailer": "REWE", "ident": "830861",  "name": "REWE Markt",             "street": "Langer Rehm 22",           "plz": "24149", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561186",  "name": "REWE Markt",             "street": "An der Schanze 40",        "plz": "24159", "city": "Kiel"},
    {"retailer": "REWE", "ident": "561220",  "name": "REWE Markt",             "street": "Langenfelde 126a",         "plz": "24159", "city": "Kiel"},
    {"retailer": "REWE", "ident": "830872",  "name": "REWE Familie Preuß",     "street": "Richthofenstr. 57",        "plz": "24159", "city": "Kiel"},
    {"retailer": "REWE", "ident": "540506",  "name": "REWE Simon Pflesser oHG","street": "Projensdorfer Str. 148-150","plz": "24106","city": "Kiel"},
    # --- REWE Umland (grenzt an Kiel) -------------------------------------
    {"retailer": "REWE", "ident": "561225",  "name": "REWE Familie Balke",     "street": "Suchsdorfer Weg 7",        "plz": "24119", "city": "Kronshagen"},
    # --- REWE Schwentinental / Raisdorf -----------------------------------
    {"retailer": "REWE", "ident": "830862",  "name": "REWE Markt Schwentinental","street": "Klingenbergstr. 64",     "plz": "24222", "city": "Schwentinental"},
    {"retailer": "REWE", "ident": "210140",  "name": "REWE Familie Schröder",  "street": "Rönner Weg 2a",            "plz": "24223", "city": "Schwentinental/Raisdorf"},
    # --- Selent (kein REWE -> Edeka / Aldi) -------------------------------
    {"retailer": "EDEKA","ident": None,      "name": "EDEKA Ley",              "street": "Kieler Straße 2",          "plz": "24238", "city": "Selent"},
    {"retailer": "ALDI", "ident": None,      "name": "ALDI Nord",              "street": "Kieler Straße 5",          "plz": "24238", "city": "Selent-Karlshof"},
]


def address(m: dict) -> str:
    return f"{m['street']}, {m['plz']} {m['city']}"

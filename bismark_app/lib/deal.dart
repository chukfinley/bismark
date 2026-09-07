// Vereinheitlichtes "Deal"-Modell: bringt REWE-Live-Preise UND marktguru-
// Ketten-Angebote in EINE nach Preis sortierte Liste. Günstigster zuerst,
// egal aus welcher Quelle. Ketten-Angebote werden dem nächstgelegenen Markt
// dieser Kette zugeordnet, damit klar ist "welcher Edeka".
import 'dart:math' as math;

import 'models.dart';
import 'markets.dart';
import 'target.dart';

enum DealSource { reweLive, weeklyOffer }

/// REWE-Markt der als "Dein Markt" oben angepinnt wird (Raisdorf, Schröder).
const String kFavoriteIdent = '210140';

class Deal {
  final String retailer; // REWE, EDEKA, GETRAENKE_HOFFMANN …
  final String? ident; // REWE wwIdent (null bei Ketten-Angeboten)
  final String title; // Marktname (oder Kette wenn kein Markt bekannt)
  final String? address;
  final double? lat;
  final double? lon;
  final double price; // Warenpreis (EUR)
  final double pfand; // Pfand (EUR), separat / Rückgeld
  final double? strike; // durchgestrichener Preis falls reduziert
  final DealSource source;
  final String? offerDesc; // marktguru-Beschreibung
  final DateTime? validTo; // Angebot gültig bis
  double? distanceKm;

  Deal({
    required this.retailer,
    this.ident,
    required this.title,
    required this.address,
    required this.lat,
    required this.lon,
    required this.price,
    required this.pfand,
    required this.source,
    this.strike,
    this.offerDesc,
    this.validTo,
    this.distanceKm,
  });

  bool get reduced => strike != null && strike! > price;
  double get total => price + pfand;
  bool get isOffer => source == DealSource.weeklyOffer;
}

double haversineKm(double aLat, double aLon, double bLat, double bLon) {
  const r = 6371.0;
  final dLat = (bLat - aLat) * math.pi / 180;
  final dLon = (bLon - aLon) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(aLat * math.pi / 180) *
          math.cos(bLat * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

String chainCode(String marktguruName) {
  final t = marktguruName.toLowerCase();
  if (t.contains('edeka') || t.contains('e center')) return 'EDEKA';
  if (t.contains('hoffmann')) return 'GETRAENKE_HOFFMANN';
  if (t.contains('kaufland')) return 'KAUFLAND';
  if (t.contains('famila')) return 'FAMILA';
  if (t.contains('markant')) return 'MARKANT';
  if (t.contains('citti')) return 'CITTI';
  if (t.contains('nahkauf')) return 'NAHKAUF';
  if (t.contains('netto')) return 'NETTO';
  if (t.contains('rewe')) return 'REWE';
  return marktguruName.toUpperCase();
}

Market? nearestStore(String code, double refLat, double refLon) {
  Market? best;
  double bestD = double.infinity;
  for (final m in kMarkets) {
    if (m.retailer != code || m.lat == null || m.lon == null) continue;
    final d = haversineKm(refLat, refLon, m.lat!, m.lon!);
    if (d < bestD) {
      bestD = d;
      best = m;
    }
  }
  return best;
}

/// Pfand aus einem Angebotstext - die Ketten schreiben es unterschiedlich:
/// "Pfand 3,30 €", "+ Pfand 3,30 €", "zzgl. 3.30 € Pfand", "(+ 3.30 Pfand)".
double? _parsePfand(String desc) {
  final m = RegExp(r'Pfand[^0-9]{0,6}([0-9]+[.,][0-9]{2})'
          r'|([0-9]+[.,][0-9]{2})\s*(?:€|EUR)?\s*Pfand')
      .firstMatch(desc);
  if (m == null) return null;
  return double.tryParse((m.group(1) ?? m.group(2))!.replaceAll(',', '.'));
}

/// Alle Läden einer Kette (EDEKA schließt die Frischemärkte ein).
List<Market> storesOfChain(String code) => kMarkets
    .where((m) =>
        m.retailer == code ||
        (code == 'EDEKA' && m.retailer == 'FRISCHEMARKT'))
    .toList();

/// Referenzpunkt für Entfernung aus der PLZ: Schwerpunkt aller Märkte mit
/// dieser PLZ in der Adresse; sonst Kiel-Zentrum.
List<double> plzCentroid(String zip) {
  final pts = kMarkets.where((m) =>
      m.lat != null && m.lon != null && m.address.contains(zip));
  if (pts.isNotEmpty) {
    final n = pts.length;
    return [
      pts.map((m) => m.lat!).reduce((a, b) => a + b) / n,
      pts.map((m) => m.lon!).reduce((a, b) => a + b) / n,
    ];
  }
  return [54.3233, 10.1394]; // Kiel
}

/// Baut die zentrale, nach Preis (dann Nähe) sortierte Deal-Liste.
List<Deal> buildDeals(
  List<Offer> reweOffers,
  List<ChainOffer> chainOffers,
  double refLat,
  double refLon,
) {
  final deals = <Deal>[];

  for (final o in reweOffers.where((o) => o.available && o.price != null)) {
    deals.add(Deal(
      retailer: 'REWE',
      ident: o.market.ident,
      title: o.market.name,
      address: o.market.address,
      lat: o.market.lat,
      lon: o.market.lon,
      price: o.price!,
      pfand: o.pfand ?? 3.30,
      strike: o.reduced ? o.regular : null,
      source: DealSource.reweLive,
    ));
  }

  // Ketten-/Regionsangebote gelten für JEDE Filiale dieser Kette in der Nähe -
  // darum bekommt jeder Laden seine eigene Zeile mit demselben Preis. So sieht
  // man beim Antippen sofort, was der konkrete Markt kostet.
  final seen = <String>{};
  for (final c in chainOffers) {
    final code = chainCode(c.chain);
    if (code == 'REWE') continue; // REWE haben wir live pro Filiale
    // Nur das Zielprodukt: Fürst Bismarck Still, Kasten 12 x 0,75 l Glas.
    if (!matchTarget('${c.chain} ${c.description}').isTarget) continue;
    if (!seen.add('$code|${c.price}|${c.description}')) continue;
    final pfand = _parsePfand(c.description) ?? 3.30;
    final stores = storesOfChain(code);
    if (stores.isEmpty) {
      deals.add(Deal(
        retailer: code,
        title: c.chain,
        address: null,
        lat: null,
        lon: null,
        price: c.price,
        pfand: pfand,
        strike: c.oldPrice,
        source: DealSource.weeklyOffer,
        offerDesc: c.description,
        validTo: c.validTo,
      ));
      continue;
    }
    for (final store in stores) {
      deals.add(Deal(
        retailer: code,
        title: store.name,
        address: store.address,
        lat: store.lat,
        lon: store.lon,
        price: c.price,
        pfand: pfand,
        strike: c.oldPrice,
        source: DealSource.weeklyOffer,
        offerDesc: c.description,
        validTo: c.validTo,
      ));
    }
  }

  for (final d in deals) {
    if (d.lat != null && d.lon != null) {
      d.distanceKm = haversineKm(refLat, refLon, d.lat!, d.lon!);
    }
  }

  deals.sort((a, b) {
    final byPrice = a.price.compareTo(b.price);
    if (byPrice != 0) return byPrice;
    final da = a.distanceKm ?? double.infinity;
    final db = b.distanceKm ?? double.infinity;
    return da.compareTo(db);
  });
  return deals;
}

// Datenmodelle fuer den Bismark Wasser-Preiswächter.

class Market {
  final String retailer; // REWE, EDEKA, ALDI
  final String? ident; // REWE wwIdent (null = kein REWE-API)
  final String name;
  final String address;
  final double? lat;
  final double? lon;

  const Market({
    required this.retailer,
    required this.ident,
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
  });

  /// Lesbarer Kettenname (retailer ist ein Code wie GETRAENKE_HOFFMANN).
  String get retailerLabel {
    switch (retailer) {
      case 'GETRAENKE_HOFFMANN':
        return 'Getränke Hoffmann';
      case 'FRISCHEMARKT':
        return 'Frischemarkt';
      case 'SONSTIGE':
        return 'Sonstige';
      default:
        return retailer[0] + retailer.substring(1).toLowerCase();
    }
  }
}

/// Ein wochenweises Ketten-Angebot (marktguru-Aggregator, PLZ-basiert).
/// Gilt fuer die ganze Kette in der Naehe, nicht fuer eine einzelne Filiale.
class ChainOffer {
  final String chain; // z.B. EDEKA, Getränke Hoffmann
  final String description; // "Classic, Medium oder Still 12 x 0,75 l Glas …"
  final double price; // Angebotspreis Ware (EUR)
  final double? oldPrice; // Streichpreis falls vorhanden
  final double? perLiter; // referencePrice
  final DateTime? validTo;

  const ChainOffer({
    required this.chain,
    required this.description,
    required this.price,
    this.oldPrice,
    this.perLiter,
    this.validTo,
  });
}

/// Ein Preis-Angebot fuer das Produkt in einem Markt.
class Offer {
  final Market market;
  final bool available; // im Sortiment + Preis vorhanden
  final double? price; // aktueller Preis (EUR)
  final double? regular; // regulaerer Preis (EUR)
  final double? pfand; // Pfand (EUR)
  final String? error;
  double? distanceKm; // Entfernung zum Nutzer (wenn Standort an)

  Offer({
    required this.market,
    this.available = false,
    this.price,
    this.regular,
    this.pfand,
    this.error,
    this.distanceKm,
  });

  bool get reduced =>
      price != null && regular != null && price! < regular!;

  double? get total => price == null ? null : price! + (pfand ?? 0);

  double? get saving =>
      reduced ? (regular! - price!) : null;
}

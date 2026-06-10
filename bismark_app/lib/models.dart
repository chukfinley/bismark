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
}

/// Ein Preis-Angebot fuer das Produkt in einem Markt.
class Offer {
  final Market market;
  final bool available; // im Sortiment + Preis vorhanden
  final double? price; // aktueller Preis (EUR)
  final double? regular; // regulaerer Preis (EUR)
  final double? pfand; // Pfand (EUR)
  final String? error;

  const Offer({
    required this.market,
    this.available = false,
    this.price,
    this.regular,
    this.pfand,
    this.error,
  });

  bool get reduced =>
      price != null && regular != null && price! < regular!;

  double? get total => price == null ? null : price! + (pfand ?? 0);

  double? get saving =>
      reduced ? (regular! - price!) : null;
}

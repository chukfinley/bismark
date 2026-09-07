// Prueft die Deal-Liste Ende-zu-Ende: echte REWE-Preise + ein simuliertes
// Ketten-Angebot, damit man sieht, dass wirklich JEDE Filiale der Kette eine
// eigene Zeile mit Preis bekommt.
//   dart run tool/check_deals.dart
import '../lib/deal.dart';
import '../lib/models.dart';
import '../lib/price_service.dart';

Future<void> main() async {
  final rewe = await PriceService().fetchAll();
  final live = rewe.where((o) => o.available && o.price != null).length;
  print('REWE live: $live Märkte mit Preis');

  final fake = [
    const ChainOffer(
      chain: 'EDEKA',
      description: 'Fürst Bismarck Mineralwasser Classic, Medium oder Still '
          '12 x 0,75 l Glas + Pfand 3,30 €',
      price: 5.99,
      oldPrice: 6.99,
    ),
    const ChainOffer(
      chain: 'Getränke Hoffmann',
      description: 'Fürst Bismarck Mineralwasser verschiedene Sorten '
          '12 PET-Flaschen à 1 Liter zzgl. 4,50 € Pfand',
      price: 5.52, // falsches Gebinde -> muss rausfliegen
    ),
  ];
  final deals = buildDeals(rewe, fake, 54.3233, 10.1394);
  print('Deals gesamt: ${deals.length}');
  final byChain = <String, int>{};
  for (final d in deals) {
    byChain[d.retailer] = (byChain[d.retailer] ?? 0) + 1;
  }
  print('pro Kette: $byChain');
  for (final d in deals.take(8)) {
    print('  ${d.price.toStringAsFixed(2)} € + ${d.pfand.toStringAsFixed(2)} Pfand'
        '  ${d.retailer.padRight(10)} ${d.title}'
        '  ${d.distanceKm?.toStringAsFixed(1) ?? "?"} km'
        '  ${d.isOffer ? "Angebot" : "Regalpreis"}');
  }
}

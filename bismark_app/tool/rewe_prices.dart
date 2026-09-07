import '../lib/price_service.dart';

Future<void> main() async {
  final offers = await PriceService().fetchAll();
  final ok = offers.where((o) => o.available && o.price != null).toList()
    ..sort((a, b) => a.price!.compareTo(b.price!));
  print('REWE-Märkte mit Live-Preis: ${ok.length}');
  final byPrice = <String, int>{};
  for (final o in ok) {
    final k = '${o.price!.toStringAsFixed(2)}${o.reduced ? " (reduziert)" : ""}';
    byPrice[k] = (byPrice[k] ?? 0) + 1;
  }
  print(byPrice);
  for (final o in ok.take(5)) {
    print('  ${o.price} € ${o.reduced ? "statt ${o.regular} " : ""}'
        '+ ${o.pfand} Pfand  ${o.market.name}, ${o.market.address}');
  }
}

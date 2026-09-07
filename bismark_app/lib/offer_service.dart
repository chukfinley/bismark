// Wochen-Angebote ALLER Ketten (Edeka, Kaufland, famila, Netto, Getränke
// Hoffmann …) über den marktguru-Aggregator. Ein httpx-Call pro PLZ, kein
// Cloudflare. Liefert nur Produkte die GERADE im Angebot sind.
//
//   GET https://api.marktguru.de/api/v1/offers/search
//        ?as=mobile&limit=40&q=<query>&zipCode=<plz>
//   Header: X-Apikey, X-Clientkey  (öffentliche Web-/App-Keys)
//   -> results[]: {description, price, oldPrice, referencePrice,
//                  validityDates[{from,to}], advertisers[{name}], brand,
//                  volume, quantity}
//
// Hinweis: Angebot gilt kettenweit in der Nähe, nicht pro Filiale.

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'models.dart';

class OfferService {
  static const String _base =
      'https://api.marktguru.de/api/v1/offers/search';
  static const String _apiKey =
      '8Kk+pmbf7TgJ9nVj2cXeA7P5zBGv8iuutVVMRfOfvNE=';
  static const String _clientKey =
      'QPJfH1Fq7Uw7CaEYQtpf2hcWqE+JgwRT6BY2ILqIUMU=';

  static const String query = 'Fürst Bismarck';

  /// Holt aktuelle Fürst-Bismarck-Angebote nahe [zipCode].
  /// [only075] filtert auf den 0,75-l-Kasten (wie das REWE-Zielprodukt).
  Future<List<ChainOffer>> fetch(String zipCode, {bool only075 = false}) async {
    final uri = Uri.parse('$_base?as=mobile&limit=40&offset=0'
        '&q=${Uri.encodeQueryComponent(query)}&zipCode=$zipCode');
    final r = await http.get(uri, headers: {
      'X-Apikey': _apiKey,
      'X-Clientkey': _clientKey,
      'Accept': 'application/json',
      'User-Agent': 'bismark-app',
    }).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return [];

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? const [];
    final offers = <ChainOffer>[];
    for (final o in results) {
      if (o is! Map) continue;
      final vol = (o['volume'] as num?)?.toDouble();
      if (only075 && vol != null && vol != 0.75) continue;
      final adv = (o['advertisers'] as List?) ?? const [];
      final chain = adv.isNotEmpty ? '${adv.first['name']}' : 'Markt';
      DateTime? to;
      final vd = (o['validityDates'] as List?) ?? const [];
      if (vd.isNotEmpty && vd.first['to'] != null) {
        to = DateTime.tryParse('${vd.first['to']}');
      }
      // Abgelaufene Angebote nicht anzeigen.
      if (to != null && to.isBefore(DateTime.now())) continue;
      // Marke + Produktname mit in die Beschreibung: marktguru packt sie in
      // eigene Felder, der Zielprodukt-Filter braucht sie aber im Text.
      final brand = '${(o['brand'] as Map?)?['name'] ?? ''}';
      final product = '${(o['product'] as Map?)?['name'] ?? ''}';
      offers.add(ChainOffer(
        chain: chain,
        description: [brand, product, '${o['description'] ?? ''}']
            .where((e) => e.trim().isNotEmpty)
            .join(' '),
        price: (o['price'] as num).toDouble(),
        oldPrice: (o['oldPrice'] as num?)?.toDouble(),
        perLiter: (o['referencePrice'] as num?)?.toDouble(),
        validTo: to,
      ));
    }
    offers.sort((a, b) => a.price.compareTo(b.price));
    return offers;
  }
}

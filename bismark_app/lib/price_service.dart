// Holt Preise direkt von der REWE-API (kein Backend, kein Cloudflare-Problem).
//
//   GET https://www.rewe.de/api/stationary-product-search/products
//        ?query=<text>&wwIdent=<marktID>
//   -> products[].pricing = {current, regular, refund}  (in Cent)
//   reduziert := current < regular
//
// Laeuft nativ auf Android (kein CORS). Pro Markt ein Request, parallel.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'markets.dart';

class PriceService {
  // Das eine Produkt: Fürst Bismarck Mineralwasser Still 12x0,75l
  static const String productId = '8016195';
  static const String productQuery = 'Fürst Bismarck Still 12x0,75l';
  static const String productName =
      'Fürst Bismarck Mineralwasser Still 12x0,75l';

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Holt alle Angebote parallel. Nur Maerkte mit REWE-`ident` werden abgefragt.
  Future<List<Offer>> fetchAll() async {
    final futures = kMarkets.map(_fetchOne);
    return Future.wait(futures);
  }

  Future<Offer> _fetchOne(Market m) async {
    if (m.retailer != 'REWE' || m.ident == null) {
      // Edeka/Aldi: noch kein Scraper -> als nicht verfuegbar fuehren.
      return Offer(market: m, available: false);
    }
    final uri = Uri.parse(
        'https://www.rewe.de/api/stationary-product-search/products'
        '?query=${Uri.encodeQueryComponent(productQuery)}&wwIdent=${m.ident}');
    try {
      final r = await http
          .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 404) return Offer(market: m, available: false);
      if (r.statusCode != 200) {
        return Offer(market: m, error: 'HTTP ${r.statusCode}');
      }
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final products = (data['products'] as List?) ?? const [];
      final prod = products.firstWhere(
        (p) => p is Map && '${p['id']}' == productId,
        orElse: () => null,
      );
      if (prod == null || prod['pricing'] == null) {
        return Offer(market: m, available: false); // nicht im Sortiment
      }
      final pr = prod['pricing'] as Map<String, dynamic>;
      final current = (pr['current'] as num).toDouble() / 100.0;
      final regular =
          ((pr['regular'] ?? pr['current']) as num).toDouble() / 100.0;
      final refund = ((pr['refund'] ?? 0) as num).toDouble() / 100.0;
      return Offer(
        market: m,
        available: true,
        price: current,
        regular: regular,
        pfand: refund,
      );
    } on TimeoutException {
      return Offer(market: m, error: 'Timeout');
    } catch (e) {
      return Offer(market: m, error: e.toString());
    }
  }
}

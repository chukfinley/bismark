// Angebote direkt bei den Ketten holen - ohne Backend, ohne marktguru.
//
// Warum: marktguru kennt nur "irgendeine Filiale dieser Kette" und liefert oft
// gar nichts (07.09.2026: 0 Treffer für Fürst Bismarck). Die Ketten selbst
// geben mehr her:
//
//   famila / Markant   Handzettel als FlipHTML5; /files/search/book_config.js
//                      enthält den Volltext aller Prospektseiten (~15-60 kB).
//   Getränke Hoffmann  PLZ-Formular setzt die Region, danach stehen die
//                      Angebote sauber im HTML der Seite /angebote.
//   Kaufland           filiale.kaufland.de hat ~2200 Angebots-Objekte als JSON
//                      im HTML der Angebotsseite (494 kB gzip).
//
// EDEKA fehlt hier bewusst: www.edeka.de sperrt Darts TLS-Fingerprint aus
// (403 von Akamai), siehe tool/probe.dart. Dafür bleibt marktguru zuständig.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'target.dart';

const String _ua = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

const Duration _timeout = Duration(seconds: 25);

/// ISO-Kalenderwoche - die Handzettel-Slugs heißen z. B. `famila_kw37_West`.
int isoWeek(DateTime d) {
  final thursday = d.add(Duration(days: 4 - (d.weekday)));
  final firstDay = DateTime(thursday.year, 1, 1);
  return ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
}

double? _num(String? s) =>
    s == null ? null : double.tryParse(s.trim().replaceAll(',', '.'));

/// Preis aus Literpreis x Gebindegröße - im Handzettel-Volltext stehen die
/// Preisziffern zerrissen ("5.\n99"), der Literpreis dagegen sauber.
double? _priceFromLiter(String text) {
  // Erst das Gebinde ("12 Flaschen à 0,75 Liter"), dann den Literpreis, der
  // DANACH steht - sonst greift man den Preis des nächsten Angebots ab.
  final vol = RegExp(
          r'(\d+)\s*(?:PET-Flaschen|Glasflaschen|Flaschen|x)\s*à?\s*([0-9]+(?:[,.][0-9]+)?)\s*Liter')
      .firstMatch(text);
  if (vol == null) return null;
  final liter = RegExp(r'1\s*Liter\s*=\s*([0-9]+[.,][0-9]{2})')
      .firstMatch(text.substring(vol.end > text.length ? text.length : vol.end));
  if (liter == null) return null;
  final perL = _num(liter.group(1));
  final count = int.tryParse(vol.group(1)!);
  final size = _num(vol.group(2));
  if (perL == null || count == null || size == null) return null;
  return double.parse((perL * count * size).toStringAsFixed(2));
}

/// Echter Preis direkt vor dem Produktnamen ("8,88 4,44 Fürst Bismarck …").
/// Gilt nur, wenn er zum Literpreis passt - sonst ist es das Nachbarangebot.
double? _exactPriceBefore(String before, double estimate, double litres) {
  final m = RegExp(r'(\d+,\d{2})\s+(?:[^\s\d]+\s+)?$').firstMatch(before);
  final exact = _num(m?.group(1));
  // Literpreis ist auf Cent gerundet: Abweichung <= 0,005 € je Liter
  if (exact == null || (exact - estimate).abs() > 0.005 * litres + 0.01) {
    return null;
  }
  return exact;
}

Future<String?> _get(String url) async {
  try {
    final r = await http
        .get(Uri.parse(url), headers: {'User-Agent': _ua})
        .timeout(_timeout);
    return r.statusCode == 200 ? r.body : null;
  } catch (_) {
    return null;
  }
}

/// Handzettel-Volltext (famila, Markant) nach dem Zielprodukt durchsuchen.
typedef OfferFilter = bool Function(String text);

bool _isTarget(String text) => matchTarget(text).isTarget;

Future<List<ChainOffer>> _leafletOffers({
  required String chain,
  required String base,
  required String slug,
  required String needle,
  required OfferFilter accept,
}) async {
  final body = await _get('$base/handzettel/$slug/files/search/book_config.js');
  if (body == null) return [];
  final m = RegExp(r'var textForPages\s*=\s*(\[[\s\S]*\])\s*;?\s*$').firstMatch(body);
  if (m == null) return [];
  List<dynamic> pages;
  try {
    pages = jsonDecode(m.group(1)!) as List<dynamic>;
  } catch (_) {
    return [];
  }
  final out = <ChainOffer>[];
  for (final page in pages) {
    final text = '$page';
    for (final hit in RegExp(needle, caseSensitive: false).allMatches(text)) {
      final seg = text.substring(
          hit.start, hit.start + 400 > text.length ? text.length : hit.start + 400);
      final desc = seg.replaceAll(RegExp(r'\s+'), ' ');
      if (!accept(desc)) continue;
      final estimate = _priceFromLiter(seg);
      if (estimate == null) continue;
      final perL = _num(RegExp(r'1\s*Liter\s*=\s*([0-9]+[.,][0-9]{2})')
          .firstMatch(seg)
          ?.group(1));
      final before =
          text.substring(hit.start - 40 < 0 ? 0 : hit.start - 40, hit.start);
      final price = (perL != null && perL > 0
              ? _exactPriceBefore(before, estimate, estimate / perL)
              : null) ??
          estimate;
      out.add(ChainOffer(
        chain: chain,
        description: desc.length > 160 ? desc.substring(0, 160) : desc,
        price: price,
        perLiter: _num(RegExp(r'1\s*Liter\s*=\s*([0-9]+[.,][0-9]{2})')
            .firstMatch(seg)
            ?.group(1)),
      ));
    }
  }
  return out;
}

class FamilaService {
  static const String base = 'https://www.famila-nordost.de';

  /// Kieler famila liegen alle in der Handzettel-Region "West".
  Future<List<ChainOffer>> fetch({
    String region = 'West',
    String needle = 'bismarck',
    OfferFilter accept = _isTarget,
  }) =>
      _leafletOffers(
          chain: 'famila',
          base: base,
          slug: 'famila_kw${isoWeek(DateTime.now())}_$region',
          needle: needle,
          accept: accept);
}

class MarkantService {
  static const String base = 'https://www.markant-online.de';

  /// Alle Markant-Märkte teilen sich den "Basis"-Handzettel.
  Future<List<ChainOffer>> fetch({
    String needle = 'bismarck',
    OfferFilter accept = _isTarget,
  }) =>
      _leafletOffers(
          chain: 'Markant',
          base: base,
          slug: 'Markant_kw${isoWeek(DateTime.now())}_Basis',
          needle: needle,
          accept: accept);
}

class HoffmannService {
  static const String base = 'https://www.getraenke-hoffmann.de';

  /// Region über die PLZ setzen, danach die Angebote der Seite lesen.
  Future<List<ChainOffer>> fetch(String zipCode,
      {OfferFilter accept = _isTarget}) async {
    try {
      final first = await http
          .get(Uri.parse('$base/angebote'), headers: {'User-Agent': _ua})
          .timeout(_timeout);
      if (first.statusCode != 200) return [];
      final build = RegExp(r'name="form_build_id" value="([^"]+)"')
          .firstMatch(first.body)
          ?.group(1);
      var html = first.body;
      if (build != null) {
        final cookie = first.headers['set-cookie']?.split(';').first;
        final res = await http.post(
          Uri.parse('$base/angebote'),
          headers: {
            'User-Agent': _ua,
            'Content-Type': 'application/x-www-form-urlencoded',
            if (cookie != null) 'Cookie': cookie,
          },
          body: {
            'plz': zipCode,
            'op': 'OK',
            'form_build_id': build,
            'form_id': 'choose_branch_form',
          },
        ).timeout(_timeout);
        if (res.statusCode == 200 && res.body.length > 1000) html = res.body;
      }
      return _parse(html, accept);
    } catch (_) {
      return [];
    }
  }

  List<ChainOffer> _parse(String html, OfferFilter accept) {
    final out = <ChainOffer>[];
    final block = RegExp(
        r'<h3 class="p-sliderelement__headline">(.*?)</h3>\s*'
        r'<div class="p-sliderelement__text">(.*?)</div>',
        dotAll: true);
    for (final m in block.allMatches(html)) {
      final title = _strip(m.group(1)!);
      final body = m.group(2)!;
      final text = _strip(body);
      if (!accept('$title $text')) continue;
      final price = _num(RegExp(r'<p class="red-big">\s*([0-9]+[.,][0-9]{2})\s*EUR')
          .firstMatch(body)
          ?.group(1));
      if (price == null) continue;
      out.add(ChainOffer(
        chain: 'Getränke Hoffmann',
        description: '$title, $text',
        price: price,
        perLiter: _num(RegExp(r'Liter:\s*([0-9]+[.,][0-9]{2})').firstMatch(text)?.group(1)),
      ));
    }
    return out;
  }
}

class KauflandService {
  static const String offers =
      'https://filiale.kaufland.de/angebote/uebersicht.html';

  Future<List<ChainOffer>> fetch({
    String needle = 'bismarck',
    OfferFilter accept = _isTarget,
  }) async {
    final html = await _get(offers);
    if (html == null) return [];
    final out = <ChainOffer>[];
    final seen = <String>{};
    for (final hit in RegExp(needle, caseSensitive: false).allMatches(html)) {
      final obj = _enclosingObject(html, hit.start);
      if (obj == null) continue;
      Map<String, dynamic> o;
      try {
        o = jsonDecode(obj) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final desc = [
        o['title'], o['subtitle'], o['detailDescription'], o['basePrice'], o['unit']
      ].where((e) => e != null).join(' ');
      if (!accept(desc)) continue;
      final price = o['price'];
      if (price is! num) continue;
      if (!seen.add('${o['offerId']}')) continue;
      out.add(ChainOffer(
        chain: 'Kaufland',
        description: desc,
        price: price.toDouble(),
        oldPrice: _num('${o['formattedOldPrice'] ?? ''}'),
      ));
    }
    return out;
  }

  /// Das JSON-Objekt suchen, in dem der Treffer steht (Klammern zählen).
  String? _enclosingObject(String s, int index) {
    var start = s.lastIndexOf('{"offerId"', index);
    if (start < 0) return null;
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == r'\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }
}

String _strip(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>'), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Alle Ketten parallel abfragen; jede Quelle darf einzeln ausfallen.
Future<List<ChainOffer>> fetchAllChainOffers(String zipCode) async {
  final results = await Future.wait<List<ChainOffer>>([
    FamilaService().fetch(),
    MarkantService().fetch(),
    HoffmannService().fetch(zipCode),
    KauflandService().fetch(),
  ]);
  return results.expand((e) => e).toList();
}

// Prueft, ob die Ketten-Quellen mit Darts HTTP-Stack erreichbar sind
// (Akamai/Cloudflare mögen manche TLS-Fingerprints nicht).
import 'dart:io';

Future<void> main() async {
  final urls = {
    'EDEKA': 'https://www.edeka.de/maerkte/211152/angebote/',
    'EDEKA-Marktsuche': 'https://www.edeka.de/api/marketsearch/markets?searchstring=24238',
    'Kaufland': 'https://filiale.kaufland.de/angebote/uebersicht.html',
    'Kaufland-Stores': 'https://filiale.kaufland.de/.klstorebygeo.json?lat=54.32&lng=10.13',
    'Hoffmann': 'https://www.getraenke-hoffmann.de/angebote',
    'famila': 'https://www.famila-nordost.de/handzettel/famila_kw37_West/files/search/book_config.js',
    'Markant': 'https://www.markant-online.de/handzettel/Markant_kw37_Basis/files/search/book_config.js',
  };
  final client = HttpClient();
  client.userAgent = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  for (final e in urls.entries) {
    try {
      final req = await client.getUrl(Uri.parse(e.value));
      final res = await req.close();
      var bytes = 0;
      await for (final chunk in res) {
        bytes += chunk.length;
      }
      print('${res.statusCode}  ${(bytes / 1024).toStringAsFixed(0)} KB  ${e.key}');
    } catch (err) {
      print('ERR ${e.key}: $err');
    }
  }
  client.close();
}

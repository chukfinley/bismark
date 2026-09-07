// Live-Test der Ketten-Services gegen die echten Seiten.
//   dart run tool/check_chains.dart [PLZ]
// Zeigt erst die Treffer fuer das Zielprodukt, dann als Funktionsprobe alle
// Mineralwasser-Angebote (damit man sieht: 0 Treffer heisst "kein Angebot",
// nicht "Scraper kaputt").
import '../lib/chain_offer_service.dart';
import '../lib/target.dart';

bool any(String _) => true;

Future<void> main(List<String> args) async {
  final zip = args.isNotEmpty ? args[0] : '24238';
  print('KW ${isoWeek(DateTime.now())}, PLZ $zip');

  print('\n== Zielprodukt (Fürst Bismarck Still 12x0,75 l Glas) ==');
  for (final e in {
    'famila': FamilaService().fetch(),
    'Markant': MarkantService().fetch(),
    'Getränke Hoffmann': HoffmannService().fetch(zip),
    'Kaufland': KauflandService().fetch(),
  }.entries) {
    final res = await e.value;
    print('${e.key}: ${res.length}');
    for (final o in res) {
      print('   ${o.price} €  ${o.description}');
    }
  }

  print('\n== Funktionsprobe: alle Wasser-Angebote der Quelle ==');
  final probes = {
    'famila': FamilaService().fetch(needle: 'Mineralwasser', accept: any),
    'Markant': MarkantService().fetch(needle: 'Mineralwasser', accept: any),
    'Getränke Hoffmann': HoffmannService().fetch(zip, accept: any),
    'Kaufland': KauflandService().fetch(needle: 'Mineralwasser', accept: any),
  };
  for (final e in probes.entries) {
    final res = await e.value;
    print('${e.key}: ${res.length} Angebote gelesen');
    for (final o in res.take(3)) {
      final d = o.description;
      print('   ${o.price} €  ${d.length > 90 ? d.substring(0, 90) : d}');
    }
  }

  print('\n== Filter-Gegenprobe ==');
  for (final c in [
    'Fürst Bismarck Mineralwasser Classic, Medium oder Still 12 x 0,75 l Glas + Pfand 3,30 €',
    'Fürst Bismarck Mineralwasser verschiedene Sorten 12 PET-Flaschen à 1 Liter',
    'Hella Mineralwasser versch. Sorten, 12 x 1 L',
  ]) {
    print('  ${matchTarget(c).isTarget ? "JA " : "nein"}  $c');
  }
}

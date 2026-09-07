// Das EINE Zielprodukt: Fürst Bismarck Mineralwasser **Still**,
// Kasten 12 x 0,75 l Glas (Mehrweg, 3,30 € Pfand).
//
// Alles andere Wasser interessiert nicht - auch nicht Fürst Bismarck in
// anderen Gebinden (z. B. 12 x 1 l PET). Angebotstexte der Ketten sind frei
// formuliert, darum wird auf drei Merkmale geprüft:
//   1. Marke  "Fürst Bismarck" (oder nur "Bismarck")
//   2. Gebinde 0,75 l  und  12er-Kasten
//   3. Sorte  Still - entweder ausdrücklich, oder als Sammelangebot
//             ("Classic, Medium oder Still", "versch. Sorten"), das Still
//             mit einschließt.

class TargetMatch {
  final bool isTarget;
  final bool stillExplicit; // "Still" steht wirklich im Text
  const TargetMatch(this.isTarget, this.stillExplicit);
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('ü', 'u')
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Prüft einen Angebotstext (Titel + Beschreibung zusammen) auf das Zielprodukt.
TargetMatch matchTarget(String text) {
  final t = _norm(text);

  if (!t.contains('bismarck')) return const TargetMatch(false, false);

  // 0,75 l - als "0,75", "0.75" oder "750 ml"
  final has075 = t.contains('0,75') || t.contains('0.75') || t.contains('750 ml');
  if (!has075) return const TargetMatch(false, false);

  // 12er-Kasten
  final has12 = RegExp(r'12\s*(?:x|st|flaschen|glas|kasten|\*)').hasMatch(t) ||
      RegExp(r'(?:kasten|kiste)\s*12').hasMatch(t) ||
      t.contains('12 x 0,75') ||
      t.contains('12x0,75');
  if (!has12) return const TargetMatch(false, false);

  // PET/Einweg ist ein anderes Produkt
  if (t.contains('pet') || t.contains('einweg')) return const TargetMatch(false, false);

  final stillExplicit = RegExp(r'\bstill\b').hasMatch(t);
  final collective = t.contains('versch') || // "versch. Sorten"
      t.contains('verschiedene sorten') ||
      t.contains('alle sorten') ||
      t.contains('sortenrein');
  if (!stillExplicit && !collective) return const TargetMatch(false, false);

  return TargetMatch(true, stillExplicit);
}

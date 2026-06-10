// Öffnet den Markt in der Standard-Karten-/Geo-App via geo:-URI.
// Kein Google-Maps-Link. geo: wird DIREKT gestartet (nicht über
// canLaunchUrl, das auf Android 11+ ohne <queries> fälschlich false liefert).
import 'package:url_launcher/url_launcher.dart';

Future<void> openInMaps({
  String? name,
  double? lat,
  double? lon,
  String? address,
}) async {
  final label = Uri.encodeComponent(name ?? '');
  final Uri geo;
  if (lat != null && lon != null) {
    // Pin auf Koordinate, mit Label.
    geo = Uri.parse('geo:$lat,$lon?q=$lat,$lon($label)');
  } else {
    geo = Uri.parse('geo:0,0?q=${Uri.encodeComponent(address ?? name ?? '')}');
  }
  try {
    final ok = await launchUrl(geo, mode: LaunchMode.externalApplication);
    if (ok) return;
  } catch (_) {
    // keine Geo-App -> harter Fallback unten
  }
  // Letzter Ausweg, falls gar keine Karten-App vorhanden ist.
  final q = (lat != null && lon != null)
      ? '$lat,$lon'
      : Uri.encodeComponent(address ?? name ?? '');
  await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
      mode: LaunchMode.externalApplication);
}

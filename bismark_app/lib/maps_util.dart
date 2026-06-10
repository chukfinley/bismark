// Gemeinsamer Karten-Launcher: öffnet den Markt in der Standard-Karten-App
// (Android geo:) bzw. Google Maps als Fallback. Von Liste UND Karte genutzt.
import 'package:url_launcher/url_launcher.dart';

Future<void> openInMaps({
  String? name,
  double? lat,
  double? lon,
  String? address,
}) async {
  final hasCoords = lat != null && lon != null;
  final q = hasCoords ? '$lat,$lon' : Uri.encodeComponent(address ?? name ?? '');
  final label = Uri.encodeComponent(name ?? '');
  final geo = Uri.parse('geo:0,0?q=$q($label)');
  final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  if (await canLaunchUrl(geo)) {
    await launchUrl(geo, mode: LaunchMode.externalApplication);
  } else {
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }
}

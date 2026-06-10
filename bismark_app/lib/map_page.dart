import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'markets.dart';

class MapPage extends StatefulWidget {
  final Future<List<Offer>> future;
  const MapPage({super.key, required this.future});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  LatLng? _me;
  Map<String, Offer> _byMarket = {};

  @override
  void initState() {
    super.initState();
    widget.future.then((offers) {
      if (!mounted) return;
      setState(() {
        _byMarket = {
          for (final o in offers) o.market.name + o.market.address: o
        };
      });
    });
  }

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Standortfreigabe verweigert.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() => _me = me);
      _map.move(me, 12);
    } catch (e) {
      _snack('Standort fehlgeschlagen: $e');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Color _color(Market m) {
    switch (m.retailer) {
      case 'REWE':
        return const Color(0xFFCC0000);
      case 'EDEKA':
        return const Color(0xFF005CA9);
      case 'ALDI':
        return const Color(0xFF00457C);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pins = kMarkets.where((m) => m.lat != null && m.lon != null).toList();
    final center = pins.isEmpty
        ? const LatLng(54.32, 10.13)
        : LatLng(
            pins.map((m) => m.lat!).reduce((a, b) => a + b) / pins.length,
            pins.map((m) => m.lon!).reduce((a, b) => a + b) / pins.length,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Märkte-Karte')),
      floatingActionButton: FloatingActionButton(
        onPressed: _locate,
        tooltip: 'Mein Standort',
        child: const Icon(Icons.my_location),
      ),
      body: FlutterMap(
        mapController: _map,
        options: MapOptions(initialCenter: center, initialZoom: 11),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'dev.chuk.bismark_app',
          ),
          MarkerLayer(
            markers: [
              ...pins.map((m) {
                final offer = _byMarket[m.name + m.address];
                final reduced = offer?.reduced ?? false;
                return Marker(
                  point: LatLng(m.lat!, m.lon!),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => _showMarket(m, offer),
                    child: Icon(Icons.location_on,
                        color: _color(m),
                        size: reduced ? 44 : 34,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 3)
                        ]),
                  ),
                );
              }),
              if (_me != null)
                Marker(
                  point: _me!,
                  width: 24,
                  height: 24,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.circle, color: Colors.white, size: 10),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMarket(Market m, Offer? o) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.name, style: Theme.of(context).textTheme.titleLarge),
            Text(m.address),
            const SizedBox(height: 12),
            if (o != null && o.available && o.total != null)
              Text('${o.total!.toStringAsFixed(2)} €'
                  '${o.reduced ? '  🔻 reduziert (statt ${(o.regular! + o.pfand!).toStringAsFixed(2)} €)' : ''}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: o.reduced ? Theme.of(context).colorScheme.error : null))
            else
              Text(m.retailer == 'REWE'
                  ? 'Nicht im Sortiment dieses Marktes'
                  : 'Preis für ${m.retailer} noch nicht verfügbar'),
          ],
        ),
      ),
    );
  }
}

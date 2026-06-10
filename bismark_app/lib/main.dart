import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'price_service.dart';
import 'offer_service.dart';
import 'map_page.dart';

void main() => runApp(const BismarkApp());

double haversineKm(double aLat, double aLon, double bLat, double bLon) {
  const r = 6371.0;
  final dLat = (bLat - aLat) * math.pi / 180;
  final dLon = (bLon - aLon) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(aLat * math.pi / 180) *
          math.cos(bLat * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

class BismarkApp extends StatelessWidget {
  const BismarkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bismark Wasser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0077C8), useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _priceService = PriceService();
  final _offerService = OfferService();

  List<Offer> _offers = [];
  List<ChainOffer> _chainOffers = [];
  Position? _pos;
  bool _loading = true;
  final String _zip = '24114';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _priceService.fetchAll(),
      _offerService.fetch(_zip),
    ]);
    _offers = results[0] as List<Offer>;
    _chainOffers = results[1] as List<ChainOffer>;
    _applyDistance();
    if (mounted) setState(() => _loading = false);
  }

  void _applyDistance() {
    if (_pos == null) return;
    for (final o in _offers) {
      final m = o.market;
      if (m.lat != null && m.lon != null) {
        o.distanceKm =
            haversineKm(_pos!.latitude, _pos!.longitude, m.lat!, m.lon!);
      }
    }
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
      setState(() {
        _pos = pos;
        _applyDistance();
      });
      _snack('Standort aktiv – sortiere nach Entfernung.');
    } catch (e) {
      _snack('Standort fehlgeschlagen: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Sortierung: günstigster Warenpreis zuerst; bei Gleichstand der nächste.
  int _cmp(Offer a, Offer b) {
    final byPrice = a.price!.compareTo(b.price!);
    if (byPrice != 0) return byPrice;
    final da = a.distanceKm, db = b.distanceKm;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  @override
  Widget build(BuildContext context) {
    final have = _offers.where((o) => o.available && o.price != null).toList()
      ..sort(_cmp);
    final reduced = have.where((o) => o.reduced).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bismark Wasser'),
        actions: [
          IconButton(
            icon: Icon(_pos == null ? Icons.location_searching : Icons.my_location),
            tooltip: 'Nach Entfernung sortieren',
            onPressed: _locate,
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Karte',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MapPage(future: Future.value(_offers))),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (have.isNotEmpty)
                    _HeroCard(best: have.first, locationOn: _pos != null),
                  const SizedBox(height: 8),
                  if (_chainOffers.isNotEmpty) ...[
                    _SectionTitle('🔻 Angebote diese Woche (alle Ketten · PLZ $_zip)'),
                    ..._chainOffers.map((c) => _ChainOfferTile(c)),
                    const SizedBox(height: 8),
                  ],
                  if (reduced.isNotEmpty) ...[
                    const _SectionTitle('🔻 REWE reduziert'),
                    ...reduced.map((o) => _OfferTile(o)),
                    const SizedBox(height: 8),
                  ],
                  const _SectionTitle('REWE-Märkte (Live-Preis)'),
                  ...have.map((o) => _OfferTile(o)),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.map_outlined),
                      label: Text('${_offers.length} Läden auf der Karte'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                MapPage(future: Future.value(_offers))),
                      ),
                    ),
                  ),
                  if (_pos == null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Tipp: Standort-Button oben → bei gleichem Preis wird '
                        'der nächstgelegene Markt zuerst angezeigt.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final Offer best;
  final bool locationOn;
  const _HeroCard({required this.best, required this.locationOn});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dist = best.distanceKm;
    return Card(
      elevation: 2,
      color: best.reduced ? cs.tertiaryContainer : cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locationOn ? 'Günstigster Markt (nächster bei Gleichstand)'
                            : 'Günstigster Markt',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${best.price!.toStringAsFixed(2)} €',
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                if (best.reduced)
                  Text('statt ${best.regular!.toStringAsFixed(2)} €',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          decoration: TextDecoration.lineThrough, color: cs.error)),
              ],
            ),
            Text('+ ${best.pfand!.toStringAsFixed(2)} € Pfand (zurück) · '
                'mit Pfand ${best.total!.toStringAsFixed(2)} €',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Text(best.market.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(best.market.address,
                style: Theme.of(context).textTheme.bodyMedium),
            if (dist != null)
              Text('${dist.toStringAsFixed(1)} km entfernt',
                  style: TextStyle(
                      color: cs.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _OfferTile extends StatelessWidget {
  final Offer o;
  const _OfferTile(this.o);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dist = o.distanceKm;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: o.reduced ? cs.errorContainer : cs.secondaryContainer,
          child: const Text('R', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(o.market.name),
        subtitle: Text(dist != null
            ? '${o.market.address}\n${dist.toStringAsFixed(1)} km entfernt'
            : o.market.address),
        isThreeLine: dist != null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${o.price!.toStringAsFixed(2)} €',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: o.reduced ? cs.error : null)),
            if (o.reduced)
              Text('statt ${o.regular!.toStringAsFixed(2)} €',
                  style: const TextStyle(
                      fontSize: 11, decoration: TextDecoration.lineThrough)),
            Text('+${o.pfand!.toStringAsFixed(2)} € Pfand',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _ChainOfferTile extends StatelessWidget {
  final ChainOffer c;
  const _ChainOfferTile(this.c);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String? gueltig;
    if (c.validTo != null) {
      gueltig = 'bis ${c.validTo!.day}.${c.validTo!.month}.';
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: cs.tertiaryContainer.withValues(alpha: 0.5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.tertiaryContainer,
          child: Text(c.chain.isNotEmpty ? c.chain[0] : '?',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(c.chain,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            gueltig == null ? c.description : '${c.description}\n$gueltig'),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${c.price.toStringAsFixed(2)} €',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17, color: cs.error)),
            if (c.oldPrice != null)
              Text('statt ${c.oldPrice!.toStringAsFixed(2)} €',
                  style: const TextStyle(
                      fontSize: 11, decoration: TextDecoration.lineThrough)),
          ],
        ),
      ),
    );
  }
}

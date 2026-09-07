import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'markets.dart';
import 'chain_offer_service.dart';
import 'deal.dart';
import 'price_service.dart';
import 'offer_service.dart';
import 'maps_util.dart';
import 'map_page.dart';

void main() => runApp(const BismarkApp());

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
  final _zipCtrl = TextEditingController(text: '24238');

  List<Offer> _rewe = [];
  List<ChainOffer> _chain = [];
  List<Deal> _deals = [];
  Position? _pos;
  bool _loading = true;
  double _refLat = 54.3233;
  double _refLon = 10.1394;

  String get _zip => _zipCtrl.text.trim().isEmpty ? '24238' : _zipCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _zipCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await Future.wait([
      _priceService.fetchAll(),
      _offerService.fetch(_zip),
      fetchAllChainOffers(_zip),
    ]);
    _rewe = res[0] as List<Offer>;
    _chain = [
      ...res[1] as List<ChainOffer>,
      ...res[2] as List<ChainOffer>,
    ];
    _rebuild();
    if (mounted) setState(() => _loading = false);
  }

  /// Nur Angebote (marktguru) neu laden – z.B. nach PLZ-Änderung.
  Future<void> _reloadOffers() async {
    setState(() => _loading = true);
    final res = await Future.wait([
      _offerService.fetch(_zip),
      fetchAllChainOffers(_zip),
    ]);
    _chain = [...res[0], ...res[1]];
    _rebuild();
    if (mounted) setState(() => _loading = false);
  }

  void _rebuild() {
    final ref = _pos != null
        ? [_pos!.latitude, _pos!.longitude]
        : plzCentroid(_zip);
    _refLat = ref[0];
    _refLon = ref[1];
    _deals = buildDeals(_rewe, _chain, _refLat, _refLon);
  }

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Standortfreigabe verweigert – nutze PLZ $_zip.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _pos = pos;
        _rebuild();
      });
      _snack('Standort aktiv – sortiert nach Nähe bei gleichem Preis.');
    } catch (e) {
      _snack('Standort fehlgeschlagen: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _openDeal(Deal d) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _DealSheet(d),
    );
  }

  /// Angepinnte Stammmärkte: REWE Raisdorf (Live-Preis) + EDEKA Ley Selent
  /// (Preis nur wenn diese Woche ein Angebot läuft).
  List<Market> _favoriteMarkets() {
    final favs = <Market>[];
    for (final m in kMarkets) {
      if (m.ident == kFavoriteIdent) favs.add(m); // REWE Schröder Raisdorf
    }
    for (final m in kMarkets) {
      if (m.retailer == 'EDEKA' && m.address.contains('24238')) {
        favs.add(m); // EDEKA Ley, Selent
        break;
      }
    }
    return favs;
  }

  /// Findet das zum Stammmarkt passende Deal (Live-Preis oder Ketten-Angebot).
  Deal? _dealFor(Market m) {
    for (final d in _deals) {
      if (m.ident != null && d.ident == m.ident) return d;
      if (m.ident == null &&
          d.retailer == m.retailer &&
          d.address == m.address) {
        return d;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bismark Wasser'),
        actions: [
          IconButton(
            icon: Icon(_pos == null ? Icons.location_searching : Icons.my_location),
            tooltip: 'Standort nutzen',
            onPressed: _locate,
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Karte',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MapPage(future: Future.value(_rewe))),
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
                  _PlzBar(
                    controller: _zipCtrl,
                    pos: _pos,
                    onSubmit: _reloadOffers,
                  ),
                  const SizedBox(height: 8),
                  if (_deals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('Keine Preise gefunden.')),
                    )
                  else ...[
                    ..._favoriteMarkets().map((m) {
                      final deal = _dealFor(m);
                      final dist = (m.lat != null && m.lon != null)
                          ? haversineKm(_refLat, _refLon, m.lat!, m.lon!)
                          : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FavoriteCard(
                          market: m,
                          deal: deal,
                          distanceKm: dist,
                          onTap: () => deal != null
                              ? _openDeal(deal)
                              : openInMaps(
                                  name: m.name,
                                  lat: m.lat,
                                  lon: m.lon,
                                  address: m.address),
                        ),
                      );
                    }),
                    _HeroCard(best: _deals.first, onTap: () => _openDeal(_deals.first)),
                    const SizedBox(height: 8),
                    const _SectionTitle('Alle Preise & Angebote – günstigster zuerst'),
                    ..._deals.map((d) => _DealTile(d, onTap: () => _openDeal(d))),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.map_outlined),
                      label: Text('${kMarketsCount()} Läden auf der Karte'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MapPage(future: Future.value(_rewe))),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

int kMarketsCount() => kMarkets.length;

class _PlzBar extends StatelessWidget {
  final TextEditingController controller;
  final Position? pos;
  final VoidCallback onSubmit;
  const _PlzBar(
      {required this.controller, required this.pos, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 5,
                decoration: const InputDecoration(
                  labelText: 'Deine PLZ (für Angebote)',
                  counterText: '',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            if (pos != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.my_location, size: 16, color: Colors.blue),
              ),
            TextButton(onPressed: onSubmit, child: const Text('Laden')),
          ],
        ),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final Market market;
  final Deal? deal;
  final double? distanceKm;
  final VoidCallback onTap;
  const _FavoriteCard(
      {required this.market,
      required this.deal,
      required this.distanceKm,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = deal?.reduced ?? false;
    return Card(
      elevation: 1,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.primary, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.star, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dein Markt · ${_retailerLabel(market.retailer)}',
                        style: Theme.of(context).textTheme.labelMedium),
                    Text(market.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(market.address,
                        style: Theme.of(context).textTheme.bodySmall),
                    if (distanceKm != null)
                      Text('${distanceKm!.toStringAsFixed(1)} km',
                          style: TextStyle(color: cs.primary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (deal != null) ...[
                    Text('${deal!.price.toStringAsFixed(2)} €',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: reduced ? cs.error : null)),
                    if (reduced)
                      Text('statt ${deal!.strike!.toStringAsFixed(2)} €',
                          style: const TextStyle(
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough)),
                    Text('+${deal!.pfand.toStringAsFixed(2)} € Pfand',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                  ] else
                    SizedBox(
                      width: 110,
                      child: Text('Diese Woche kein Online-Angebot',
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  const Icon(Icons.directions, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final Deal best;
  final VoidCallback onTap;
  const _HeroCard({required this.best, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      color: best.reduced ? cs.tertiaryContainer : cs.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Günstigster Preis',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${best.price.toStringAsFixed(2)} €',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  if (best.reduced)
                    Text('statt ${best.strike!.toStringAsFixed(2)} €',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: cs.error)),
                ],
              ),
              Text('+ ${best.pfand.toStringAsFixed(2)} € Pfand (zurück)',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Text('${_retailerLabel(best.retailer)} · ${best.title}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (best.address != null) Text(best.address!),
              Row(
                children: [
                  if (best.distanceKm != null)
                    Text('${best.distanceKm!.toStringAsFixed(1)} km · ',
                        style: TextStyle(
                            color: cs.primary, fontWeight: FontWeight.w600)),
                  if (best.isOffer)
                    Text(best.validTo != null
                        ? 'Angebot bis ${best.validTo!.day}.${best.validTo!.month}.'
                        : 'Aktuelles Angebot',
                        style: TextStyle(color: cs.error)),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.directions),
                label: const Text('Hinfahren – in Maps öffnen'),
                onPressed: () => openInMaps(
                    name: best.title,
                    lat: best.lat,
                    lon: best.lon,
                    address: best.address),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _retailerLabel(String code) {
  switch (code) {
    case 'GETRAENKE_HOFFMANN':
      return 'Getränke Hoffmann';
    case 'NETTO':
      return 'Netto';
    default:
      return code[0] + code.substring(1).toLowerCase();
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

class _DealTile extends StatelessWidget {
  final Deal d;
  final VoidCallback onTap;
  const _DealTile(this.d, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = <String>[
      if (d.address != null) d.address!,
      [
        if (d.distanceKm != null) '${d.distanceKm!.toStringAsFixed(1)} km',
        if (d.isOffer)
          (d.validTo != null
              ? 'Angebot bis ${d.validTo!.day}.${d.validTo!.month}.'
              : 'Angebot'),
      ].join(' · '),
    ].where((s) => s.trim().isNotEmpty).join('\n');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: d.reduced ? cs.errorContainer : cs.secondaryContainer,
          child: Text(d.retailer[0],
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text('${_retailerLabel(d.retailer)} · ${d.title}'),
        subtitle: Text(sub),
        isThreeLine: sub.contains('\n'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${d.price.toStringAsFixed(2)} €',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: d.reduced ? cs.error : null)),
            if (d.reduced)
              Text('statt ${d.strike!.toStringAsFixed(2)} €',
                  style: const TextStyle(
                      fontSize: 11, decoration: TextDecoration.lineThrough)),
            Text('+${d.pfand.toStringAsFixed(2)} € Pfand',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _DealSheet extends StatelessWidget {
  final Deal d;
  const _DealSheet(this.d);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_retailerLabel(d.retailer)} · ${d.title}',
              style: Theme.of(context).textTheme.titleLarge),
          if (d.address != null) Text(d.address!),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${d.price.toStringAsFixed(2)} €',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: d.reduced ? cs.error : null)),
              const SizedBox(width: 8),
              if (d.reduced)
                Text('statt ${d.strike!.toStringAsFixed(2)} €',
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough)),
            ],
          ),
          Text('+ ${d.pfand.toStringAsFixed(2)} € Pfand (zurück) · '
              'mit Pfand ${d.total.toStringAsFixed(2)} €',
              style: Theme.of(context).textTheme.bodySmall),
          if (d.offerDesc != null && d.offerDesc!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(d.offerDesc!),
            ),
          if (d.isOffer && d.validTo != null)
            Text('Angebot gültig bis ${d.validTo!.day}.${d.validTo!.month}.',
                style: TextStyle(color: cs.error)),
          if (d.distanceKm != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${d.distanceKm!.toStringAsFixed(1)} km entfernt'),
            ),
          if (d.isOffer)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Angebot gilt für ${_retailerLabel(d.retailer)} in '
                  'deiner Nähe – nächster Markt angezeigt.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.directions),
              label: const Text('Hinfahren – Route in Maps öffnen'),
              onPressed: () => openInMaps(
                  name: d.title,
                  lat: d.lat,
                  lon: d.lon,
                  address: d.address),
            ),
          ),
        ],
      ),
    );
  }
}

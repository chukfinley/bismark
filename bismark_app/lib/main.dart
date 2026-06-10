import 'package:flutter/material.dart';

import 'models.dart';
import 'price_service.dart';
import 'map_page.dart';

void main() => runApp(const BismarkApp());

class BismarkApp extends StatelessWidget {
  const BismarkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bismark Wasser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0077C8),
        useMaterial3: true,
      ),
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
  final _service = PriceService();
  Future<List<Offer>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchAll();
  }

  Future<void> _refresh() async {
    final f = _service.fetchAll();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bismark Wasser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Karte',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MapPage(future: _future ?? Future.value([]))),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Offer>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 120),
                Center(child: Text('Fehler: ${snap.error}')),
              ]);
            }
            final offers = snap.data ?? const [];
            final have = offers
                .where((o) => o.available && o.total != null)
                .toList()
              ..sort((a, b) => a.total!.compareTo(b.total!));
            final reduced = have.where((o) => o.reduced).toList();

            if (have.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('Kein Markt mit Preis gefunden.')),
              ]);
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _HeroCard(best: have.first, reducedCount: reduced.length),
                const SizedBox(height: 8),
                if (reduced.isNotEmpty) ...[
                  const _SectionTitle('🔻 Aktuell reduziert'),
                  ...reduced.map((o) => _OfferTile(o)),
                  const SizedBox(height: 8),
                ],
                const _SectionTitle('REWE-Märkte (Live-Preis)'),
                ...have.map((o) => _OfferTile(o)),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                        '${offers.length} Läden gesamt auf der Karte '
                        '(Edeka, Kaufland, famila … – Angebote folgen)'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              MapPage(future: Future.value(offers))),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final Offer best;
  final int reducedCount;
  const _HeroCard({required this.best, required this.reducedCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = reducedCount > 0;
    return Card(
      elevation: 2,
      color: active ? cs.tertiaryContainer : cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(active
                ? 'Günstigster Preis (Angebot aktiv!)'
                : 'Günstigster Preis',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${best.total!.toStringAsFixed(2)} €',
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Text('inkl. ${best.pfand!.toStringAsFixed(2)} € Pfand',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            if (best.reduced)
              Text('Ware ${best.price!.toStringAsFixed(2)} € statt '
                  '${best.regular!.toStringAsFixed(2)} €  '
                  '(−${best.saving!.toStringAsFixed(2)} €)',
                  style: TextStyle(
                      color: cs.error, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(best.market.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(best.market.address,
                style: Theme.of(context).textTheme.bodyMedium),
            if (reducedCount > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('$reducedCount Märkte haben gerade ein Angebot.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              o.reduced ? cs.errorContainer : cs.secondaryContainer,
          child: Text(o.market.retailer == 'REWE' ? 'R' : o.market.retailer[0],
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(o.market.name),
        subtitle: Text(o.market.address),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${o.total!.toStringAsFixed(2)} €',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: o.reduced ? cs.error : null)),
            if (o.reduced)
              Text('statt ${(o.regular! + o.pfand!).toStringAsFixed(2)} €',
                  style: const TextStyle(
                      fontSize: 11, decoration: TextDecoration.lineThrough)),
          ],
        ),
      ),
    );
  }
}

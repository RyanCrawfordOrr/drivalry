import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:flutter/material.dart';

import '../../app/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db/database.dart';
import '../../packs/pack_manager.dart';
import '../../packs/pack_providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/friendly_error.dart';

/// Installed speed-limit packs and the catalogue (docs/03 §4.3).
class PacksScreen extends ConsumerStatefulWidget {
  const PacksScreen({super.key});

  @override
  ConsumerState<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends ConsumerState<PacksScreen> {
  PackIndex? _index;
  bool _busy = false;
  double? _progress;
  String? _message;

  PackManager get _manager => ref.read(packManagerProvider);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _progress = null;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _message = friendlyError(e, doing: 'update the packs'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshCatalogue() => _run(() async {
    final index = await _manager.refreshIndex(force: true);
    setState(() {
      _index = index;
      _message = index == null ? 'Could not load the catalogue.' : null;
    });
  });

  Future<void> _install(PackIndexEntry e) => _run(() async {
    await _manager.install(e, onProgress: (f) => setState(() => _progress = f));
    setState(() => _message = 'Installed ${e.name}.');
  });

  Future<void> _installForLocation() => _run(() async {
    final live = ref.read(trackingControllerProvider).live;
    double? lat = live?.lastLat;
    double? lon = live?.lastLon;
    if (lat == null || lon == null) {
      final trips = await ref
          .read(databaseProvider)
          .watchRecentTrips(limit: 1)
          .first;
      if (trips.isNotEmpty) {
        final samples = await ref
            .read(databaseProvider)
            .samplesFor(trips.first.trip.id);
        if (samples.isNotEmpty) {
          lat = samples.last.lat;
          lon = samples.last.lon;
        }
      }
    }
    if (lat == null || lon == null) {
      setState(() => _message = 'No location known yet. Take a drive first.');
      return;
    }
    final pack = await _manager.ensureRegionFor(
      lat,
      lon,
      force: true,
      onProgress: (f) => setState(() => _progress = f),
    );
    setState(
      () => _message = pack == null
          ? 'No speed-limit pack covers your area yet.'
          : 'Installed ${pack.name}.',
    );
  });

  Future<void> _importFromUrl() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => TextControllers(
        builder: (ctx, c) => AlertDialog(
          title: const Text('Paste a pack link'),
          content: TextField(
            controller: c.first,
            decoration: const InputDecoration(hintText: 'https://…/us-dc.pack'),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.first.text.trim()),
              child: const Text('Download'),
            ),
          ],
        ),
      ),
    );
    if (url == null || url.isEmpty) return;
    await _run(() async {
      final pack = await _manager.importFromUrl(
        url,
        onProgress: (f) => setState(() => _progress = f),
      );
      setState(() => _message = 'Installed ${pack.name}.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final installed = ref.watch(installedPacksProvider).value ?? const <Pack>[];
    final installedRegions = {for (final p in installed) p.region};

    return Scaffold(
      appBar: AppBar(title: const Text('Speed-limit packs')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'The roads and posted limits for one region, kept on your phone. '
            'Nothing is looked up online while you drive.',
            style: context.bodyMuted,
          ),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _installForLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Install for my location'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshCatalogue,
                icon: const Icon(Icons.refresh),
                label: const Text('Catalogue'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importFromUrl,
                icon: const Icon(Icons.link),
                label: const Text('Paste a link'),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: Space.lg),
            LinearProgressIndicator(value: _progress),
          ],
          if (_message != null) ...[
            const SizedBox(height: Space.md),
            Text(_message!, style: context.caption),
          ],
          const SizedBox(height: Space.section),
          const Kicker('Installed'),
          const SizedBox(height: Space.md),
          if (installed.isEmpty)
            Text(
              'None yet. Trips are still recorded and scored for smoothness, '
              'attention and efficiency; speeding stays silent until a pack '
              'covers your area.',
              style: context.bodyMuted,
            ),
          for (final (i, p) in installed.indexed) ...[
            if (i > 0) const SizedBox(height: Space.md),
            Tile(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.sm,
                Space.lg,
              ),
              child: Row(
                children: [
                  Icon(Icons.map_outlined, color: scheme.primary),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: context.title),
                        const SizedBox(height: Space.xs),
                        Text(
                          '${p.region} · OSM ${_date(p.osmTimestamp)} · '
                          '${(p.bytes / 1e6).toStringAsFixed(1)} MB · '
                          '${NumberFormat.compact().format(p.wayCount)} roads',
                          style: context.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                    onPressed: _busy
                        ? null
                        : () => _run(() => _manager.removeRegion(p.region)),
                  ),
                ],
              ),
            ),
          ],
          if (_index != null) ...[
            const SizedBox(height: Space.section),
            Kicker('Available (built ${_date(_index!.builtAt)})'),
            const SizedBox(height: Space.xs),
            for (final e in _index!.packs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.name, style: context.body),
                subtitle: Text(
                  '${e.region} · ${(e.bytes / 1e6).toStringAsFixed(1)} MB',
                  style: context.caption,
                ),
                trailing: installedRegions.contains(e.region)
                    ? Icon(Icons.check, color: scheme.primary)
                    : TextButton(
                        onPressed: _busy ? null : () => _install(e),
                        child: const Text('Install'),
                      ),
              ),
          ],
        ],
      ),
    );
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat.yMMMd().format(d.toLocal());
  }
}

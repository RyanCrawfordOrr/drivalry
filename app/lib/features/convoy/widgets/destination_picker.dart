import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/google/places_client.dart';
import '../../../data/google/routes_client.dart' show LatLon;
import '../../../data/repos/convoy_models.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/friendly_error.dart';
import 'convoy_ui.dart';

/// Search for a destination (Places text search, capped per device) with
/// "where I am now" as the no-API fallback. Returns null when dismissed.
Future<Destination?> showDestinationPicker(
  BuildContext context, {
  String title = 'Destination',
}) {
  return showConvoySheet<Destination>(
    context,
    title: title,
    builder: (_) => const _DestinationSheet(),
  );
}

class _DestinationSheet extends ConsumerStatefulWidget {
  const _DestinationSheet();

  @override
  ConsumerState<_DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends ConsumerState<_DestinationSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion>? _results;
  bool _searching = false;
  bool _unavailable = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _unavailable = false;
    });
    LatLon? near;
    try {
      final loc = await ref.read(trackingPortProvider).getLastKnownLocation();
      if (loc != null) near = LatLon(loc.lat, loc.lon);
    } catch (_) {}
    final found = await ref
        .read(placesClientProvider)
        .searchText(q, near: near);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = found;
      _unavailable = found == null;
    });
  }

  Future<void> _useHere() async {
    try {
      final loc = await ref.read(trackingPortProvider).getLastKnownLocation();
      if (!mounted) return;
      if (loc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No position yet. Try again in a moment.'),
          ),
        );
        return;
      }
      Navigator.of(context).pop(
        Destination(
          name: _controller.text.trim().isEmpty
              ? 'Where I am'
              : _controller.text.trim(),
          lat: loc.lat,
          lon: loc.lon,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, doing: 'find where you are')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('destination-search'),
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Search a place or town',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(Space.md),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (_unavailable)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text(
                'Search is resting until tomorrow. You can still use where '
                'you are.',
                style: context.bodyMuted,
              ),
            ),
          if (results != null && results.isEmpty && !_unavailable)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text(
                'Nothing found. Try another spelling.',
                style: context.bodyMuted,
              ),
            ),
          if (results != null && results.isNotEmpty)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final p = results[i];
                  return ConvoyRow(
                    leading: const Icon(Icons.place_outlined, size: 28),
                    title: p.name,
                    titleStyle: context.body,
                    caption: p.address,
                    onTap: () => Navigator.of(context).pop(
                      Destination(
                        name: p.name,
                        lat: p.location.lat,
                        lon: p.location.lon,
                        placeId: p.placeId,
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: Space.sm),
          ConvoyRow(
            leading: const Icon(Icons.my_location, size: 28),
            title: 'Use where I am now',
            titleStyle: context.body,
            caption: 'No search needed',
            onTap: _useHere,
          ),
        ],
      ),
    );
  }
}

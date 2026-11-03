import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repos/places_repo.dart';

/// Add a saved place at [lat], [lon], or edit [existing]. Places never leave
/// the phone.
Future<void> showSavePlaceSheet(
  BuildContext context, {
  required double lat,
  required double lon,
  Place? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SavePlaceSheet(lat: lat, lon: lon, existing: existing),
  );
}

class _SavePlaceSheet extends ConsumerStatefulWidget {
  const _SavePlaceSheet({
    required this.lat,
    required this.lon,
    required this.existing,
  });

  final double lat;
  final double lon;
  final Place? existing;

  @override
  ConsumerState<_SavePlaceSheet> createState() => _SavePlaceSheetState();
}

class _SavePlaceSheetState extends ConsumerState<_SavePlaceSheet> {
  late final TextEditingController _label;
  late PlaceKind _kind;
  late double _radius;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e == null ? PlaceKind.home : PlaceKind.fromWire(e.kind);
    _label = TextEditingController(text: e?.label ?? _kind.label);
    _radius = e?.radiusM ?? 150;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Give the place a name.');
      return;
    }
    final repo = ref.read(placesRepoProvider);
    final e = widget.existing;
    if (e == null) {
      await repo.addPlace(
        label: label,
        kind: _kind,
        lat: widget.lat,
        lon: widget.lon,
        radiusM: _radius,
      );
    } else {
      await repo.updatePlace(e.id, label: label, kind: _kind, radiusM: _radius);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Save a place' : 'Edit place',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Stays on this phone. Friends\' arrivals and departures are '
              'worked out here from their live position.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<PlaceKind>(
              segments: [
                for (final k in PlaceKind.values)
                  ButtonSegment(
                    value: k,
                    icon: Icon(k.icon),
                    label: Text(k.label),
                  ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                final previousDefault = _kind.label;
                _kind = s.first;
                if (_label.text.trim() == previousDefault ||
                    _label.text.trim().isEmpty) {
                  _label.text = _kind.label;
                }
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            Row(
              children: [
                const Icon(Icons.radio_button_unchecked, size: 18),
                Expanded(
                  child: Slider(
                    value: _radius,
                    min: PlacesRepo.minRadiusM,
                    max: PlacesRepo.maxRadiusM,
                    divisions: 18,
                    label: '${_radius.round()} m',
                    onChanged: (v) => setState(() => _radius = v),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text('${_radius.round()} m', textAlign: TextAlign.end),
                ),
              ],
            ),
            Text(
              '${widget.lat.toStringAsFixed(4)}, ${widget.lon.toStringAsFixed(4)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.existing == null ? 'Save place' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

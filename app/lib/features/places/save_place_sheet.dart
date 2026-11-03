import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/repos/places_repo.dart';
import '../../tracking/providers.dart';
import '../../widgets/units.dart';
import '../friends/widgets/page_insets.dart';
import 'radius_text.dart';

/// Add a saved place at [lat], [lon], or edit [existing]. Places never leave
/// the phone.
Future<void> showSavePlaceSheet(
  BuildContext context, {
  required double lat,
  required double lon,
  Place? existing,
}) {
  return showDrivalrySheet<void>(
    context,
    title: existing == null ? 'Save a place' : 'Edit place',
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
    if (!mounted) return;
    Haptics.success();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    return Padding(
      padding: sheetBottomInset(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Stays on this phone. Alerts are worked out here from your '
            'friends\' live position.',
            style: context.caption,
          ),
          const SizedBox(height: Space.lg),
          // Words only: with icons the four labels break mid-word at 360.
          SegmentedButton<PlaceKind>(
            segments: [
              for (final k in PlaceKind.values)
                ButtonSegment(value: k, label: Text(k.label)),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              Haptics.select();
              final previousDefault = _kind.label;
              _kind = s.first;
              if (_label.text.trim() == previousDefault ||
                  _label.text.trim().isEmpty) {
                _label.text = _kind.label;
              }
            }),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _label,
            maxLength: 30,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              const Kicker('Radius'),
              Expanded(
                child: Slider(
                  value: _radius,
                  min: PlacesRepo.minRadiusM,
                  max: PlacesRepo.maxRadiusM,
                  divisions: 18,
                  label: radiusText(_radius, units),
                  onChanged: (v) => setState(() => _radius = v),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  radiusText(_radius, units),
                  textAlign: TextAlign.end,
                  style: context.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          PressScale(
            child: PrimaryButton(
              label: widget.existing == null ? 'Save place' : 'Save',
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/garage/fuel_math.dart';
import '../../data/garage/vehicle_matcher.dart';
import '../../data/repos/garage_repo.dart';
import '../../tracking/providers.dart';
import '../../widgets/units.dart';

/// Add or edit a vehicle. [vehicleId] null means new.
class VehicleEditScreen extends ConsumerStatefulWidget {
  const VehicleEditScreen({super.key, this.vehicleId});

  final String? vehicleId;

  @override
  ConsumerState<VehicleEditScreen> createState() => _VehicleEditScreenState();
}

class _VehicleEditScreenState extends ConsumerState<VehicleEditScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _tank = TextEditingController();
  final _newBt = TextEditingController();
  final List<String> _btNames = [];
  bool _neverTrack = false;
  bool _loaded = false;
  Vehicle? _existing;

  @override
  void dispose() {
    for (final c in [_name, _make, _model, _year, _tank, _newBt]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(Vehicle v, bool gallons) {
    if (_loaded) return;
    _loaded = true;
    _existing = v;
    _name.text = v.name;
    _make.text = v.make ?? '';
    _model.text = v.model ?? '';
    _year.text = v.year?.toString() ?? '';
    if (v.tankLitres != null) {
      _tank.text = (gallons ? litresToUsGallons(v.tankLitres!) : v.tankLitres!)
          .toStringAsFixed(1);
    }
    _btNames.addAll(v.bluetoothNameList);
    _neverTrack = v.neverTrack;
  }

  @override
  Widget build(BuildContext context) {
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final gallons = unitLabel(units) == 'mph';
    final id = widget.vehicleId;
    if (id != null) {
      final v = ref.watch(vehicleProvider(id)).value;
      if (v != null) _load(v, gallons);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(id == null ? 'Add vehicle' : 'Edit vehicle'),
        actions: [
          if (id != null)
            IconButton(
              tooltip: 'Archive',
              icon: const Icon(Icons.archive_outlined),
              onPressed: () => _archive(context),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.gutter,
            Space.lg,
            Space.gutter,
            Space.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Give it a name.' : null,
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _make,
                    decoration: const InputDecoration(labelText: 'Make'),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: 'Model'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Year'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      final y = int.tryParse(v);
                      return (y == null || y < 1900 || y > 2100)
                          ? 'Enter a four-digit year.'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TextFormField(
                    controller: _tank,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tank (${gallons ? 'gal' : 'L'})',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            const Kicker('Car audio'),
            const SizedBox(height: Space.xs),
            Text(
              'The Bluetooth or CarPlay name the phone sees in this car. '
              'Trips in it are credited to this vehicle.',
              style: context.caption,
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final n in _btNames)
                  InputChip(
                    label: Text(n),
                    onDeleted: () => setState(() => _btNames.remove(n)),
                  ),
              ],
            ),
            if (_btNames.isNotEmpty) const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newBt,
                    decoration: const InputDecoration(
                      hintText: 'e.g. "Mazda CX-5"',
                    ),
                    onSubmitted: (_) => _addBt(),
                  ),
                ),
                IconButton(
                  tooltip: 'Add name',
                  onPressed: _addBt,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            SwitchListTile(
              key: const Key('never-track'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Never track this vehicle'),
              subtitle: const Text(
                'Rental, work truck: drives in it are deleted the moment the '
                'phone connects to it.',
              ),
              value: _neverTrack,
              onChanged: (v) => setState(() => _neverTrack = v),
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Save',
              onPressed: () => _save(context, gallons),
            ),
          ],
        ),
      ),
    );
  }

  void _addBt() {
    final n = _newBt.text.trim();
    if (n.isEmpty) return;
    if (!_btNames
        .map(VehicleMatcher.normalize)
        .contains(VehicleMatcher.normalize(n))) {
      setState(() => _btNames.add(n));
    }
    _newBt.clear();
  }

  Future<void> _save(BuildContext context, bool gallons) async {
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(garageRepoProvider);
    final tankRaw = double.tryParse(_tank.text.replaceAll(',', '.'));
    final tankLitres = tankRaw == null
        ? null
        : (gallons ? usGallonsToLitres(tankRaw) : tankRaw);
    final year = int.tryParse(_year.text);
    final existing = _existing;
    if (existing == null) {
      final v = await repo.createVehicle(
        name: _name.text,
        make: _make.text,
        model: _model.text,
        year: year,
        tankLitres: tankLitres,
        bluetoothNames: _btNames,
        neverTrack: _neverTrack,
      );
      if (context.mounted) context.go(Routes.vehicle(v.id));
    } else {
      await repo.updateVehicle(
        existing.copyWith(
          name: _name.text.trim(),
          make: Value(_make.text.trim().isEmpty ? null : _make.text.trim()),
          model: Value(_model.text.trim().isEmpty ? null : _model.text.trim()),
          year: Value(year),
          tankLitres: Value(tankLitres),
          bluetoothNames: VehicleMatcher.encodeNames(_btNames),
          neverTrack: _neverTrack,
        ),
      );
      if (context.mounted) context.pop();
    }
  }

  Future<void> _archive(BuildContext context) async {
    final id = widget.vehicleId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this vehicle?'),
        content: const Text(
          'It disappears from the Garage. Its trips, fuel log and documents '
          'stay on the phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(garageRepoProvider).archiveVehicle(id);
    if (context.mounted) context.go(Routes.garage);
  }
}

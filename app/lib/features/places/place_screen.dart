import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/places_repo.dart';
import '../../data/repos/presence_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../tracking/providers.dart';
import '../../widgets/units.dart';
import '../friends/widgets/user_avatar.dart';
import 'radius_text.dart';
import 'save_place_sheet.dart';

/// One saved place: edit, delete, and who to be told about.
class PlaceScreen extends ConsumerWidget {
  const PlaceScreen({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider(placeId)).value;
    final alerts = ref.watch(placeAlertsForProvider(placeId)).value ?? const [];
    final people = _people(ref);
    final repo = ref.read(placesRepoProvider);
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final scheme = Theme.of(context).colorScheme;

    if (place == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          kicker: 'Place',
          headline: 'This place was deleted.',
          body: 'Nothing left to show here.',
        ),
      );
    }
    final kind = PlaceKind.fromWire(place.kind);
    final byMember = {for (final a in alerts) a.memberUserId: a};

    return Scaffold(
      appBar: AppBar(
        title: Text(place.label),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () => showSavePlaceSheet(
              context,
              lat: place.lat,
              lon: place.lon,
              existing: place,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _delete(context, repo, place),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xxxl),
        children: [
          Padding(
            padding: Space.screen,
            child: Reveal(
              child: Tile(
                child: Row(
                  children: [
                    Icon(kind.icon, size: 28, color: scheme.primary),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(kind.label, style: context.title),
                          const SizedBox(height: Space.xs),
                          Text(
                            'Within ${radiusText(place.radiusM, units)} of '
                            'here',
                            style: context.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.section),
          EditorialSection(
            kicker: 'Alerts',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick who to hear about when they arrive or leave.',
                  style: context.caption,
                ),
                const SizedBox(height: Space.md),
                if (people.isEmpty)
                  Text(
                    'Add a friend who shares their location and they show '
                    'up here.',
                    style: context.bodyMuted,
                  ),
                for (var i = 0; i < people.length; i++)
                  Reveal(
                    delay: Reveal.stagger(i),
                    child: _PersonAlertRow(
                      person: people[i],
                      alert: byMember[people[i].id],
                      onChanged: (arrive, leave) => repo.setAlert(
                        place.id,
                        people[i].id,
                        onArrive: arrive,
                        onLeave: leave,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: Space.screen,
            child: Text(
              'Worked out on this phone from their live position. Nothing '
              'about this place is uploaded. Quiet hours apply.',
              style: context.caption,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    PlacesRepo repo,
    Place place,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${place.label}?'),
        content: const Text('You stop getting alerts for it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await repo.deletePlace(place.id);
      if (context.mounted) context.pop();
    }
  }

  /// Friends plus anyone visible through a circle, minus me.
  List<_Person> _people(WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final seen = <String, _Person>{};
    final friends =
        ref.watch(friendsSnapshotProvider).value?.friends ?? const [];
    for (final f in friends) {
      seen[f.id] = _Person(f.id, f.name, f.avatarPath);
    }
    final presence = ref.watch(visiblePresenceProvider).value ?? const [];
    for (final p in presence) {
      seen.putIfAbsent(p.userId, () => _Person(p.userId, p.name, p.avatarPath));
    }
    final circles = ref.watch(myCirclesProvider).value ?? const [];
    for (final c in circles) {
      for (final m
          in ref.watch(circleMembersProvider(c.id)).value ?? const []) {
        seen.putIfAbsent(
          m.userId,
          () => _Person(m.userId, m.name, m.avatarPath),
        );
      }
    }
    seen.remove(me);
    final list = seen.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}

class _Person {
  const _Person(this.id, this.name, this.avatarPath);
  final String id;
  final String name;
  final String? avatarPath;
}

class _PersonAlertRow extends StatelessWidget {
  const _PersonAlertRow({
    required this.person,
    required this.alert,
    required this.onChanged,
  });

  final _Person person;
  final PlaceAlert? alert;
  final void Function(bool arrive, bool leave) onChanged;

  @override
  Widget build(BuildContext context) {
    final arrive = alert?.onArrive ?? false;
    final leave = alert?.onLeave ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        children: [
          UserAvatar(name: person.name, avatarPath: person.avatarPath),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  style: context.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  children: [
                    FilterChip(
                      label: const Text('Arrives'),
                      selected: arrive,
                      onSelected: (v) {
                        Haptics.select();
                        onChanged(v, leave);
                      },
                    ),
                    FilterChip(
                      label: const Text('Leaves'),
                      selected: leave,
                      onSelected: (v) {
                        Haptics.select();
                        onChanged(arrive, v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

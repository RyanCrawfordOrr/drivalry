import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/places_repo.dart';
import '../../data/repos/presence_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../friends/widgets/user_avatar.dart';
import 'save_place_sheet.dart';

/// One saved place: edit, delete, and who to be told about.
class PlaceScreen extends ConsumerWidget {
  const PlaceScreen({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final place = ref.watch(placeProvider(placeId)).value;
    final alerts = ref.watch(placeAlertsForProvider(placeId)).value ?? const [];
    final people = _people(ref);
    final repo = ref.read(placesRepoProvider);

    if (place == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Place')),
        body: const Center(child: Text('This place was removed.')),
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
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete ${place.label}?'),
                  content: const Text('Its alerts go with it.'),
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
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          ListTile(
            leading: Icon(kind.icon),
            title: Text(kind.label),
            subtitle: Text(
              '${place.radiusM.round()} m radius · '
              '${place.lat.toStringAsFixed(3)}, ${place.lon.toStringAsFixed(3)}',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Tell me when…',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (people.isEmpty)
            const ListTile(
              title: Text('No friends sharing yet'),
              subtitle: Text(
                'Alerts need a friend or circle member who shares their '
                'location.',
              ),
            ),
          for (final person in people)
            _PersonRow(
              person: person,
              alert: byMember[person.id],
              onChanged: (arrive, leave) => repo.setAlert(
                place.id,
                person.id,
                onArrive: arrive,
                onLeave: leave,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Worked out on this phone from their live position; nothing about '
              'this place is uploaded. Honours quiet hours.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
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

class _PersonRow extends StatelessWidget {
  const _PersonRow({
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
    return ListTile(
      leading: UserAvatar(name: person.name, avatarPath: person.avatarPath),
      title: Text(person.name),
      subtitle: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('arrives'),
            selected: arrive,
            onSelected: (v) => onChanged(v, leave),
          ),
          FilterChip(
            label: const Text('leaves'),
            selected: leave,
            onSelected: (v) => onChanged(arrive, v),
          ),
        ],
      ),
    );
  }
}

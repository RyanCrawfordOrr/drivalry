import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repos/convoy_models.dart';
import '../../../data/repos/convoy_sync.dart';

/// Display names by user id for one convoy, from the cached member list the
/// detail screen keeps fresh. Live while watched; empty until cached.
final convoyMemberNamesProvider = StreamProvider.autoDispose
    .family<Map<String, String>, String>((ref, id) {
      final repo = ref.watch(convoyRepoProvider);
      return repo
          .watchMembers(id)
          .map(
            (list) => {
              for (final m in list ?? const <ConvoyMember>[]) m.userId: m.name,
            },
          );
    });

/// A label for a car: [self] for the signed-in user, the member's name, or
/// "Someone" when nothing is cached. Never a UUID prefix (docs/01 §4.6).
String memberLabel(
  Map<String, String> names,
  String id, {
  String? selfId,
  String self = 'You',
}) => id == selfId ? self : names[id] ?? 'Someone';

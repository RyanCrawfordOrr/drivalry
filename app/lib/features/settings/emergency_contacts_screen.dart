import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/ui/ui.dart';
import '../../data/crash/crash_sms.dart';
import '../../data/db/database.dart';
import '../../data/repos/friends_repo.dart' show FriendProfile;
import '../../data/repos/friends_sync.dart';
import '../../widgets/friendly_error.dart';
import 'widgets/settings_rows.dart';

/// Settings › Emergency contacts: who gets the prefilled text when a crash
/// countdown runs out. Stored on this phone only. A contact who is also a
/// Drivalry friend can be linked so they get the push as well.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(emergencyContactsProvider);
    final rows = contacts.value ?? const <EmergencyContact>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: rows.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('contact-add'),
              onPressed: () => showAddContactSheet(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add contact'),
            ),
      body: contacts.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xxxl,
          ),
          children: const [
            SkeletonTile(height: 72),
            SizedBox(height: Space.sm),
            SkeletonTile(height: 72),
          ],
        ),
        error: (e, _) => EmptyState(
          kicker: 'Emergency contacts',
          headline: 'Could not load your contacts.',
          body: friendlyError(e, doing: 'load your contacts'),
        ),
        data: (rows) => rows.isEmpty
            ? ListView(
                children: [
                  EmptyState(
                    kicker: 'Emergency contacts',
                    headline: 'Who should get the text?',
                    body:
                        'If a crash check goes unanswered, they get a text '
                        'with your location.',
                    actionLabel: 'Add contact',
                    onAction: () => showAddContactSheet(context, ref),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Space.xxxl + Space.xxl,
                ),
                children: [
                  SettingsGroup(
                    children: [
                      for (final c in rows)
                        SettingsRow(
                          leading: Avatar(name: c.name, size: AvatarSize.md),
                          title: c.name,
                          caption: c.userId == null
                              ? c.phone
                              : '${c.phone} · also gets an alert in the app',
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(context, ref, c),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    'Numbers stay on this phone. The text is readied in your '
                    'messaging app; someone still presses send.',
                    style: context.caption,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    EmergencyContact c,
  ) async {
    final db = ref.read(databaseProvider);
    await db.deleteEmergencyContact(c.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${c.name} removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => db.upsertEmergencyContact(
            EmergencyContactsCompanion.insert(
              id: c.id,
              name: c.name,
              phone: c.phone,
              userId: Value(c.userId),
              createdAt: c.createdAt,
            ),
          ),
        ),
      ),
    );
  }
}

/// Name + phone, with an optional friend to link for the push.
Future<void> showAddContactSheet(BuildContext context, WidgetRef ref) {
  final name = TextEditingController();
  final phone = TextEditingController();
  String? linkedUserId;
  final formKey = GlobalKey<FormState>();
  return showDrivalrySheet<void>(
    context,
    title: 'Add emergency contact',
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: StatefulBuilder(
        builder: (sheet, setState) {
          final friends =
              ref.watch(friendsSnapshotProvider).value?.friends ??
              const <FriendProfile>[];
          return Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('contact-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Add a name.' : null,
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  key: const Key('contact-phone'),
                  controller: phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+1 555 123 4567',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => normalisePhone(v ?? '').length < 5
                      ? 'Enter a phone number.'
                      : null,
                ),
                if (friends.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  DropdownButtonFormField<String?>(
                    key: const Key('contact-friend'),
                    initialValue: linkedUserId,
                    decoration: const InputDecoration(
                      labelText: 'Also a friend on Drivalry?',
                      helperText:
                          'They get an alert in the app as well as the text.',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No'),
                      ),
                      for (final f in friends)
                        DropdownMenuItem<String?>(
                          value: f.id,
                          child: Text('${f.displayName} (@${f.handle})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => linkedUserId = v),
                  ),
                ],
                const SizedBox(height: Space.xl),
                PrimaryButton(
                  key: const Key('contact-save'),
                  label: 'Save',
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    await ref
                        .read(databaseProvider)
                        .upsertEmergencyContact(
                          EmergencyContactsCompanion.insert(
                            id: const Uuid().v4(),
                            name: name.text.trim(),
                            phone: normalisePhone(phone.text),
                            userId: Value(linkedUserId),
                            createdAt: DateTime.now().millisecondsSinceEpoch,
                          ),
                        );
                    Haptics.success();
                    if (sheet.mounted) Navigator.of(sheet).pop();
                  },
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

final emergencyContactsProvider = StreamProvider<List<EmergencyContact>>(
  (ref) => ref.watch(databaseProvider).watchEmergencyContacts(),
);

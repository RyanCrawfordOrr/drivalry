import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/crash/crash_sms.dart';
import '../../data/db/database.dart';
import '../../data/repos/friends_repo.dart' show FriendProfile;
import '../../data/repos/friends_sync.dart';

/// Settings › Emergency contacts: who gets the prefilled text when a crash
/// countdown runs out. Stored on this phone only. A contact who is also a
/// Drivalry friend can be linked so they get the push as well.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(emergencyContactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      body: contacts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => rows.isEmpty
            ? const _Empty()
            : ListView(
                children: [
                  for (final c in rows)
                    ListTile(
                      leading: Icon(
                        c.userId == null
                            ? Icons.person_outline
                            : Icons.verified_user_outlined,
                      ),
                      title: Text(c.name),
                      subtitle: Text(
                        c.userId == null
                            ? c.phone
                            : '${c.phone}  ·  also gets the push',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(databaseProvider)
                            .deleteEmergencyContact(c.id),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Numbers stay on this phone. The text is prepared in '
                      'your messaging app; you (or whoever has your phone) '
                      'still press send.',
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('contact-add'),
        onPressed: () => showAddContactSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add contact'),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.contact_phone_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No emergency contacts',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Add the people who should get a text with your location if a '
            'crash check goes unanswered.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

/// Name + phone, with an optional friend to link for the push.
Future<void> showAddContactSheet(BuildContext context, WidgetRef ref) {
  final name = TextEditingController();
  final phone = TextEditingController();
  String? linkedUserId;
  final formKey = GlobalKey<FormState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(sheet).bottom,
      ),
      child: StatefulBuilder(
        builder: (sheet, setState) {
          final friends =
              ref.watch(friendsSnapshotProvider).value?.friends ??
              const <FriendProfile>[];
          return Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add emergency contact',
                  style: Theme.of(sheet).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('contact-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                TextFormField(
                  key: const Key('contact-phone'),
                  controller: phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+1 555 123 4567',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => normalisePhone(v ?? '').length < 5
                      ? 'Enter a phone number'
                      : null,
                ),
                if (friends.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    key: const Key('contact-friend'),
                    initialValue: linkedUserId,
                    decoration: const InputDecoration(
                      labelText: 'Also a Drivalry friend? (optional)',
                      helperText:
                          'Only accepted friends can be linked. They get the '
                          'push alert as well as the text.',
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
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('contact-save'),
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
                    if (sheet.mounted) Navigator.of(sheet).pop();
                  },
                  child: const Text('Save'),
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

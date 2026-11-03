import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import 'friends_map.dart';

/// The friends map, full screen (ADR-018).
class FriendsMapScreen extends StatelessWidget {
  const FriendsMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends map'),
        actions: [
          IconButton(
            tooltip: 'Add friend',
            onPressed: () => context.push(Routes.addFriend),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: const FriendsMap(fullScreen: true),
    );
  }
}

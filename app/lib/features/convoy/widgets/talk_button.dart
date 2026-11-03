import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/ui/ui.dart';

/// The route to the radio with the "start on open" flag the radio screen
/// reads (`convoy_routes.dart`).
String radioRouteStarting(String convoyId) =>
    '${Routes.convoyRadio(convoyId)}?start=1';

/// Opens the radio and starts it: the one in-car action (docs/12 §7).
void openRadio(BuildContext context, String convoyId) {
  Haptics.select();
  context.push(radioRouteStarting(convoyId));
}

/// The 64-tall, full-width "Talk" button on the hub and the convoy map.
class TalkButton extends StatelessWidget {
  const TalkButton({super.key, required this.convoyId});
  final String convoyId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Sizes.drivingTouch,
      child: PrimaryButton(
        label: 'Talk',
        icon: Icons.mic,
        onPressed: () => openRadio(context, convoyId),
      ),
    );
  }
}

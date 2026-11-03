import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/deep_links.dart';
import '../../app/router.dart';
import '../../app/ui/ui.dart';
import '../../data/alerts/auto_checkin.dart';
import '../../data/alerts/place_alerts.dart';
import '../../data/crash/crash_monitor.dart';
import '../../data/db/database.dart';
import '../../data/garage/vehicle_matcher.dart';
import '../../data/models/trip_score_view.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/presence_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';
import '../../widgets/units.dart';
import '../crash/crash_status_card.dart';
import '../cues/live_limit.dart';
import '../garage/widgets/new_vehicle_prompt_card.dart';
import '../profile/profile_repo.dart';
import 'drive_sheet.dart';
import 'first_run_flow.dart';
import 'friends_map/friends_map.dart';
import 'parking/parking_card.dart';
import 'parking/parking_memory.dart';
import 'share_card.dart';
import 'simulate_sheet.dart';
import 'trip_celebration.dart';
import 'widgets/drive_status_capsule.dart';
import 'widgets/live_drive_block.dart';
import 'widgets/passenger_card.dart';
import 'widgets/sheet_action.dart';
import 'widgets/trip_card.dart';

/// `Settings` key: the three-page first run was finished or skipped here.
const firstRunDoneKey = 'first_run_done';

final firstRunDoneProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(firstRunDoneKey)
      .map((v) => v == '1'),
);

/// Whether the developer shortcuts (Simulate, Diagnostics) float on the
/// Drive tab. Debug builds only; the store-art renderer turns them off.
final devToolsVisibleProvider = Provider<bool>((_) => kDebugMode);

/// Home tab (docs/12 §7 "Drive"): the friends map full-bleed under a
/// transparent status bar, a status capsule and two round buttons floating at
/// the top, and a draggable sheet with the live drive, the prompts, the last
/// trip and the recents. First launch shows the three-page [FirstRunFlow]
/// instead until permissions are set or the person says "Not now".
class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Long-lived services that live as long as the home tab does.
    ref.watch(presencePublisherProvider);
    ref.watch(friendsSyncProvider);
    ref.watch(deepLinksProvider);
    ref.watch(vehicleMatcherProvider);
    ref.watch(parkingMemoryProvider);
    ref.watch(placeAlertsProvider);
    ref.watch(autoCheckinProvider);

    final tracking = ref.watch(trackingControllerProvider);
    final controller = ref.read(trackingControllerProvider.notifier);
    final tripsAsync = ref.watch(recentTripsProvider);
    final firstRunDone = ref.watch(firstRunDoneProvider);
    final plugin = tracking.plugin;
    final needsSetup =
        plugin.pluginAvailable && !plugin.permissions.sufficientForAutoTracking;

    // Nothing flashes: wait for the plugin, the trips and the setting.
    if (!tracking.booted || !tripsAsync.hasValue || !firstRunDone.hasValue) {
      return const Scaffold(body: SizedBox.expand());
    }
    final trips = tripsAsync.value ?? const <TripWithScore>[];
    if (needsSetup && trips.isEmpty && firstRunDone.value != true) {
      return FirstRunFlow(
        permissions: plugin.permissions,
        onRequest: controller.requestPermissions,
        onOpenSettings: controller.openSettings,
        onDone: () =>
            ref.read(databaseProvider).setSetting(firstRunDoneKey, '1'),
      );
    }
    return TripCelebrationHost(
      child: _DriveHome(tracking: tracking, trips: trips),
    );
  }
}

class _DriveHome extends ConsumerWidget {
  const _DriveHome({required this.tracking, required this.trips});

  final TrackingUiState tracking;
  final List<TripWithScore> trips;

  /// Height of the recording capsule, for placing the map's own chrome.
  static const _recordingCapsuleHeight = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(trackingControllerProvider.notifier);
    final unanswered =
        ref.watch(unansweredTripsProvider).value ?? const <Trip>[];
    final unitsSetting =
        ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
    final parkingSpot = ref.watch(latestParkingSpotProvider).value;
    final vehiclePrompt = ref.watch(vehiclePromptProvider).value;
    final liveLimit = ref.watch(liveLimitProvider).value;
    final crash = ref.watch(crashMonitorProvider);
    final flagged = ref.watch(crashFlaggedTripsProvider).value ?? const [];
    final devTools = ref.watch(devToolsVisibleProvider);

    final plugin = tracking.plugin;
    final live = tracking.live;
    final recording = live != null;
    final idle = plugin.phase == TrackingPhase.idle && !recording;
    final needsSetup =
        plugin.pluginAvailable && !plugin.permissions.sufficientForAutoTracking;
    final latestRegion = trips.isEmpty ? null : trips.first.trip.packRegion;
    final units = resolveUnits(unitsSetting, packRegion: latestRegion);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Mirrors CrashStatusCard's own rule so the sheet only leaves room for
    // the card when it has something to say.
    final showCrash =
        crash.unresolved != null ||
        (crash.candidate != null && !crash.testMode) ||
        flagged.any((t) => t.id != crash.candidate?.tripId);
    final last = trips.isEmpty ? null : trips.first;
    final rest = trips.length > 1 ? trips.sublist(1) : const <TripWithScore>[];
    final overlayTop =
        MediaQuery.paddingOf(context).top +
        Space.md +
        (recording ? _recordingCapsuleHeight : Sizes.touch) +
        Space.md;

    // Sheet contents in order (docs/12 §7). Each gets a stable key so a new
    // item reveals on arrival and the rest stay put.
    final items = <(String, Widget)>[
      if (recording)
        (
          'live',
          LiveDriveBlock(
            live: live,
            units: units,
            liveLimit: liveLimit,
            onEnd: controller.endNow,
          ),
        ),
      if (tracking.error != null)
        (
          'error',
          Tile(
            tone: TileTone.danger,
            child: Text(
              tracking.error!,
              style: context.body.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ),
      if (showCrash) ('crash', const CrashStatusCard()),
      if (idle && parkingSpot != null)
        ('parking', ParkingCard(spot: parkingSpot)),
      if (vehiclePrompt != null)
        ('vehicle', NewVehiclePromptCard(prompt: vehiclePrompt)),
      for (final t in unanswered)
        (
          'passenger-${t.id}',
          PassengerCard(
            trip: t,
            units: resolveUnits(unitsSetting, packRegion: t.packRegion),
            onAnswer: (isPassenger) =>
                controller.answerPassenger(t.id, isPassenger),
          ),
        ),
      if (needsSetup && !recording)
        (
          'auto-detect',
          AutoDetectTile(onTap: () => _turnOnAutoDetect(context, controller)),
        ),
      if (last == null)
        ('empty', const _NoTripsYet())
      else ...[
        (
          'last',
          EditorialSection(
            kicker: 'Last trip',
            padding: EdgeInsets.zero,
            gap: Space.lg,
            child: TripCard(
              trip: last.trip,
              score: _view(last.score),
              units: resolveUnits(
                unitsSetting,
                packRegion: last.trip.packRegion,
              ),
              large: true,
              onTap: () => context.push(Routes.tripDetail(last.trip.id)),
              onLongPress: () => _tripActions(context, ref, last, units),
            ),
          ),
        ),
        if (rest.isNotEmpty)
          (
            'recent',
            EditorialSection(
              kicker: 'Recent',
              padding: EdgeInsets.zero,
              gap: 0,
              child: Column(
                children: [
                  for (final t in rest)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: TripCard(
                        trip: t.trip,
                        score: _view(t.score),
                        units: resolveUnits(
                          unitsSetting,
                          packRegion: t.trip.packRegion,
                        ),
                        onTap: () => context.push(Routes.tripDetail(t.trip.id)),
                        onLongPress: () => _tripActions(context, ref, t, units),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ];
    final children = <Widget>[
      for (final (i, (key, w)) in items.indexed)
        Reveal(
          key: ValueKey('sheet-$key'),
          delay: Reveal.stagger(i),
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: w,
          ),
        ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: FriendsMap(embedded: true, overlayTop: overlayTop),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.md,
                    Space.gutter,
                    0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: DriveStatusCapsule(
                            state: tracking,
                            units: units,
                            liveLimit: liveLimit,
                            onTap: plugin.pluginAvailable
                                ? () => _detectionSheet(
                                    context,
                                    controller,
                                    tracking,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      if (devTools) ...[
                        const _DevMenu(),
                        const SizedBox(width: Space.sm),
                      ],
                      const _RequestsButton(),
                      const SizedBox(width: Space.sm),
                      const _AvatarButton(),
                    ],
                  ),
                ),
              ),
            ),
            DriveSheet(recording: recording, children: children),
          ],
        ),
      ),
    );
  }

  static TripScoreView? _view(TripScoreRow? row) =>
      row == null ? null : TripScoreView.fromJsonString(row.scoreJson);

  /// Asks the OS again; when that is not enough, points at Settings.
  Future<void> _turnOnAutoDetect(
    BuildContext context,
    TrackingController controller,
  ) async {
    final perms = await controller.requestPermissions();
    if (perms.sufficientForAutoTracking || !context.mounted) return;
    await showDrivalrySheet<void>(
      context,
      title: 'Almost there',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Set location to all the time and allow motion in your phone's "
            'settings.',
            style: ctx.bodyMuted,
          ),
          const SizedBox(height: Space.xl),
          PrimaryButton(
            label: 'Open settings',
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.openSettings();
            },
          ),
        ],
      ),
    );
  }

  /// The capsule's sheet: pause, resume, start a drive by hand, turn off.
  Future<void> _detectionSheet(
    BuildContext context,
    TrackingController controller,
    TrackingUiState state,
  ) {
    final plugin = state.plugin;
    final now = DateTime.now().millisecondsSinceEpoch;
    final recording = state.live != null;
    return showDrivalrySheet<void>(
      context,
      title: 'Auto-detect',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recording)
            SheetAction(
              icon: Icons.stop_circle_outlined,
              label: 'End drive',
              onTap: controller.endNow,
            )
          else if (!plugin.enabled)
            SheetAction(
              icon: Icons.radar,
              label: 'Turn on auto-detect',
              onTap: () => controller.setEnabled(true),
            )
          else if (plugin.isPausedAt(now))
            SheetAction(
              icon: Icons.play_circle_outline,
              label: 'Resume now',
              onTap: controller.clearPause,
            )
          else ...[
            if (plugin.permissions.sufficientForManualTracking)
              SheetAction(
                icon: Icons.play_arrow,
                label: 'Start a drive now',
                onTap: controller.startNow,
              ),
            SheetAction(
              icon: Icons.snooze,
              label: 'Pause for 1 hour',
              onTap: () => controller.pauseFor(const Duration(hours: 1)),
            ),
            SheetAction(
              icon: Icons.snooze,
              label: 'Pause for 4 hours',
              onTap: () => controller.pauseFor(const Duration(hours: 4)),
            ),
            SheetAction(
              icon: Icons.bedtime_outlined,
              label: 'Pause until tomorrow',
              onTap: controller.pauseUntilTomorrow,
            ),
            SheetAction(
              icon: Icons.power_settings_new,
              label: 'Turn off auto-detect',
              onTap: () => controller.setEnabled(false),
            ),
          ],
        ],
      ),
    );
  }

  /// Long-press on a trip: share, passenger, delete (docs/12 §5b).
  Future<void> _tripActions(
    BuildContext context,
    WidgetRef ref,
    TripWithScore t,
    SpeedUnits units,
  ) {
    final controller = ref.read(trackingControllerProvider.notifier);
    final trip = t.trip;
    final score = _view(t.score);
    return showDrivalrySheet<void>(
      context,
      title: tripDateLabel(trip),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (score != null && score.scored)
            SheetAction(
              icon: Icons.ios_share,
              label: 'Share',
              onTap: () => shareTripFromApp(context, ref, trip, score, units),
            ),
          SheetAction(
            icon: Icons.airline_seat_recline_normal,
            label: trip.isPassenger == true
                ? 'I was the driver'
                : 'Mark as passenger',
            onTap: () =>
                controller.answerPassenger(trip.id, trip.isPassenger != true),
          ),
          SheetAction(
            icon: Icons.delete_outline,
            label: 'Delete trip',
            destructive: true,
            onTap: () async {
              if (await confirmDeleteTrip(context)) {
                await controller.deleteTrip(trip.id);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Empty sheet copy: no mention of the simulator (docs/12 audit item 3).
class _NoTripsYet extends StatelessWidget {
  const _NoTripsYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Go for a drive.', style: context.headline),
          const SizedBox(height: Space.md),
          Text("We'll score it when you park.", style: context.bodyMuted),
        ],
      ),
    );
  }
}

/// Round tonal surface floating over the map, with the soft map shadow.
class _RoundSurface extends StatelessWidget {
  const _RoundSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox.square(
          dimension: Sizes.touch,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressScale(
        onTap: onTap,
        child: _RoundSurface(child: child),
      ),
    );
  }
}

class _RequestsButton extends ConsumerWidget {
  const _RequestsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingRequestCountProvider);
    return _RoundButton(
      tooltip: 'Friend requests',
      onTap: () => context.push(Routes.friendRequests),
      child: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        child: const Icon(Icons.mark_email_unread_outlined),
      ),
    );
  }
}

/// Your avatar: opens Profile (where Settings now lives), or sign-in.
class _AvatarButton extends ConsumerWidget {
  const _AvatarButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) {
      return _RoundButton(
        tooltip: 'Sign in',
        onTap: () => context.push(Routes.signIn),
        child: const Icon(Icons.person_outline),
      );
    }
    final profile = ref.watch(myProfileProvider).value;
    final name = profile == null
        ? '?'
        : profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.handle.isNotEmpty
        ? profile.handle
        : '?';
    final url = profile == null
        ? null
        : ref.read(profileRepoProvider).avatarUrl(profile.avatarPath);
    return _RoundButton(
      tooltip: 'Profile',
      onTap: () => context.push(Routes.profile),
      child: Hero(
        tag: 'avatar-$uid',
        child: Avatar(
          name: name,
          isMe: true,
          image: url == null ? null : CachedNetworkImageProvider(url),
        ),
      ),
    );
  }
}

/// Debug builds only: Simulate and Diagnostics. Packs and Units live in
/// Settings.
class _DevMenu extends ConsumerWidget {
  const _DevMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Developer',
      onSelected: (v) async {
        switch (v) {
          case 'simulate':
            await showSimulateSheet(context, ref);
          case 'diagnostics':
            await context.push(Routes.diagnostics);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'simulate', child: Text('Simulate a drive')),
        PopupMenuItem(value: 'diagnostics', child: Text('Diagnostics')),
      ],
      child: const _RoundSurface(child: Icon(Icons.more_horiz)),
    );
  }
}

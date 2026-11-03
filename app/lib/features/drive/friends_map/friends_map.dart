import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/bootstrap.dart';
import '../../../app/routes.dart';
import '../../../app/ui/ui.dart';
import '../../../config/env.dart';
import '../../../data/db/database.dart' show ParkingSpot, Place;
import '../../../data/repos/circles_sync.dart';
import '../../../data/repos/places_repo.dart';
import '../../../data/repos/presence_repo.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../tracking/providers.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';
import '../../../widgets/units.dart';
import '../../places/save_place_sheet.dart';
import '../parking/parking_memory.dart';
import 'friend_marker.dart';
import 'marker_icons.dart';

/// Replaces the Google map surface when set. Tests and the store-art renderer
/// (`test/art/`) use it: platform views do not exist there, so they draw a
/// stand-in and keep the chips, buttons and notices that sit on top real.
final friendsMapSurfaceProvider = Provider<WidgetBuilder?>((_) => null);

/// Live map of friends and circle members (ADR-018). Full-bleed under the
/// Drive tab ([embedded]) and full screen at [Routes.friendsMap]. Subscribes
/// to presence only while mounted. When it cannot render it explains itself
/// in one calm line, never in build detail.
class FriendsMap extends ConsumerStatefulWidget {
  const FriendsMap({
    super.key,
    this.fullScreen = false,
    this.embedded = false,
    this.overlayTop = 0,
  });

  final bool fullScreen;

  /// Behind the Drive tab's floating chrome and sheet: the circle chips and
  /// notices sit at [overlayTop] instead of the top edge, and there is no
  /// expand button because the map already fills the screen.
  final bool embedded;
  final double overlayTop;

  @override
  ConsumerState<FriendsMap> createState() => _FriendsMapState();
}

class _FriendsMapState extends ConsumerState<FriendsMap> {
  /// Only when nothing at all is known about where the phone is.
  static const _usa = CameraPosition(target: LatLng(39.5, -98.35), zoom: 3);

  /// Where you are when nobody is sharing: a city, never a continent.
  static const _cityZoom = 12.0;

  /// The OS's cached fix is good enough for a map; nothing wakes the GPS.
  static const _lastFixMaxAge = Duration(days: 1);

  GoogleMapController? _map;
  bool _fitted = false;

  /// The empty map has been pointed at the phone's position.
  bool _homed = false;

  /// The OS's cached position, asked for once; null until answered.
  LatLng? _lastFix;
  bool _fixChecked = false;

  /// The phone's position as of this build, or null when unknown.
  LatLng? _here;

  /// Circle id to filter by, or null for everyone.
  String? _circleFilter;
  final _icons = MarkerIconCache();
  final Map<String, BitmapDescriptor> _ready = {};
  final Set<String> _requested = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadLastFix());
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _loadLastFix() async {
    try {
      final loc = await ref
          .read(trackingPortProvider)
          .getLastKnownLocation(maxAgeMs: _lastFixMaxAge.inMilliseconds);
      if (loc != null) _lastFix = LatLng(loc.lat, loc.lon);
    } catch (_) {
      // No permission or no plugin: the parking spot, or nothing.
    } finally {
      if (mounted) setState(() => _fixChecked = true);
    }
  }

  /// The phone's position as best the app knows it: the drive in progress,
  /// then the OS's cached fix, then where the car was parked.
  LatLng? _knownPosition(LiveTripStats? live, ParkingSpot? parking) {
    final lat = live?.lastLat;
    final lon = live?.lastLon;
    if (lat != null && lon != null) return LatLng(lat, lon);
    if (_lastFix != null) return _lastFix;
    if (parking != null) return LatLng(parking.lat, parking.lon);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = ref.watch(friendsMapSurfaceProvider);
    if (surface == null && !Env.hasSupabase) {
      return _MapNotice(
        kicker: 'Friends',
        text: 'Friends are not available in this version.',
        embedded: widget.embedded,
      );
    }
    if (!ref.watch(isSignedInProvider)) {
      return _MapNotice(
        kicker: 'Friends map',
        text: 'Sign in to see friends on the map.',
        embedded: widget.embedded,
        action: FilledButton.tonal(
          onPressed: () => context.push(Routes.signIn),
          child: const Text('Sign in'),
        ),
      );
    }
    final mapsReady = ref.watch(mapsReadyProvider);
    if (surface == null && mapsReady.value != true) {
      return _MapNotice(
        kicker: 'Map',
        text: mapsReady.isLoading
            ? 'Loading the map…'
            : 'Map not available in this version.',
        embedded: widget.embedded,
      );
    }

    final presence = ref.watch(visiblePresenceProvider);
    final me = ref.watch(currentUserIdProvider);
    final now = DateTime.now().toUtc();
    final allMarkers = markersFrom(
      presence.value ?? const <PresenceRow>[],
      excludeUserId: me,
    );
    final circles = ref.watch(myCirclesProvider).value ?? const [];
    final membership = ref.watch(circleMembershipProvider);
    final filter = _circleFilter;
    final markers = filter == null
        ? allMarkers
        : [
            for (final m in allMarkers)
              if (membership[filter]?.contains(m.id) ?? false) m,
          ];
    final places = ref.watch(placesProvider).value ?? const <Place>[];
    _ensureIcons(markers, theme, now);
    final perms = ref.watch(
      trackingControllerProvider.select((s) => s.plugin.permissions),
    );
    final parking = ref.watch(latestParkingSpotProvider).value;
    final live = ref.watch(trackingControllerProvider.select((s) => s.live));
    _here = _knownPosition(live, parking);
    if (!_fitted && markers.isNotEmpty && _map != null) {
      _fitted = true;
      unawaited(_fit(markers));
    } else if (!_homed && markers.isEmpty && _here != null && _map != null) {
      // Nobody sharing: look at where you are, not at the whole country.
      _homed = true;
      unawaited(_home(_here!));
    }

    final chips = circles.isEmpty
        ? null
        : _CircleChips(
            options: [for (final c in circles) (c.id, c.name)],
            selected: filter,
            onSelected: (id) => setState(() {
              _circleFilter = id;
              _fitted = false;
              _homed = false;
            }),
          );
    final noFriends = markers.isEmpty && !presence.isLoading
        ? const _NoFriendsNotice()
        : null;

    return Stack(
      children: [
        if (surface != null)
          Positioned.fill(child: surface(context))
        else if (!_fixChecked)
          // Hold the map until the phone's position is known or ruled out,
          // so it never opens on the continent and then jumps.
          Positioned.fill(
            child: ColoredBox(color: theme.colorScheme.surfaceContainerLow),
          )
        else
          GoogleMap(
            initialCameraPosition: _initialCamera(markers),
            markers: {
              for (final m in markers)
                Marker(
                  markerId: MarkerId(m.id),
                  position: m.position,
                  anchor: const Offset(0.5, 0.5),
                  icon:
                      _ready[m.iconKey(now)] ??
                      BitmapDescriptor.defaultMarkerWithHue(m.hue),
                  onTap: () => _showFriend(context, m),
                ),
              for (final p in places) _placeMarker(context, p),
            },
            circles: {for (final p in places) _placeRadius(theme, p)},
            onLongPress: (pos) => showSavePlaceSheet(
              context,
              lat: pos.latitude,
              lon: pos.longitude,
            ),
            myLocationEnabled: perms.location != LocationPermission.denied,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) {
              _map = c;
              if (markers.isNotEmpty && !_fitted) {
                _fitted = true;
                unawaited(_fit(markers));
              } else if (markers.isEmpty && _here != null) {
                _homed = true;
                unawaited(_home(_here!));
              }
            },
          ),
        if (widget.embedded)
          Positioned(
            top: widget.overlayTop,
            left: Space.gutter,
            right: Space.gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?chips,
                if (chips != null && noFriends != null)
                  const SizedBox(height: Space.sm),
                ?noFriends,
              ],
            ),
          )
        else ...[
          // Floating controls: 12 under the top edge, 20 from the sides
          // (docs/12 §2), with room for the buttons on the right.
          if (chips != null)
            Positioned(
              top: Space.md,
              left: Space.gutter,
              right: Space.gutter + Sizes.touch + Space.md,
              child: chips,
            ),
          Positioned(
            top: Space.md,
            right: Space.gutter,
            child: Column(
              children: [
                if (!widget.fullScreen) ...[
                  IconButton.filledTonal(
                    tooltip: 'Expand map',
                    onPressed: () => context.push(Routes.friendsMap),
                    icon: const Icon(Icons.open_in_full),
                  ),
                  const SizedBox(height: Space.sm),
                ],
                IconButton.filledTonal(
                  tooltip: 'Show everyone',
                  onPressed: markers.isEmpty ? null : () => _fit(markers),
                  icon: const Icon(Icons.fit_screen_outlined),
                ),
              ],
            ),
          ),
          if (noFriends != null)
            Positioned(
              left: Space.gutter,
              right: Space.gutter,
              bottom: Space.xl + MediaQuery.paddingOf(context).bottom,
              child: noFriends,
            ),
        ],
        if (presence.isLoading && markers.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: widget.embedded ? widget.overlayTop : 0,
            child: const LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  CameraPosition _initialCamera(List<FriendMarker> markers) {
    if (markers.isEmpty) {
      final here = _here;
      if (here == null) return _usa;
      return CameraPosition(target: here, zoom: _cityZoom);
    }
    final b = boundsOf(markers)!;
    return CameraPosition(
      target: LatLng(
        (b.southwest.latitude + b.northeast.latitude) / 2,
        (b.southwest.longitude + b.northeast.longitude) / 2,
      ),
      zoom: markers.length == 1 ? 13 : 10,
    );
  }

  Future<void> _home(LatLng here) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.animateCamera(CameraUpdate.newLatLngZoom(here, _cityZoom));
    } catch (_) {
      // Not laid out yet; the next build tries again.
      _homed = false;
    }
  }

  Future<void> _fit(List<FriendMarker> markers) async {
    final map = _map;
    final bounds = boundsOf(markers);
    if (map == null || bounds == null) return;
    try {
      if (markers.length == 1) {
        await map.animateCamera(
          CameraUpdate.newLatLngZoom(markers.single.position, 13),
        );
      } else {
        await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
      }
    } catch (_) {
      // The platform view may not be laid out yet; the next data arrival
      // tries again.
      _fitted = false;
    }
  }

  void _ensureIcons(List<FriendMarker> markers, ThemeData theme, DateTime now) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final m in markers) {
      final key = m.iconKey(now);
      if (_ready.containsKey(key) || _requested.contains(key)) continue;
      _requested.add(key);
      final driving = m.isDriving(now);
      unawaited(
        _icons
            .get(
              key: key,
              initials: m.initials,
              fill: driving
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondary,
              ring: driving ? theme.colorScheme.tertiary : Colors.white,
              devicePixelRatio: dpr,
              stale: m.isStale(now),
            )
            .then((icon) {
              if (!mounted) return;
              setState(() => _ready[key] = icon);
            })
            .catchError((Object _) {
              _requested.remove(key);
            }),
      );
    }
  }

  Marker _placeMarker(BuildContext context, Place p) => Marker(
    markerId: MarkerId('place:${p.id}'),
    position: LatLng(p.lat, p.lon),
    icon: BitmapDescriptor.defaultMarkerWithHue(_placeHue(p)),
    infoWindow: InfoWindow(title: p.label),
    onTap: () => context.push(Routes.place(p.id)),
  );

  Circle _placeRadius(ThemeData theme, Place p) => Circle(
    circleId: CircleId('place-radius:${p.id}'),
    center: LatLng(p.lat, p.lon),
    radius: p.radiusM,
    strokeWidth: 1,
    strokeColor: theme.colorScheme.tertiary.withValues(alpha: 0.6),
    fillColor: theme.colorScheme.tertiary.withValues(alpha: 0.08),
  );

  static double _placeHue(Place p) => switch (PlaceKind.fromWire(p.kind)) {
    PlaceKind.home => BitmapDescriptor.hueGreen,
    PlaceKind.work => BitmapDescriptor.hueAzure,
    PlaceKind.school => BitmapDescriptor.hueViolet,
    PlaceKind.other => BitmapDescriptor.hueOrange,
  };

  Future<void> _showFriend(BuildContext context, FriendMarker m) =>
      showDrivalrySheet<void>(context, builder: (_) => FriendSheet(marker: m));
}

/// Bottom sheet for a tapped marker: who, where they are at, and two ways on.
class FriendSheet extends ConsumerWidget {
  const FriendSheet({super.key, required this.marker});

  final FriendMarker marker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now().toUtc();
    final row = marker.row;
    final battery = row.battery;
    final driving = marker.isDriving(now);
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final detail = [
      marker.statusLine(now),
      if (battery != null) '${(battery * 100).round()}% battery',
      if (driving && row.speed != null) formatSpeed(row.speed!, units),
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Avatar(
              name: marker.title,
              size: AvatarSize.lg,
              color: driving ? scheme.primary : scheme.secondary,
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(marker.title, style: context.title),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      if (driving) ...[
                        PulsingDot(color: scheme.primary, size: 6),
                        const SizedBox(width: Space.xs),
                      ],
                      Expanded(child: Text(detail, style: context.caption)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        SecondaryButton(
          label: 'Directions',
          icon: Icons.directions_outlined,
          onPressed: () => launchUrl(
            Uri.parse(
              'https://www.google.com/maps/search/?api=1&query='
              '${row.lat},${row.lon}',
            ),
            mode: LaunchMode.externalApplication,
          ),
        ),
        const SizedBox(height: Space.sm),
        PrimaryButton(
          label: 'View profile',
          icon: Icons.person_outline,
          onPressed: () {
            Navigator.of(context).pop();
            context.push(Routes.userProfile(row.userId));
          },
        ),
      ],
    );
  }
}

/// Calm panel in place of the map when it cannot render.
class _MapNotice extends StatelessWidget {
  const _MapNotice({
    required this.kicker,
    required this.text,
    this.action,
    this.embedded = false,
  });

  final String kicker;
  final String text;
  final Widget? action;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      // Behind the Drive sheet only the upper half shows.
      alignment: embedded ? const Alignment(0, -0.45) : Alignment.center,
      padding: const EdgeInsets.all(Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Kicker(kicker),
          const SizedBox(height: Space.md),
          Text(text, textAlign: TextAlign.center, style: context.title),
          if (action != null) ...[const SizedBox(height: Space.xl), action!],
        ],
      ),
    );
  }
}

/// "No friends on the map yet · Add friend", floating over the map.
class _NoFriendsNotice extends StatelessWidget {
  const _NoFriendsNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.cardRadius,
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
        borderRadius: Radii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.xs,
            Space.sm,
            Space.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('No friends on the map yet', style: context.label),
              ),
              TextButton.icon(
                onPressed: () => context.push(Routes.addFriend),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add friend'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "All" plus one chip per circle; filters the markers by membership.
class _CircleChips extends StatelessWidget {
  const _CircleChips({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(String, String)> options;
  final String? selected;
  final void Function(String? id) onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final (id, name) in options) ...[
            const SizedBox(width: Space.sm),
            ChoiceChip(
              label: Text(name),
              selected: selected == id,
              onSelected: (_) => onSelected(selected == id ? null : id),
            ),
          ],
        ],
      ),
    );
  }
}

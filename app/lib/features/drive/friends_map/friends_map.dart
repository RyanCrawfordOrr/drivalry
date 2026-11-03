import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/bootstrap.dart';
import '../../../app/routes.dart';
import '../../../config/env.dart';
import '../../../data/repos/presence_repo.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';
import '../../../data/db/database.dart' show Place;
import '../../../data/repos/circles_sync.dart';
import '../../../data/repos/places_repo.dart';
import '../../places/save_place_sheet.dart';
import 'friend_marker.dart';
import 'marker_icons.dart';

/// Replaces the Google map surface when set. Tests and the store-art renderer
/// (`test/art/`) use it: platform views do not exist there, so they draw a
/// stand-in and keep the chips, buttons and notices that sit on top real.
final friendsMapSurfaceProvider = Provider<WidgetBuilder?>((_) => null);

/// Live map of friends and circle members (ADR-018). Embedded at the top of
/// the Drive tab and shown full screen at [Routes.friendsMap]. Subscribes to
/// presence only while mounted.
class FriendsMap extends ConsumerStatefulWidget {
  const FriendsMap({super.key, this.fullScreen = false});

  final bool fullScreen;

  @override
  ConsumerState<FriendsMap> createState() => _FriendsMapState();
}

class _FriendsMapState extends ConsumerState<FriendsMap> {
  static const _usa = CameraPosition(target: LatLng(39.5, -98.35), zoom: 3);

  GoogleMapController? _map;
  bool _fitted = false;

  /// Circle id to filter by, or null for everyone.
  String? _circleFilter;
  final _icons = MarkerIconCache();
  final Map<String, BitmapDescriptor> _ready = {};
  final Set<String> _requested = {};

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = ref.watch(friendsMapSurfaceProvider);
    if (surface == null && !Env.hasSupabase) {
      return _MapNotice(
        icon: Icons.cloud_off_outlined,
        text:
            'Offline build: the friends map needs the Drivalry cloud project.',
      );
    }
    if (!ref.watch(isSignedInProvider)) {
      return _MapNotice(
        icon: Icons.people_outline,
        text: 'Sign in to see your friends on the map.',
        action: FilledButton.tonal(
          onPressed: () => context.push(Routes.signIn),
          child: const Text('Sign in'),
        ),
      );
    }
    final mapsReady = ref.watch(mapsReadyProvider);
    if (surface == null && mapsReady.value != true) {
      return _MapNotice(
        icon: Icons.map_outlined,
        text: mapsReady.isLoading
            ? 'Loading map…'
            : 'Map unavailable: build with --dart-define-from-file=../.env '
                  'to show friends.',
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
    if (!_fitted && markers.isNotEmpty && _map != null) {
      _fitted = true;
      unawaited(_fit(markers));
    }

    return Stack(
      children: [
        if (surface != null)
          Positioned.fill(child: surface(context))
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
              }
            },
          ),
        if (circles.isNotEmpty)
          Positioned(
            top: 8,
            left: 8,
            right: 60,
            child: _CircleChips(
              options: [for (final c in circles) (c.id, c.name)],
              selected: filter,
              onSelected: (id) => setState(() {
                _circleFilter = id;
                _fitted = false;
              }),
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              if (!widget.fullScreen)
                IconButton.filledTonal(
                  tooltip: 'Expand map',
                  onPressed: () => context.push(Routes.friendsMap),
                  icon: const Icon(Icons.open_in_full),
                ),
              IconButton.filledTonal(
                tooltip: 'Show everyone',
                onPressed: markers.isEmpty ? null : () => _fit(markers),
                icon: const Icon(Icons.fit_screen_outlined),
              ),
            ],
          ),
        ),
        if (markers.isEmpty && !presence.isLoading)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'No friends sharing yet',
                        style: theme.textTheme.bodyMedium,
                      ),
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
          ),
        if (presence.isLoading && markers.isEmpty)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  CameraPosition _initialCamera(List<FriendMarker> markers) {
    if (markers.isEmpty) return _usa;
    final b = boundsOf(markers)!;
    return CameraPosition(
      target: LatLng(
        (b.southwest.latitude + b.northeast.latitude) / 2,
        (b.southwest.longitude + b.northeast.longitude) / 2,
      ),
      zoom: markers.length == 1 ? 13 : 10,
    );
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
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => FriendSheet(marker: m),
      );
}

/// Bottom sheet for a tapped marker.
class FriendSheet extends StatelessWidget {
  const FriendSheet({super.key, required this.marker});

  final FriendMarker marker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final row = marker.row;
    final battery = row.battery;
    final driving = marker.isDriving(now);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: driving
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
                foregroundColor: Colors.white,
                child: Text(marker.initials),
              ),
              title: Text(marker.title, style: theme.textTheme.titleMedium),
              subtitle: Text(
                [
                  marker.statusLine(now),
                  if (battery != null) '${(battery * 100).round()}% battery',
                  if (driving && row.speed != null)
                    '${(row.speed! * 2.23694).round()} mph',
                ].join(' · '),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query='
                        '${row.lat},${row.lon}',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Open in Google Maps'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(Routes.userProfile(row.userId));
                    },
                    icon: const Icon(Icons.person_outline),
                    label: const Text('View profile'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
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
            const SizedBox(width: 6),
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

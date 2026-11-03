import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../../config/env.dart';
import '../../../data/convoy/eta.dart';
import '../../../data/google/places_client.dart' show StopCategory;
import '../../../data/google/routes_client.dart' show LatLon;
import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';
import '../../drive/friends_map/marker_icons.dart';
import '../live/convoy_live.dart';
import '../positions/peer_positions.dart';
import 'destination_picker.dart';

/// Icon for a stop category; tolerant of categories added later.
IconData stopIcon(StopCategory c) => switch (c.wire) {
  'gas' => Icons.local_gas_station_outlined,
  'food' => Icons.restaurant_outlined,
  'restroom' => Icons.wc_outlined,
  'photo' => Icons.photo_camera_outlined,
  'lodging' => Icons.hotel_outlined,
  'charging' => Icons.ev_station_outlined,
  _ => Icons.place_outlined,
};

/// Positions older than this are drawn faded.
const staleAfter = Duration(minutes: 2);

/// The shared convoy map: every car as an initials pin (leader ringed),
/// the destination, accepted stops, the regroup pin and my routed line.
/// Long-press (leader only) drops a regroup pin or moves the destination.
/// Without a Maps key the same data is shown as a list.
class ConvoyMap extends ConsumerStatefulWidget {
  const ConvoyMap({super.key, required this.convoyId});

  final String convoyId;

  @override
  ConsumerState<ConvoyMap> createState() => _ConvoyMapState();
}

class _ConvoyMapState extends ConsumerState<ConvoyMap> {
  static const _usa = CameraPosition(target: LatLng(39.5, -98.35), zoom: 3);

  GoogleMapController? _map;
  bool _fitted = false;
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
    final id = widget.convoyId;
    if (!Env.hasGoogleMaps) {
      return _PositionsList(convoyId: id);
    }
    final mapsReady = ref.watch(mapsReadyProvider);
    if (mapsReady.value != true) {
      return Center(
        child: Text(
          mapsReady.isLoading ? 'Loading map…' : 'Map unavailable.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final theme = Theme.of(context);
    final me = ref.watch(currentUserIdProvider);
    final convoy = ref.watch(convoyProvider(id));
    final leader = ref.watch(convoyLeaderProvider(id));
    final amLeader = ref.watch(amConvoyLeaderProvider(id));
    final members = ref.watch(convoyMembersProvider(id)).value ?? const [];
    final positions = ref.watch(peerPositionsProvider(id)).value ?? const {};
    final etas = ref.watch(convoyEtasProvider(id)).value ?? const {};
    final lost = ref.watch(lostSheepProvider(id)).value ?? const {};
    final regroup = ref.watch(regroupPinProvider(id)).value;
    final stops = ref.watch(convoyStopsProvider(id)).value ?? const [];
    final live = ref.watch(convoyLiveProvider(id));
    final now = DateTime.now().millisecondsSinceEpoch;

    final markers = <Marker>{};
    final points = <LatLng>[];
    for (final m in members) {
      if (!m.isPresent) continue;
      final p = positions[m.userId];
      if (p == null) continue;
      final stale = now - p.t > staleAfter.inMilliseconds;
      final isLeader = m.userId == leader;
      final isLost = lost.containsKey(m.userId);
      final fill = isLeader
          ? theme.colorScheme.primary
          : m.userId == me
          ? theme.colorScheme.tertiary
          : theme.colorScheme.secondary;
      final ring = isLost ? theme.colorScheme.error : fill;
      final key = '${m.initials}|$isLeader|$isLost|$stale|${m.userId == me}';
      _ensureIcon(
        key,
        initials: m.initials,
        fill: fill,
        ring: ring,
        stale: stale,
      );
      final pos = LatLng(p.lat, p.lon);
      points.add(pos);
      final eta = etas[m.userId];
      markers.add(
        Marker(
          markerId: MarkerId('car:${m.userId}'),
          position: pos,
          anchor: const Offset(0.5, 0.5),
          rotation: 0,
          zIndexInt: isLeader ? 3 : 2,
          icon:
              _ready[key] ??
              BitmapDescriptor.defaultMarkerWithHue(
                isLeader ? BitmapDescriptor.hueBlue : BitmapDescriptor.hueGreen,
              ),
          infoWindow: InfoWindow(
            title: m.userId == me ? 'You' : m.name,
            snippet: [
              if (isLeader) 'Leader',
              if (eta != null) 'ETA ${eta.estimated ? '~' : ''}${eta.label}',
              if (isLost) 'Lost sheep',
              if (stale) 'Last seen a while ago',
            ].join(' · '),
          ),
        ),
      );
    }
    final dest = convoy?.destination;
    if (dest != null) {
      final pos = LatLng(dest.lat, dest.lon);
      points.add(pos);
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: dest.name, snippet: 'Destination'),
        ),
      );
    }
    for (final s in stops) {
      if (s.status != StopStatus.accepted) continue;
      markers.add(
        Marker(
          markerId: MarkerId('stop:${s.id}'),
          position: LatLng(s.lat, s.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: s.name,
            snippet: '${s.category.label} stop · accepted',
          ),
        ),
      );
    }
    if (regroup != null) {
      final pos = LatLng(regroup.lat, regroup.lon);
      points.add(pos);
      markers.add(
        Marker(
          markerId: const MarkerId('regroup'),
          position: pos,
          zIndexInt: 4,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Regroup here',
            snippet: regroup.name ?? 'Set by the leader',
          ),
        ),
      );
    }
    final route = live?.eta.last?.polyline ?? const <LatLon>[];
    final polylines = <Polyline>{
      if (route.length >= 2)
        Polyline(
          polylineId: const PolylineId('my-route'),
          points: [for (final p in route) LatLng(p.lat, p.lon)],
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
          width: 4,
        ),
    };
    if (!_fitted && points.isNotEmpty && _map != null) {
      _fitted = true;
      unawaited(_fit(points));
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: points.isEmpty
              ? _usa
              : CameraPosition(target: points.first, zoom: 11),
          markers: markers,
          polylines: polylines,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          onLongPress: amLeader
              ? (pos) => _leaderMenu(context, live, pos)
              : null,
          onMapCreated: (c) {
            _map = c;
            if (points.isNotEmpty && !_fitted) {
              _fitted = true;
              unawaited(_fit(points));
            }
          },
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              IconButton.filledTonal(
                tooltip: 'Show everyone',
                onPressed: points.isEmpty ? null : () => _fit(points),
                icon: const Icon(Icons.fit_screen_outlined),
              ),
              if (me != null && positions[me] != null)
                IconButton.filledTonal(
                  tooltip: 'Centre on me',
                  onPressed: () => _map?.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(positions[me]!.lat, positions[me]!.lon),
                      14,
                    ),
                  ),
                  icon: const Icon(Icons.my_location),
                ),
            ],
          ),
        ),
        if (lost.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lostText(lost.keys, members, me),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (points.isEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  convoy?.isActive == true
                      ? 'Waiting for the first positions. They arrive once '
                            'cars start moving.'
                      : 'Positions appear here once the leader starts the '
                            'trip.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _lostText(
    Iterable<String> ids,
    List<ConvoyMember> members,
    String? me,
  ) {
    final names = [
      for (final id in ids)
        id == me
            ? 'You'
            : members.where((m) => m.userId == id).firstOrNull?.name ?? 'A car',
    ];
    return names.length == 1
        ? '${names.single} ${names.single == 'You' ? 'are' : 'is'} falling '
              'behind.'
        : '${names.join(', ')} are falling behind.';
  }

  void _ensureIcon(
    String key, {
    required String initials,
    required Color fill,
    required Color ring,
    required bool stale,
  }) {
    if (_ready.containsKey(key) || _requested.contains(key)) return;
    _requested.add(key);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    unawaited(
      _icons
          .get(
            key: key,
            initials: initials,
            fill: fill,
            ring: ring,
            devicePixelRatio: dpr,
            stale: stale,
          )
          .then((d) {
            if (mounted) setState(() => _ready[key] = d);
          })
          .catchError((Object e) {
            debugPrint('marker icon failed: $e');
          }),
    );
  }

  Future<void> _fit(List<LatLng> pts) async {
    final map = _map;
    if (map == null || pts.isEmpty) return;
    if (pts.length == 1) {
      await map.animateCamera(CameraUpdate.newLatLngZoom(pts.single, 13));
      return;
    }
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLon = pts.first.longitude, maxLon = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    await map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        64,
      ),
    );
  }

  Future<void> _leaderMenu(
    BuildContext context,
    ConvoyLive? live,
    LatLng pos,
  ) async {
    final repo = ref.read(convoyRepoProvider);
    final id = widget.convoyId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.group_work_outlined),
              title: const Text('Regroup here'),
              subtitle: const Text('Everyone gets a pin and a nudge.'),
              enabled: live != null,
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(live?.setRegroup(pos.latitude, pos.longitude));
              },
            ),
            if (live?.regroupPin != null)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Clear regroup pin'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(live?.clearRegroup());
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Set destination here'),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(
                  repo.setDestination(
                    id,
                    Destination(
                      name: 'Pinned destination',
                      lat: pos.latitude,
                      lon: pos.longitude,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search a destination'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final d = await showDestinationPicker(context);
                if (d != null) await repo.setDestination(id, d);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback without a Maps key: who is where, relative to the leader.
class _PositionsList extends ConsumerWidget {
  const _PositionsList({required this.convoyId});
  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final members =
        ref.watch(convoyMembersProvider(convoyId)).value ?? const [];
    final positions =
        ref.watch(peerPositionsProvider(convoyId)).value ?? const {};
    final etas = ref.watch(convoyEtasProvider(convoyId)).value ?? const {};
    final leader = ref.watch(convoyLeaderProvider(convoyId));
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final lead = leader == null ? null : positions[leader];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'No map in this build. Positions and ETAs still flow between the '
          'cars:',
          style: theme.textTheme.bodySmall,
        ),
        for (final m in members)
          if (m.isPresent)
            ListTile(
              dense: true,
              leading: Icon(
                m.userId == leader
                    ? Icons.star_outline
                    : Icons.directions_car_outlined,
              ),
              title: Text(m.name),
              subtitle: Text(
                _describe(positions[m.userId], lead, etas[m.userId], units),
              ),
            ),
      ],
    );
  }

  static String _describe(
    PeerPosition? p,
    PeerPosition? lead,
    EtaInfo? eta,
    SpeedUnits units,
  ) {
    if (p == null) return 'No position yet';
    final parts = <String>[];
    if (lead != null && lead.userId != p.userId) {
      final d = LatLon(lead.lat, lead.lon).distanceTo(LatLon(p.lat, p.lon));
      parts.add('${formatDistance(d, units)} from the leader');
    }
    if (eta != null) parts.add('ETA ${eta.estimated ? '~' : ''}${eta.label}');
    return parts.isEmpty ? 'Sharing position' : parts.join(' · ');
  }
}

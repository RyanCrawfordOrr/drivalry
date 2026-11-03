/// Typed mirrors of the maps in docs/08-tracking-channel.md.
///
/// Parsing is lenient on purpose: unknown keys are ignored and missing
/// optional values become null, so an older plugin build never crashes a
/// newer Dart build or vice versa.
library;

/// Where the native state machine is (docs/08 §2). `ending` is internal to
/// the plugin and never surfaces here.
enum TrackingPhase {
  idle,
  tentative,
  active;

  static TrackingPhase fromWire(String? wire) => switch (wire) {
    'tentative' => tentative,
    'active' => active,
    _ => idle,
  };
}

enum LocationPermission {
  denied,
  whileInUse,
  always;

  static LocationPermission fromWire(String? wire) => switch (wire) {
    'always' => always,
    'whileInUse' => whileInUse,
    _ => denied,
  };
}

enum SimplePermission {
  denied,
  granted,
  notDetermined;

  static SimplePermission fromWire(String? wire) => switch (wire) {
    'granted' => granted,
    'denied' => denied,
    _ => notDetermined,
  };
}

class TrackingPermissions {
  const TrackingPermissions({
    this.location = LocationPermission.denied,
    this.preciseLocation = false,
    this.motion = SimplePermission.notDetermined,
    this.notifications = SimplePermission.notDetermined,
    this.bluetooth = SimplePermission.notDetermined,
  });

  factory TrackingPermissions.fromMap(Map<Object?, Object?>? m) {
    if (m == null) return const TrackingPermissions();
    return TrackingPermissions(
      location: LocationPermission.fromWire(m['location'] as String?),
      preciseLocation: m['preciseLocation'] as bool? ?? false,
      motion: SimplePermission.fromWire(m['motion'] as String?),
      notifications: SimplePermission.fromWire(m['notifications'] as String?),
      bluetooth: SimplePermission.fromWire(m['bluetooth'] as String?),
    );
  }

  final LocationPermission location;
  final bool preciseLocation;
  final SimplePermission motion;
  final SimplePermission notifications;
  final SimplePermission bluetooth;

  /// Everything automatic trip detection needs.
  bool get sufficientForAutoTracking =>
      location == LocationPermission.always &&
      preciseLocation &&
      motion == SimplePermission.granted;

  /// Enough to record a trip the user starts by hand with the app open.
  bool get sufficientForManualTracking =>
      location != LocationPermission.denied && preciseLocation;

  Map<String, Object?> toMap() => {
    'location': location.name,
    'preciseLocation': preciseLocation,
    'motion': motion.name,
    'notifications': notifications.name,
    'bluetooth': bluetooth.name,
  };
}

class TrackingState {
  const TrackingState({
    this.phase = TrackingPhase.idle,
    this.tripId,
    this.tripStartedAt,
    this.enabled = true,
    this.pausedUntil = 0,
    this.permissions = const TrackingPermissions(),
    this.spooledEvents = 0,
    this.pluginAvailable = true,
  });

  /// State reported when no native plugin answers (desktop, tests).
  const TrackingState.unavailable()
    : this(enabled: false, pluginAvailable: false);

  factory TrackingState.fromMap(Map<Object?, Object?> m) => TrackingState(
    phase: TrackingPhase.fromWire(m['phase'] as String?),
    tripId: m['tripId'] as String?,
    tripStartedAt: (m['tripStartedAt'] as num?)?.toInt(),
    enabled: m['enabled'] as bool? ?? true,
    pausedUntil: (m['pausedUntil'] as num?)?.toInt() ?? 0,
    permissions: TrackingPermissions.fromMap(
      m['permissions'] as Map<Object?, Object?>?,
    ),
    spooledEvents: (m['spooledEvents'] as num?)?.toInt() ?? 0,
  );

  final TrackingPhase phase;
  final String? tripId;
  final int? tripStartedAt;
  final bool enabled;

  /// Epoch ms; 0 when not paused.
  final int pausedUntil;
  final TrackingPermissions permissions;
  final int spooledEvents;

  /// False when the platform has no tracking plugin (tests, desktop).
  final bool pluginAvailable;

  bool isPausedAt(int nowMs) => pausedUntil > nowMs;

  TrackingState copyWith({
    TrackingPhase? phase,
    String? tripId,
    int? tripStartedAt,
    bool? enabled,
    int? pausedUntil,
    TrackingPermissions? permissions,
    int? spooledEvents,
    bool clearTrip = false,
  }) => TrackingState(
    phase: phase ?? this.phase,
    tripId: clearTrip ? null : (tripId ?? this.tripId),
    tripStartedAt: clearTrip ? null : (tripStartedAt ?? this.tripStartedAt),
    enabled: enabled ?? this.enabled,
    pausedUntil: pausedUntil ?? this.pausedUntil,
    permissions: permissions ?? this.permissions,
    spooledEvents: spooledEvents ?? this.spooledEvents,
    pluginAvailable: pluginAvailable,
  );
}

class TrackingDiagnostics {
  const TrackingDiagnostics({
    this.lastTriggerAt,
    this.lastTriggerKind,
    this.tentativeStarts = 0,
    this.confirmedTrips = 0,
    this.discardedTentatives = 0,
    this.lastTripEndedAt,
    this.lastTripEndReason,
    this.batteryLevel,
    this.serviceRunning = false,
  });

  factory TrackingDiagnostics.fromMap(Map<Object?, Object?> m) =>
      TrackingDiagnostics(
        lastTriggerAt: (m['lastTriggerAt'] as num?)?.toInt(),
        lastTriggerKind: m['lastTriggerKind'] as String?,
        tentativeStarts: (m['tentativeStarts'] as num?)?.toInt() ?? 0,
        confirmedTrips: (m['confirmedTrips'] as num?)?.toInt() ?? 0,
        discardedTentatives: (m['discardedTentatives'] as num?)?.toInt() ?? 0,
        lastTripEndedAt: (m['lastTripEndedAt'] as num?)?.toInt(),
        lastTripEndReason: m['lastTripEndReason'] as String?,
        batteryLevel: (m['batteryLevel'] as num?)?.toDouble(),
        serviceRunning: m['serviceRunning'] as bool? ?? false,
      );

  final int? lastTriggerAt;
  final String? lastTriggerKind;
  final int tentativeStarts;
  final int confirmedTrips;
  final int discardedTentatives;
  final int? lastTripEndedAt;
  final String? lastTripEndReason;
  final double? batteryLevel;
  final bool serviceRunning;

  Map<String, Object?> toMap() => {
    'lastTriggerAt': lastTriggerAt,
    'lastTriggerKind': lastTriggerKind,
    'tentativeStarts': tentativeStarts,
    'confirmedTrips': confirmedTrips,
    'discardedTentatives': discardedTentatives,
    'lastTripEndedAt': lastTripEndedAt,
    'lastTripEndReason': lastTripEndReason,
    'batteryLevel': batteryLevel,
    'serviceRunning': serviceRunning,
  };
}

// ------------------------------------------------------------------ events --

/// One GPS fix as the plugin reports it (docs/08 §4 `fixes`).
class Fix {
  const Fix({
    required this.t,
    required this.lat,
    required this.lon,
    required this.accuracy,
    this.speed,
    this.heading,
    this.altitude,
    this.speedAccuracy,
    this.headingAccuracy,
  });

  factory Fix.fromMap(Map<Object?, Object?> m) => Fix(
    t: (m['t'] as num).toInt(),
    lat: (m['lat'] as num).toDouble(),
    lon: (m['lon'] as num).toDouble(),
    accuracy: (m['accuracy'] as num?)?.toDouble() ?? 50,
    speed: (m['speed'] as num?)?.toDouble(),
    heading: (m['heading'] as num?)?.toDouble(),
    altitude: (m['altitude'] as num?)?.toDouble(),
    speedAccuracy: (m['speedAccuracy'] as num?)?.toDouble(),
    headingAccuracy: (m['headingAccuracy'] as num?)?.toDouble(),
  );

  final int t;
  final double lat;
  final double lon;
  final double accuracy;
  final double? speed;
  final double? heading;
  final double? altitude;
  final double? speedAccuracy;
  final double? headingAccuracy;

  Map<String, Object?> toMap() => {
    't': t,
    'lat': lat,
    'lon': lon,
    'accuracy': accuracy,
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
    if (altitude != null) 'altitude': altitude,
    if (speedAccuracy != null) 'speedAccuracy': speedAccuracy,
    if (headingAccuracy != null) 'headingAccuracy': headingAccuracy,
  };
}

class MotionPeakSample {
  const MotionPeakSample({required this.t, required this.peak});

  factory MotionPeakSample.fromMap(Map<Object?, Object?> m) => MotionPeakSample(
    t: (m['t'] as num).toInt(),
    peak: (m['peak'] as num).toDouble(),
  );

  final int t;
  final double peak;

  Map<String, Object?> toMap() => {'t': t, 'kind': 'accelPeak', 'peak': peak};
}

/// Lifecycle value carried by a [PhaseEvent].
enum TripPhaseSignal {
  tentative,
  active,
  ended,
  discarded;

  static TripPhaseSignal? fromWire(String? wire) => switch (wire) {
    'tentative' => tentative,
    'active' => active,
    'ended' => ended,
    'discarded' => discarded,
    _ => null,
  };
}

/// Raw phone-usage signal names (docs/08 §4 `phone`).
enum PhoneSignal {
  unlock,
  screenOn,
  screenOff,
  interaction,
  callStart,
  callEnd,
  projectionOn,
  projectionOff,
  foreground,
  background;

  static PhoneSignal? fromWire(String? wire) {
    for (final v in values) {
      if (v.name == wire) return v;
    }
    return null;
  }
}

/// Everything the plugin can tell Dart. [TrackingEvent.fromMap] returns null
/// for maps of an unknown type so a newer plugin never breaks an older app.
sealed class TrackingEvent {
  const TrackingEvent({required this.tripId, required this.t});

  final String? tripId;

  /// Epoch ms.
  final int t;

  static TrackingEvent? fromMap(Map<Object?, Object?> m) {
    final tripId = m['tripId'] as String?;
    final t = (m['t'] as num?)?.toInt() ?? 0;
    switch (m['type']) {
      case 'phase':
        final phase = TripPhaseSignal.fromWire(m['phase'] as String?);
        if (phase == null || tripId == null) return null;
        return PhaseEvent(
          tripId: tripId,
          t: t,
          phase: phase,
          reason: m['reason'] as String?,
          startedAt: (m['startedAt'] as num?)?.toInt(),
        );
      case 'fixes':
        if (tripId == null) return null;
        return FixesEvent(
          tripId: tripId,
          t: t,
          fixes: [
            for (final f in (m['fixes'] as List?) ?? const [])
              Fix.fromMap(f as Map<Object?, Object?>),
          ],
        );
      case 'motion':
        if (tripId == null) return null;
        return MotionPeaksEvent(
          tripId: tripId,
          t: t,
          peaks: [
            for (final e in (m['events'] as List?) ?? const [])
              MotionPeakSample.fromMap(e as Map<Object?, Object?>),
          ],
        );
      case 'phone':
        final kind = PhoneSignal.fromWire(m['kind'] as String?);
        if (kind == null || tripId == null) return null;
        return PhoneEventRaw(tripId: tripId, t: t, kind: kind);
      case 'hint':
        if (tripId == null) return null;
        return HintEvent(
          tripId: tripId,
          t: t,
          kind: m['kind'] as String? ?? 'unknown',
          name: m['name'] as String?,
        );
      case 'parkedFix':
        final lat = m['lat'] as num?;
        final lon = m['lon'] as num?;
        if (lat == null || lon == null) return null;
        return ParkedFixEvent(
          t: t,
          lat: lat.toDouble(),
          lon: lon.toDouble(),
          accuracy: (m['accuracy'] as num?)?.toDouble() ?? 50,
          speed: (m['speed'] as num?)?.toDouble(),
          heading: (m['heading'] as num?)?.toDouble(),
        );
      case 'error':
        return TrackingError(
          t: t,
          code: m['code'] as String? ?? 'unknown',
          message: m['message'] as String? ?? '',
        );
      default:
        return null;
    }
  }

  Map<String, Object?> toMap();
}

/// A free position the OS handed the plugin while idle (docs/08 §4
/// `parkedFix`): significant-change callbacks and geofence exits. Feeds the
/// owner's presence while parked without ever turning the GPS radio on.
final class ParkedFixEvent extends TrackingEvent {
  const ParkedFixEvent({
    required super.t,
    required this.lat,
    required this.lon,
    required this.accuracy,
    this.speed,
    this.heading,
  }) : super(tripId: null);

  final double lat;
  final double lon;
  final double accuracy;
  final double? speed;
  final double? heading;

  @override
  Map<String, Object?> toMap() => {
    'type': 'parkedFix',
    'tripId': null,
    't': t,
    'lat': lat,
    'lon': lon,
    'accuracy': accuracy,
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
  };
}

/// Answer to `getLastKnownLocation` (docs/08 §3).
class LastKnownLocation {
  const LastKnownLocation({
    required this.t,
    required this.lat,
    required this.lon,
    required this.accuracy,
    this.speed,
    this.heading,
  });

  factory LastKnownLocation.fromMap(Map<Object?, Object?> m) =>
      LastKnownLocation(
        t: (m['t'] as num?)?.toInt() ?? 0,
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        accuracy: (m['accuracy'] as num?)?.toDouble() ?? 50,
        speed: (m['speed'] as num?)?.toDouble(),
        heading: (m['heading'] as num?)?.toDouble(),
      );

  final int t;
  final double lat;
  final double lon;
  final double accuracy;
  final double? speed;
  final double? heading;

  Map<String, Object?> toMap() => {
    't': t,
    'lat': lat,
    'lon': lon,
    'accuracy': accuracy,
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
  };
}

final class PhaseEvent extends TrackingEvent {
  const PhaseEvent({
    required String super.tripId,
    required super.t,
    required this.phase,
    this.reason,
    this.startedAt,
  });

  final TripPhaseSignal phase;
  final String? reason;
  final int? startedAt;

  @override
  Map<String, Object?> toMap() => {
    'type': 'phase',
    'tripId': tripId,
    't': t,
    'phase': phase.name,
    if (reason != null) 'reason': reason,
    if (startedAt != null) 'startedAt': startedAt,
  };
}

final class FixesEvent extends TrackingEvent {
  const FixesEvent({
    required String super.tripId,
    required super.t,
    required this.fixes,
  });

  final List<Fix> fixes;

  @override
  Map<String, Object?> toMap() => {
    'type': 'fixes',
    'tripId': tripId,
    't': t,
    'fixes': [for (final f in fixes) f.toMap()],
  };
}

final class MotionPeaksEvent extends TrackingEvent {
  const MotionPeaksEvent({
    required String super.tripId,
    required super.t,
    required this.peaks,
  });

  final List<MotionPeakSample> peaks;

  @override
  Map<String, Object?> toMap() => {
    'type': 'motion',
    'tripId': tripId,
    't': t,
    'events': [for (final p in peaks) p.toMap()],
  };
}

final class PhoneEventRaw extends TrackingEvent {
  const PhoneEventRaw({
    required String super.tripId,
    required super.t,
    required this.kind,
  });

  final PhoneSignal kind;

  @override
  Map<String, Object?> toMap() => {
    'type': 'phone',
    'tripId': tripId,
    't': t,
    'kind': kind.name,
  };
}

final class HintEvent extends TrackingEvent {
  const HintEvent({
    required String super.tripId,
    required super.t,
    required this.kind,
    this.name,
  });

  /// bluetooth | carplay | androidAuto
  final String kind;
  final String? name;

  @override
  Map<String, Object?> toMap() => {
    'type': 'hint',
    'tripId': tripId,
    't': t,
    'kind': kind,
    if (name != null) 'name': name,
  };
}

final class TrackingError extends TrackingEvent {
  const TrackingError({
    required super.t,
    required this.code,
    required this.message,
  }) : super(tripId: null);

  final String code;
  final String message;

  @override
  Map<String, Object?> toMap() => {
    'type': 'error',
    'tripId': null,
    't': t,
    'code': code,
    'message': message,
  };
}

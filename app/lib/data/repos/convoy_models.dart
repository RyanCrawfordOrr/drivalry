import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../google/places_client.dart' show StopCategory;
import 'friends_repo.dart' show initialsOf;

/// Lifecycle of a convoy (docs/10 §2).
enum ConvoyStatus {
  planning,
  active,
  ended;

  static ConvoyStatus fromWire(String? w) => switch (w) {
    'active' => ConvoyStatus.active,
    'ended' => ConvoyStatus.ended,
    _ => ConvoyStatus.planning,
  };

  String get wire => name;
}

/// Where the convoy is going. Stored as JSON in `convoys.destination`.
class Destination {
  const Destination({
    required this.name,
    required this.lat,
    required this.lon,
    this.placeId,
  });

  static Destination? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = j.cast<String, dynamic>();
    final lat = m['lat'];
    final lon = m['lon'];
    if (lat is! num || lon is! num) return null;
    return Destination(
      name: m['name'] as String? ?? 'Destination',
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      placeId: m['placeId'] as String?,
    );
  }

  final String name;
  final double lat;
  final double lon;
  final String? placeId;

  Map<String, Object?> toJson() => {
    'name': name,
    'lat': lat,
    'lon': lon,
    'placeId': ?placeId,
  };
}

/// A road-trip group of 2–6 cars (docs/01 §4.6).
class Convoy {
  const Convoy({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.status,
    required this.inviteCode,
    required this.createdAt,
    this.destination,
    this.maxCars = 6,
    this.startedAt,
    this.endedAt,
    this.memberCount = 1,
  });

  /// From a `convoy_members` row with the `convoys` row embedded.
  factory Convoy.fromMembershipRow(Map<String, dynamic> r, {int? memberCount}) {
    final c = (r['convoys'] as Map).cast<String, dynamic>();
    return Convoy.fromJson(c, memberCount: memberCount);
  }

  factory Convoy.fromJson(Map<String, dynamic> c, {int? memberCount}) => Convoy(
    id: c['id'] as String,
    name: c['name'] as String? ?? '',
    createdBy: c['created_by'] as String? ?? '',
    status: ConvoyStatus.fromWire(c['status'] as String?),
    destination: Destination.fromJson(c['destination']),
    inviteCode: c['invite_code'] as String? ?? '',
    maxCars: (c['max_cars'] as num?)?.toInt() ?? 6,
    createdAt: _date(c['created_at']) ?? _epoch,
    startedAt: _date(c['started_at']),
    endedAt: _date(c['ended_at']),
    memberCount: memberCount ?? (c['member_count'] as num?)?.toInt() ?? 1,
  );

  final String id;
  final String name;
  final String createdBy;
  final ConvoyStatus status;
  final Destination? destination;

  /// Empty until the first fetch after creation (the server generates it).
  final String inviteCode;
  final int maxCars;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int memberCount;

  bool get isActive => status == ConvoyStatus.active;
  bool get isEnded => status == ConvoyStatus.ended;

  /// `drivalry://join/convoy/<code>`.
  String get inviteLink => 'drivalry://join/convoy/$inviteCode';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_by': createdBy,
    'status': status.wire,
    'destination': destination?.toJson(),
    'invite_code': inviteCode,
    'max_cars': maxCars,
    'created_at': createdAt.toIso8601String(),
    'started_at': startedAt?.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'member_count': memberCount,
  };

  Convoy copyWith({
    String? name,
    ConvoyStatus? status,
    Destination? destination,
    bool clearDestination = false,
    String? inviteCode,
    DateTime? startedAt,
    DateTime? endedAt,
    int? memberCount,
  }) => Convoy(
    id: id,
    name: name ?? this.name,
    createdBy: createdBy,
    status: status ?? this.status,
    destination: clearDestination ? null : destination ?? this.destination,
    inviteCode: inviteCode ?? this.inviteCode,
    maxCars: maxCars,
    createdAt: createdAt,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    memberCount: memberCount ?? this.memberCount,
  );
}

/// One car in a convoy with the public bits of the driver's profile.
class ConvoyMember {
  const ConvoyMember({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.avatarPath,
    this.carLabel,
    this.leftAt,
  });

  factory ConvoyMember.fromRow(Map<String, dynamic> r) {
    final p = (r['profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ConvoyMember(
      userId: r['user_id'] as String,
      handle: p['handle'] as String? ?? r['handle'] as String? ?? '',
      displayName:
          p['display_name'] as String? ?? r['display_name'] as String? ?? '',
      avatarPath: p['avatar_path'] as String? ?? r['avatar_path'] as String?,
      role: r['role'] as String? ?? 'member',
      carLabel: r['car_label'] as String?,
      joinedAt: _date(r['joined_at']) ?? _epoch,
      leftAt: _date(r['left_at']),
    );
  }

  final String userId;
  final String handle;
  final String displayName;
  final String? avatarPath;

  /// `leader` or `member`.
  final String role;
  final String? carLabel;
  final DateTime joinedAt;
  final DateTime? leftAt;

  bool get isLeader => role == 'leader';
  bool get isPresent => leftAt == null;
  String get name => displayName.trim().isNotEmpty ? displayName : '@$handle';
  String get initials => initialsOf(name);

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'handle': handle,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'role': role,
    'car_label': carLabel,
    'joined_at': joinedAt.toIso8601String(),
    'left_at': leftAt?.toIso8601String(),
  };
}

/// Status of a proposed stop (`stop_status` enum in 0001_init.sql).
enum StopStatus {
  proposed,
  accepted,
  rejected,
  done;

  static StopStatus fromWire(String? w) => switch (w) {
    'accepted' => StopStatus.accepted,
    'rejected' => StopStatus.rejected,
    'done' => StopStatus.done,
    _ => StopStatus.proposed,
  };

  String get wire => name;
}

/// A proposed or accepted stop with its votes.
class ConvoyStop {
  const ConvoyStop({
    required this.id,
    required this.convoyId,
    required this.proposedBy,
    required this.category,
    required this.name,
    required this.lat,
    required this.lon,
    required this.status,
    required this.createdAt,
    this.placeId,
    this.votes = const {},
  });

  factory ConvoyStop.fromRow(Map<String, dynamic> r) {
    final votes = <String, int>{};
    for (final v in (r['convoy_stop_votes'] as List? ?? const [])) {
      final m = (v as Map).cast<String, dynamic>();
      final uid = m['user_id'];
      final vote = m['vote'];
      if (uid is String && vote is num) votes[uid] = vote.toInt();
    }
    return ConvoyStop(
      id: r['id'] as String,
      convoyId: r['convoy_id'] as String? ?? '',
      proposedBy: r['proposed_by'] as String? ?? '',
      category: StopCategory.fromWire(r['category'] as String? ?? 'other'),
      name: r['name'] as String? ?? '',
      lat: (r['lat'] as num).toDouble(),
      lon: (r['lon'] as num).toDouble(),
      placeId: r['place_id'] as String?,
      status: StopStatus.fromWire(r['status'] as String?),
      createdAt: _date(r['created_at']) ?? _epoch,
      votes: votes,
    );
  }

  final String id;
  final String convoyId;
  final String proposedBy;
  final StopCategory category;
  final String name;
  final double lat;
  final double lon;
  final String? placeId;
  final StopStatus status;
  final DateTime createdAt;

  /// userId → +1 / -1.
  final Map<String, int> votes;

  int get upVotes => votes.values.where((v) => v > 0).length;
  int get downVotes => votes.values.where((v) => v < 0).length;
  int get score => votes.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'id': id,
    'convoy_id': convoyId,
    'proposed_by': proposedBy,
    'category': category.wire,
    'name': name,
    'lat': lat,
    'lon': lon,
    'place_id': placeId,
    'status': status.wire,
    'created_at': createdAt.toIso8601String(),
    'convoy_stop_votes': [
      for (final e in votes.entries) {'user_id': e.key, 'vote': e.value},
    ],
  };

  ConvoyStop copyWith({StopStatus? status, Map<String, int>? votes}) =>
      ConvoyStop(
        id: id,
        convoyId: convoyId,
        proposedBy: proposedBy,
        category: category,
        name: name,
        lat: lat,
        lon: lon,
        placeId: placeId,
        status: status ?? this.status,
        createdAt: createdAt,
        votes: votes ?? this.votes,
      );
}

/// Something one car paid for everyone (gas, tolls, food, lodging, other).
class ConvoyExpense {
  const ConvoyExpense({
    required this.id,
    required this.convoyId,
    required this.payerId,
    required this.amountCents,
    required this.category,
    required this.createdAt,
    this.currency = 'USD',
    this.note,
  });

  factory ConvoyExpense.fromRow(Map<String, dynamic> r) => ConvoyExpense(
    id: r['id'] as String,
    convoyId: r['convoy_id'] as String? ?? '',
    payerId: r['payer_id'] as String? ?? '',
    amountCents: (r['amount_cents'] as num).toInt(),
    currency: r['currency'] as String? ?? 'USD',
    category: r['category'] as String? ?? 'other',
    note: r['note'] as String?,
    createdAt: _date(r['created_at']) ?? _epoch,
  );

  final String id;
  final String convoyId;
  final String payerId;
  final int amountCents;
  final String currency;
  final String category;
  final String? note;
  final DateTime createdAt;

  static const categories = ['gas', 'tolls', 'food', 'lodging', 'other'];

  Map<String, dynamic> toJson() => {
    'id': id,
    'convoy_id': convoyId,
    'payer_id': payerId,
    'amount_cents': amountCents,
    'currency': currency,
    'category': category,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };
}

/// A small photo in the shared album (bucket `convoy-photos`).
class ConvoyPhoto {
  const ConvoyPhoto({
    required this.id,
    required this.convoyId,
    required this.userId,
    required this.storagePath,
    required this.takenAt,
    this.stopId,
  });

  factory ConvoyPhoto.fromRow(Map<String, dynamic> r) => ConvoyPhoto(
    id: r['id'] as String,
    convoyId: r['convoy_id'] as String? ?? '',
    userId: r['user_id'] as String? ?? '',
    stopId: r['stop_id'] as String?,
    storagePath: r['storage_path'] as String,
    takenAt: _date(r['taken_at']) ?? _epoch,
  );

  final String id;
  final String convoyId;
  final String userId;
  final String? stopId;
  final String storagePath;
  final DateTime takenAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'convoy_id': convoyId,
    'user_id': userId,
    'stop_id': stopId,
    'storage_path': storagePath,
    'taken_at': takenAt.toIso8601String(),
  };
}

/// The little a recap needs from a member's uploaded trip summaries.
class ConvoyTripSummary {
  const ConvoyTripSummary({
    required this.userId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceM,
    required this.scored,
    this.score,
    this.speedingSeconds = 0,
  });

  factory ConvoyTripSummary.fromRow(Map<String, dynamic> r) {
    var speeding = 0;
    for (final e in (r['trip_events'] as List? ?? const [])) {
      final m = (e as Map).cast<String, dynamic>();
      if (m['kind'] == 'speeding') {
        speeding += (m['duration_s'] as num?)?.toInt() ?? 0;
      }
    }
    return ConvoyTripSummary(
      userId: r['user_id'] as String,
      startedAt: _date(r['started_at']) ?? _epoch,
      endedAt: _date(r['ended_at']) ?? _epoch,
      distanceM: (r['distance_m'] as num?)?.toDouble() ?? 0,
      scored: r['scored'] == true && r['is_passenger'] != true,
      score: (r['score'] as num?)?.toInt(),
      speedingSeconds: speeding,
    );
  }

  final String userId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceM;
  final bool scored;
  final int? score;
  final int speedingSeconds;
}

enum ConvoyJoinError { invalidCode, full, notSignedIn, unavailable }

class ConvoyJoinException implements Exception {
  const ConvoyJoinException(this.error, [this.detail]);
  final ConvoyJoinError error;
  final String? detail;

  String get message => switch (error) {
    ConvoyJoinError.invalidCode => 'That invite code is not valid.',
    ConvoyJoinError.full => 'That convoy is full (six cars).',
    ConvoyJoinError.notSignedIn => 'Sign in first.',
    ConvoyJoinError.unavailable => 'Could not reach Drivalry. Try again.',
  };

  @override
  String toString() => 'ConvoyJoinException($error, $detail)';
}

/// Maps what `join_convoy` raises (0001_init.sql: P0001 invalid, P0002 full).
ConvoyJoinError mapConvoyJoinError(Object e) {
  if (e is PostgrestException) {
    if (e.code == 'P0001') return ConvoyJoinError.invalidCode;
    if (e.code == 'P0002') return ConvoyJoinError.full;
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid invite code')) return ConvoyJoinError.invalidCode;
    if (msg.contains('full')) return ConvoyJoinError.full;
  }
  return ConvoyJoinError.unavailable;
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

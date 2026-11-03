/// A row of `profiles`, as the app reads it.
class Profile {
  const Profile({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarPath,
    this.driverRating,
    this.passengerMarkedCount = 0,
    this.locationHidden = false,
    this.units = 'auto',
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    handle: j['handle'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    avatarPath: j['avatar_path'] as String?,
    driverRating: (j['driver_rating'] as num?)?.toDouble(),
    passengerMarkedCount: (j['passenger_marked_count'] as num?)?.toInt() ?? 0,
    locationHidden: j['location_hidden'] as bool? ?? false,
    units: j['units'] as String? ?? 'auto',
  );

  final String id;
  final String handle;
  final String displayName;

  /// Storage object path in bucket `avatars` (`<uid>/avatar.jpg`).
  final String? avatarPath;

  /// Rolling 30-day weighted average; null until five scored trips.
  final double? driverRating;
  final int passengerMarkedCount;

  /// The global "hide my location from everyone" switch (ADR-018).
  final bool locationHidden;
  final String units;

  Map<String, Object?> toJson() => {
    'id': id,
    'handle': handle,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'driver_rating': driverRating,
    'passenger_marked_count': passengerMarkedCount,
    'location_hidden': locationHidden,
    'units': units,
  };

  Profile copyWith({
    String? handle,
    String? displayName,
    String? avatarPath,
    bool clearAvatar = false,
    double? driverRating,
    int? passengerMarkedCount,
    bool? locationHidden,
  }) => Profile(
    id: id,
    handle: handle ?? this.handle,
    displayName: displayName ?? this.displayName,
    avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    driverRating: driverRating ?? this.driverRating,
    passengerMarkedCount: passengerMarkedCount ?? this.passengerMarkedCount,
    locationHidden: locationHidden ?? this.locationHidden,
    units: units,
  );

  /// The handle rule from `0001_init.sql`.
  static final RegExp handleRule = RegExp(r'^[a-z0-9_]{3,20}$');

  static String? validateHandle(String value) {
    final v = value.trim();
    if (v.length < 3) return 'At least 3 characters.';
    if (v.length > 20) return 'At most 20 characters.';
    if (!handleRule.hasMatch(v)) {
      return 'Lowercase letters, digits and underscores only.';
    }
    return null;
  }

  static String? validateDisplayName(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter a name.';
    if (v.length > 40) return 'At most 40 characters.';
    return null;
  }
}

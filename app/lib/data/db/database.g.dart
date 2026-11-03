// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TripsTable extends Trips with TableInfo<$TripsTable, Trip> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TripsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endReasonMeta = const VerificationMeta(
    'endReason',
  );
  @override
  late final GeneratedColumn<String> endReason = GeneratedColumn<String>(
    'end_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _triggerKindMeta = const VerificationMeta(
    'triggerKind',
  );
  @override
  late final GeneratedColumn<String> triggerKind = GeneratedColumn<String>(
    'trigger_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  @override
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
    'distance_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _movingSMeta = const VerificationMeta(
    'movingS',
  );
  @override
  late final GeneratedColumn<double> movingS = GeneratedColumn<double>(
    'moving_s',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isPassengerMeta = const VerificationMeta(
    'isPassenger',
  );
  @override
  late final GeneratedColumn<bool> isPassenger = GeneratedColumn<bool>(
    'is_passenger',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_passenger" IN (0, 1))',
    ),
  );
  static const VerificationMeta _passengerHintMeta = const VerificationMeta(
    'passengerHint',
  );
  @override
  late final GeneratedColumn<bool> passengerHint = GeneratedColumn<bool>(
    'passenger_hint',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("passenger_hint" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _passengerAnsweredMeta = const VerificationMeta(
    'passengerAnswered',
  );
  @override
  late final GeneratedColumn<bool> passengerAnswered = GeneratedColumn<bool>(
    'passenger_answered',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("passenger_answered" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _vehicleLabelMeta = const VerificationMeta(
    'vehicleLabel',
  );
  @override
  late final GeneratedColumn<String> vehicleLabel = GeneratedColumn<String>(
    'vehicle_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packRegionMeta = const VerificationMeta(
    'packRegion',
  );
  @override
  late final GeneratedColumn<String> packRegion = GeneratedColumn<String>(
    'pack_region',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packVersionMeta = const VerificationMeta(
    'packVersion',
  );
  @override
  late final GeneratedColumn<String> packVersion = GeneratedColumn<String>(
    'pack_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _limitCoverageMeta = const VerificationMeta(
    'limitCoverage',
  );
  @override
  late final GeneratedColumn<double> limitCoverage = GeneratedColumn<double>(
    'limit_coverage',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nightFractionMeta = const VerificationMeta(
    'nightFraction',
  );
  @override
  late final GeneratedColumn<double> nightFraction = GeneratedColumn<double>(
    'night_fraction',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weatherMeta = const VerificationMeta(
    'weather',
  );
  @override
  late final GeneratedColumn<String> weather = GeneratedColumn<String>(
    'weather',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startedAt,
    endedAt,
    phase,
    endReason,
    triggerKind,
    distanceM,
    movingS,
    isPassenger,
    passengerHint,
    passengerAnswered,
    vehicleLabel,
    packRegion,
    packVersion,
    limitCoverage,
    nightFraction,
    weather,
    createdAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trips';
  @override
  VerificationContext validateIntegrity(
    Insertable<Trip> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('end_reason')) {
      context.handle(
        _endReasonMeta,
        endReason.isAcceptableOrUnknown(data['end_reason']!, _endReasonMeta),
      );
    }
    if (data.containsKey('trigger_kind')) {
      context.handle(
        _triggerKindMeta,
        triggerKind.isAcceptableOrUnknown(
          data['trigger_kind']!,
          _triggerKindMeta,
        ),
      );
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    }
    if (data.containsKey('moving_s')) {
      context.handle(
        _movingSMeta,
        movingS.isAcceptableOrUnknown(data['moving_s']!, _movingSMeta),
      );
    }
    if (data.containsKey('is_passenger')) {
      context.handle(
        _isPassengerMeta,
        isPassenger.isAcceptableOrUnknown(
          data['is_passenger']!,
          _isPassengerMeta,
        ),
      );
    }
    if (data.containsKey('passenger_hint')) {
      context.handle(
        _passengerHintMeta,
        passengerHint.isAcceptableOrUnknown(
          data['passenger_hint']!,
          _passengerHintMeta,
        ),
      );
    }
    if (data.containsKey('passenger_answered')) {
      context.handle(
        _passengerAnsweredMeta,
        passengerAnswered.isAcceptableOrUnknown(
          data['passenger_answered']!,
          _passengerAnsweredMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_label')) {
      context.handle(
        _vehicleLabelMeta,
        vehicleLabel.isAcceptableOrUnknown(
          data['vehicle_label']!,
          _vehicleLabelMeta,
        ),
      );
    }
    if (data.containsKey('pack_region')) {
      context.handle(
        _packRegionMeta,
        packRegion.isAcceptableOrUnknown(data['pack_region']!, _packRegionMeta),
      );
    }
    if (data.containsKey('pack_version')) {
      context.handle(
        _packVersionMeta,
        packVersion.isAcceptableOrUnknown(
          data['pack_version']!,
          _packVersionMeta,
        ),
      );
    }
    if (data.containsKey('limit_coverage')) {
      context.handle(
        _limitCoverageMeta,
        limitCoverage.isAcceptableOrUnknown(
          data['limit_coverage']!,
          _limitCoverageMeta,
        ),
      );
    }
    if (data.containsKey('night_fraction')) {
      context.handle(
        _nightFractionMeta,
        nightFraction.isAcceptableOrUnknown(
          data['night_fraction']!,
          _nightFractionMeta,
        ),
      );
    }
    if (data.containsKey('weather')) {
      context.handle(
        _weatherMeta,
        weather.isAcceptableOrUnknown(data['weather']!, _weatherMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Trip map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Trip(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      ),
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      endReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_reason'],
      ),
      triggerKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_kind'],
      ),
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_m'],
      )!,
      movingS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}moving_s'],
      )!,
      isPassenger: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_passenger'],
      ),
      passengerHint: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}passenger_hint'],
      )!,
      passengerAnswered: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}passenger_answered'],
      )!,
      vehicleLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_label'],
      ),
      packRegion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_region'],
      ),
      packVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_version'],
      ),
      limitCoverage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}limit_coverage'],
      ),
      nightFraction: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}night_fraction'],
      ),
      weather: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weather'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $TripsTable createAlias(String alias) {
    return $TripsTable(attachedDatabase, alias);
  }
}

class Trip extends DataClass implements Insertable<Trip> {
  /// UUID generated by the native plugin (or the simulator).
  final String id;

  /// Epoch ms of the first confirmed fix (or the tentative trigger until then).
  final int startedAt;
  final int? endedAt;

  /// recording | pendingPassenger | scored | unscored | discarded
  final String phase;

  /// stationary | exit | manual
  final String? endReason;

  /// activity | bluetooth | geofence | significantChange | manual | simulated
  final String? triggerKind;
  final double distanceM;
  final double movingS;

  /// Null until the trip has been finalised once.
  final bool? isPassenger;

  /// Pre-answer for the passenger interstitial, from native hints.
  final bool passengerHint;

  /// True once the user has confirmed or changed the passenger answer.
  final bool passengerAnswered;

  /// Bluetooth / CarPlay / Android Auto name seen during the trip.
  final String? vehicleLabel;
  final String? packRegion;
  final String? packVersion;
  final double? limitCoverage;
  final double? nightFraction;

  /// clear | rain | snow
  final String? weather;
  final int createdAt;

  /// Soft delete: hidden everywhere, purged with the samples.
  final int? deletedAt;
  const Trip({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.phase,
    this.endReason,
    this.triggerKind,
    required this.distanceM,
    required this.movingS,
    this.isPassenger,
    required this.passengerHint,
    required this.passengerAnswered,
    this.vehicleLabel,
    this.packRegion,
    this.packVersion,
    this.limitCoverage,
    this.nightFraction,
    this.weather,
    required this.createdAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(endedAt);
    }
    map['phase'] = Variable<String>(phase);
    if (!nullToAbsent || endReason != null) {
      map['end_reason'] = Variable<String>(endReason);
    }
    if (!nullToAbsent || triggerKind != null) {
      map['trigger_kind'] = Variable<String>(triggerKind);
    }
    map['distance_m'] = Variable<double>(distanceM);
    map['moving_s'] = Variable<double>(movingS);
    if (!nullToAbsent || isPassenger != null) {
      map['is_passenger'] = Variable<bool>(isPassenger);
    }
    map['passenger_hint'] = Variable<bool>(passengerHint);
    map['passenger_answered'] = Variable<bool>(passengerAnswered);
    if (!nullToAbsent || vehicleLabel != null) {
      map['vehicle_label'] = Variable<String>(vehicleLabel);
    }
    if (!nullToAbsent || packRegion != null) {
      map['pack_region'] = Variable<String>(packRegion);
    }
    if (!nullToAbsent || packVersion != null) {
      map['pack_version'] = Variable<String>(packVersion);
    }
    if (!nullToAbsent || limitCoverage != null) {
      map['limit_coverage'] = Variable<double>(limitCoverage);
    }
    if (!nullToAbsent || nightFraction != null) {
      map['night_fraction'] = Variable<double>(nightFraction);
    }
    if (!nullToAbsent || weather != null) {
      map['weather'] = Variable<String>(weather);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  TripsCompanion toCompanion(bool nullToAbsent) {
    return TripsCompanion(
      id: Value(id),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      phase: Value(phase),
      endReason: endReason == null && nullToAbsent
          ? const Value.absent()
          : Value(endReason),
      triggerKind: triggerKind == null && nullToAbsent
          ? const Value.absent()
          : Value(triggerKind),
      distanceM: Value(distanceM),
      movingS: Value(movingS),
      isPassenger: isPassenger == null && nullToAbsent
          ? const Value.absent()
          : Value(isPassenger),
      passengerHint: Value(passengerHint),
      passengerAnswered: Value(passengerAnswered),
      vehicleLabel: vehicleLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleLabel),
      packRegion: packRegion == null && nullToAbsent
          ? const Value.absent()
          : Value(packRegion),
      packVersion: packVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(packVersion),
      limitCoverage: limitCoverage == null && nullToAbsent
          ? const Value.absent()
          : Value(limitCoverage),
      nightFraction: nightFraction == null && nullToAbsent
          ? const Value.absent()
          : Value(nightFraction),
      weather: weather == null && nullToAbsent
          ? const Value.absent()
          : Value(weather),
      createdAt: Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Trip.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Trip(
      id: serializer.fromJson<String>(json['id']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      endedAt: serializer.fromJson<int?>(json['endedAt']),
      phase: serializer.fromJson<String>(json['phase']),
      endReason: serializer.fromJson<String?>(json['endReason']),
      triggerKind: serializer.fromJson<String?>(json['triggerKind']),
      distanceM: serializer.fromJson<double>(json['distanceM']),
      movingS: serializer.fromJson<double>(json['movingS']),
      isPassenger: serializer.fromJson<bool?>(json['isPassenger']),
      passengerHint: serializer.fromJson<bool>(json['passengerHint']),
      passengerAnswered: serializer.fromJson<bool>(json['passengerAnswered']),
      vehicleLabel: serializer.fromJson<String?>(json['vehicleLabel']),
      packRegion: serializer.fromJson<String?>(json['packRegion']),
      packVersion: serializer.fromJson<String?>(json['packVersion']),
      limitCoverage: serializer.fromJson<double?>(json['limitCoverage']),
      nightFraction: serializer.fromJson<double?>(json['nightFraction']),
      weather: serializer.fromJson<String?>(json['weather']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'startedAt': serializer.toJson<int>(startedAt),
      'endedAt': serializer.toJson<int?>(endedAt),
      'phase': serializer.toJson<String>(phase),
      'endReason': serializer.toJson<String?>(endReason),
      'triggerKind': serializer.toJson<String?>(triggerKind),
      'distanceM': serializer.toJson<double>(distanceM),
      'movingS': serializer.toJson<double>(movingS),
      'isPassenger': serializer.toJson<bool?>(isPassenger),
      'passengerHint': serializer.toJson<bool>(passengerHint),
      'passengerAnswered': serializer.toJson<bool>(passengerAnswered),
      'vehicleLabel': serializer.toJson<String?>(vehicleLabel),
      'packRegion': serializer.toJson<String?>(packRegion),
      'packVersion': serializer.toJson<String?>(packVersion),
      'limitCoverage': serializer.toJson<double?>(limitCoverage),
      'nightFraction': serializer.toJson<double?>(nightFraction),
      'weather': serializer.toJson<String?>(weather),
      'createdAt': serializer.toJson<int>(createdAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  Trip copyWith({
    String? id,
    int? startedAt,
    Value<int?> endedAt = const Value.absent(),
    String? phase,
    Value<String?> endReason = const Value.absent(),
    Value<String?> triggerKind = const Value.absent(),
    double? distanceM,
    double? movingS,
    Value<bool?> isPassenger = const Value.absent(),
    bool? passengerHint,
    bool? passengerAnswered,
    Value<String?> vehicleLabel = const Value.absent(),
    Value<String?> packRegion = const Value.absent(),
    Value<String?> packVersion = const Value.absent(),
    Value<double?> limitCoverage = const Value.absent(),
    Value<double?> nightFraction = const Value.absent(),
    Value<String?> weather = const Value.absent(),
    int? createdAt,
    Value<int?> deletedAt = const Value.absent(),
  }) => Trip(
    id: id ?? this.id,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    phase: phase ?? this.phase,
    endReason: endReason.present ? endReason.value : this.endReason,
    triggerKind: triggerKind.present ? triggerKind.value : this.triggerKind,
    distanceM: distanceM ?? this.distanceM,
    movingS: movingS ?? this.movingS,
    isPassenger: isPassenger.present ? isPassenger.value : this.isPassenger,
    passengerHint: passengerHint ?? this.passengerHint,
    passengerAnswered: passengerAnswered ?? this.passengerAnswered,
    vehicleLabel: vehicleLabel.present ? vehicleLabel.value : this.vehicleLabel,
    packRegion: packRegion.present ? packRegion.value : this.packRegion,
    packVersion: packVersion.present ? packVersion.value : this.packVersion,
    limitCoverage: limitCoverage.present
        ? limitCoverage.value
        : this.limitCoverage,
    nightFraction: nightFraction.present
        ? nightFraction.value
        : this.nightFraction,
    weather: weather.present ? weather.value : this.weather,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Trip copyWithCompanion(TripsCompanion data) {
    return Trip(
      id: data.id.present ? data.id.value : this.id,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      phase: data.phase.present ? data.phase.value : this.phase,
      endReason: data.endReason.present ? data.endReason.value : this.endReason,
      triggerKind: data.triggerKind.present
          ? data.triggerKind.value
          : this.triggerKind,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
      movingS: data.movingS.present ? data.movingS.value : this.movingS,
      isPassenger: data.isPassenger.present
          ? data.isPassenger.value
          : this.isPassenger,
      passengerHint: data.passengerHint.present
          ? data.passengerHint.value
          : this.passengerHint,
      passengerAnswered: data.passengerAnswered.present
          ? data.passengerAnswered.value
          : this.passengerAnswered,
      vehicleLabel: data.vehicleLabel.present
          ? data.vehicleLabel.value
          : this.vehicleLabel,
      packRegion: data.packRegion.present
          ? data.packRegion.value
          : this.packRegion,
      packVersion: data.packVersion.present
          ? data.packVersion.value
          : this.packVersion,
      limitCoverage: data.limitCoverage.present
          ? data.limitCoverage.value
          : this.limitCoverage,
      nightFraction: data.nightFraction.present
          ? data.nightFraction.value
          : this.nightFraction,
      weather: data.weather.present ? data.weather.value : this.weather,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Trip(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('phase: $phase, ')
          ..write('endReason: $endReason, ')
          ..write('triggerKind: $triggerKind, ')
          ..write('distanceM: $distanceM, ')
          ..write('movingS: $movingS, ')
          ..write('isPassenger: $isPassenger, ')
          ..write('passengerHint: $passengerHint, ')
          ..write('passengerAnswered: $passengerAnswered, ')
          ..write('vehicleLabel: $vehicleLabel, ')
          ..write('packRegion: $packRegion, ')
          ..write('packVersion: $packVersion, ')
          ..write('limitCoverage: $limitCoverage, ')
          ..write('nightFraction: $nightFraction, ')
          ..write('weather: $weather, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    startedAt,
    endedAt,
    phase,
    endReason,
    triggerKind,
    distanceM,
    movingS,
    isPassenger,
    passengerHint,
    passengerAnswered,
    vehicleLabel,
    packRegion,
    packVersion,
    limitCoverage,
    nightFraction,
    weather,
    createdAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Trip &&
          other.id == this.id &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.phase == this.phase &&
          other.endReason == this.endReason &&
          other.triggerKind == this.triggerKind &&
          other.distanceM == this.distanceM &&
          other.movingS == this.movingS &&
          other.isPassenger == this.isPassenger &&
          other.passengerHint == this.passengerHint &&
          other.passengerAnswered == this.passengerAnswered &&
          other.vehicleLabel == this.vehicleLabel &&
          other.packRegion == this.packRegion &&
          other.packVersion == this.packVersion &&
          other.limitCoverage == this.limitCoverage &&
          other.nightFraction == this.nightFraction &&
          other.weather == this.weather &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt);
}

class TripsCompanion extends UpdateCompanion<Trip> {
  final Value<String> id;
  final Value<int> startedAt;
  final Value<int?> endedAt;
  final Value<String> phase;
  final Value<String?> endReason;
  final Value<String?> triggerKind;
  final Value<double> distanceM;
  final Value<double> movingS;
  final Value<bool?> isPassenger;
  final Value<bool> passengerHint;
  final Value<bool> passengerAnswered;
  final Value<String?> vehicleLabel;
  final Value<String?> packRegion;
  final Value<String?> packVersion;
  final Value<double?> limitCoverage;
  final Value<double?> nightFraction;
  final Value<String?> weather;
  final Value<int> createdAt;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const TripsCompanion({
    this.id = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.phase = const Value.absent(),
    this.endReason = const Value.absent(),
    this.triggerKind = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.movingS = const Value.absent(),
    this.isPassenger = const Value.absent(),
    this.passengerHint = const Value.absent(),
    this.passengerAnswered = const Value.absent(),
    this.vehicleLabel = const Value.absent(),
    this.packRegion = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.limitCoverage = const Value.absent(),
    this.nightFraction = const Value.absent(),
    this.weather = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TripsCompanion.insert({
    required String id,
    required int startedAt,
    this.endedAt = const Value.absent(),
    required String phase,
    this.endReason = const Value.absent(),
    this.triggerKind = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.movingS = const Value.absent(),
    this.isPassenger = const Value.absent(),
    this.passengerHint = const Value.absent(),
    this.passengerAnswered = const Value.absent(),
    this.vehicleLabel = const Value.absent(),
    this.packRegion = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.limitCoverage = const Value.absent(),
    this.nightFraction = const Value.absent(),
    this.weather = const Value.absent(),
    required int createdAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startedAt = Value(startedAt),
       phase = Value(phase),
       createdAt = Value(createdAt);
  static Insertable<Trip> custom({
    Expression<String>? id,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<String>? phase,
    Expression<String>? endReason,
    Expression<String>? triggerKind,
    Expression<double>? distanceM,
    Expression<double>? movingS,
    Expression<bool>? isPassenger,
    Expression<bool>? passengerHint,
    Expression<bool>? passengerAnswered,
    Expression<String>? vehicleLabel,
    Expression<String>? packRegion,
    Expression<String>? packVersion,
    Expression<double>? limitCoverage,
    Expression<double>? nightFraction,
    Expression<String>? weather,
    Expression<int>? createdAt,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (phase != null) 'phase': phase,
      if (endReason != null) 'end_reason': endReason,
      if (triggerKind != null) 'trigger_kind': triggerKind,
      if (distanceM != null) 'distance_m': distanceM,
      if (movingS != null) 'moving_s': movingS,
      if (isPassenger != null) 'is_passenger': isPassenger,
      if (passengerHint != null) 'passenger_hint': passengerHint,
      if (passengerAnswered != null) 'passenger_answered': passengerAnswered,
      if (vehicleLabel != null) 'vehicle_label': vehicleLabel,
      if (packRegion != null) 'pack_region': packRegion,
      if (packVersion != null) 'pack_version': packVersion,
      if (limitCoverage != null) 'limit_coverage': limitCoverage,
      if (nightFraction != null) 'night_fraction': nightFraction,
      if (weather != null) 'weather': weather,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TripsCompanion copyWith({
    Value<String>? id,
    Value<int>? startedAt,
    Value<int?>? endedAt,
    Value<String>? phase,
    Value<String?>? endReason,
    Value<String?>? triggerKind,
    Value<double>? distanceM,
    Value<double>? movingS,
    Value<bool?>? isPassenger,
    Value<bool>? passengerHint,
    Value<bool>? passengerAnswered,
    Value<String?>? vehicleLabel,
    Value<String?>? packRegion,
    Value<String?>? packVersion,
    Value<double?>? limitCoverage,
    Value<double?>? nightFraction,
    Value<String?>? weather,
    Value<int>? createdAt,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return TripsCompanion(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      phase: phase ?? this.phase,
      endReason: endReason ?? this.endReason,
      triggerKind: triggerKind ?? this.triggerKind,
      distanceM: distanceM ?? this.distanceM,
      movingS: movingS ?? this.movingS,
      isPassenger: isPassenger ?? this.isPassenger,
      passengerHint: passengerHint ?? this.passengerHint,
      passengerAnswered: passengerAnswered ?? this.passengerAnswered,
      vehicleLabel: vehicleLabel ?? this.vehicleLabel,
      packRegion: packRegion ?? this.packRegion,
      packVersion: packVersion ?? this.packVersion,
      limitCoverage: limitCoverage ?? this.limitCoverage,
      nightFraction: nightFraction ?? this.nightFraction,
      weather: weather ?? this.weather,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (endReason.present) {
      map['end_reason'] = Variable<String>(endReason.value);
    }
    if (triggerKind.present) {
      map['trigger_kind'] = Variable<String>(triggerKind.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (movingS.present) {
      map['moving_s'] = Variable<double>(movingS.value);
    }
    if (isPassenger.present) {
      map['is_passenger'] = Variable<bool>(isPassenger.value);
    }
    if (passengerHint.present) {
      map['passenger_hint'] = Variable<bool>(passengerHint.value);
    }
    if (passengerAnswered.present) {
      map['passenger_answered'] = Variable<bool>(passengerAnswered.value);
    }
    if (vehicleLabel.present) {
      map['vehicle_label'] = Variable<String>(vehicleLabel.value);
    }
    if (packRegion.present) {
      map['pack_region'] = Variable<String>(packRegion.value);
    }
    if (packVersion.present) {
      map['pack_version'] = Variable<String>(packVersion.value);
    }
    if (limitCoverage.present) {
      map['limit_coverage'] = Variable<double>(limitCoverage.value);
    }
    if (nightFraction.present) {
      map['night_fraction'] = Variable<double>(nightFraction.value);
    }
    if (weather.present) {
      map['weather'] = Variable<String>(weather.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TripsCompanion(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('phase: $phase, ')
          ..write('endReason: $endReason, ')
          ..write('triggerKind: $triggerKind, ')
          ..write('distanceM: $distanceM, ')
          ..write('movingS: $movingS, ')
          ..write('isPassenger: $isPassenger, ')
          ..write('passengerHint: $passengerHint, ')
          ..write('passengerAnswered: $passengerAnswered, ')
          ..write('vehicleLabel: $vehicleLabel, ')
          ..write('packRegion: $packRegion, ')
          ..write('packVersion: $packVersion, ')
          ..write('limitCoverage: $limitCoverage, ')
          ..write('nightFraction: $nightFraction, ')
          ..write('weather: $weather, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SamplesTable extends Samples with TableInfo<$SamplesTable, Sample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tMeta = const VerificationMeta('t');
  @override
  late final GeneratedColumn<int> t = GeneratedColumn<int>(
    't',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  @override
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
    'accuracy',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _headingMeta = const VerificationMeta(
    'heading',
  );
  @override
  late final GeneratedColumn<double> heading = GeneratedColumn<double>(
    'heading',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _altitudeMeta = const VerificationMeta(
    'altitude',
  );
  @override
  late final GeneratedColumn<double> altitude = GeneratedColumn<double>(
    'altitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tripId,
    t,
    lat,
    lon,
    speed,
    accuracy,
    heading,
    altitude,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<Sample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('t')) {
      context.handle(_tMeta, t.isAcceptableOrUnknown(data['t']!, _tMeta));
    } else if (isInserting) {
      context.missing(_tMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    } else if (isInserting) {
      context.missing(_accuracyMeta);
    }
    if (data.containsKey('heading')) {
      context.handle(
        _headingMeta,
        heading.isAcceptableOrUnknown(data['heading']!, _headingMeta),
      );
    }
    if (data.containsKey('altitude')) {
      context.handle(
        _altitudeMeta,
        altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, t};
  @override
  Sample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sample(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      t: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}t'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      ),
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy'],
      )!,
      heading: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}heading'],
      ),
      altitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude'],
      ),
    );
  }

  @override
  $SamplesTable createAlias(String alias) {
    return $SamplesTable(attachedDatabase, alias);
  }
}

class Sample extends DataClass implements Insertable<Sample> {
  final String tripId;
  final int t;
  final double lat;
  final double lon;
  final double? speed;
  final double accuracy;
  final double? heading;
  final double? altitude;
  const Sample({
    required this.tripId,
    required this.t,
    required this.lat,
    required this.lon,
    this.speed,
    required this.accuracy,
    this.heading,
    this.altitude,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['t'] = Variable<int>(t);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    map['accuracy'] = Variable<double>(accuracy);
    if (!nullToAbsent || heading != null) {
      map['heading'] = Variable<double>(heading);
    }
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<double>(altitude);
    }
    return map;
  }

  SamplesCompanion toCompanion(bool nullToAbsent) {
    return SamplesCompanion(
      tripId: Value(tripId),
      t: Value(t),
      lat: Value(lat),
      lon: Value(lon),
      speed: speed == null && nullToAbsent
          ? const Value.absent()
          : Value(speed),
      accuracy: Value(accuracy),
      heading: heading == null && nullToAbsent
          ? const Value.absent()
          : Value(heading),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
    );
  }

  factory Sample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sample(
      tripId: serializer.fromJson<String>(json['tripId']),
      t: serializer.fromJson<int>(json['t']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      speed: serializer.fromJson<double?>(json['speed']),
      accuracy: serializer.fromJson<double>(json['accuracy']),
      heading: serializer.fromJson<double?>(json['heading']),
      altitude: serializer.fromJson<double?>(json['altitude']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      't': serializer.toJson<int>(t),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'speed': serializer.toJson<double?>(speed),
      'accuracy': serializer.toJson<double>(accuracy),
      'heading': serializer.toJson<double?>(heading),
      'altitude': serializer.toJson<double?>(altitude),
    };
  }

  Sample copyWith({
    String? tripId,
    int? t,
    double? lat,
    double? lon,
    Value<double?> speed = const Value.absent(),
    double? accuracy,
    Value<double?> heading = const Value.absent(),
    Value<double?> altitude = const Value.absent(),
  }) => Sample(
    tripId: tripId ?? this.tripId,
    t: t ?? this.t,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    speed: speed.present ? speed.value : this.speed,
    accuracy: accuracy ?? this.accuracy,
    heading: heading.present ? heading.value : this.heading,
    altitude: altitude.present ? altitude.value : this.altitude,
  );
  Sample copyWithCompanion(SamplesCompanion data) {
    return Sample(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      t: data.t.present ? data.t.value : this.t,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      speed: data.speed.present ? data.speed.value : this.speed,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      heading: data.heading.present ? data.heading.value : this.heading,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sample(')
          ..write('tripId: $tripId, ')
          ..write('t: $t, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('speed: $speed, ')
          ..write('accuracy: $accuracy, ')
          ..write('heading: $heading, ')
          ..write('altitude: $altitude')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(tripId, t, lat, lon, speed, accuracy, heading, altitude);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sample &&
          other.tripId == this.tripId &&
          other.t == this.t &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.speed == this.speed &&
          other.accuracy == this.accuracy &&
          other.heading == this.heading &&
          other.altitude == this.altitude);
}

class SamplesCompanion extends UpdateCompanion<Sample> {
  final Value<String> tripId;
  final Value<int> t;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double?> speed;
  final Value<double> accuracy;
  final Value<double?> heading;
  final Value<double?> altitude;
  final Value<int> rowid;
  const SamplesCompanion({
    this.tripId = const Value.absent(),
    this.t = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.speed = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.heading = const Value.absent(),
    this.altitude = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SamplesCompanion.insert({
    required String tripId,
    required int t,
    required double lat,
    required double lon,
    this.speed = const Value.absent(),
    required double accuracy,
    this.heading = const Value.absent(),
    this.altitude = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       t = Value(t),
       lat = Value(lat),
       lon = Value(lon),
       accuracy = Value(accuracy);
  static Insertable<Sample> custom({
    Expression<String>? tripId,
    Expression<int>? t,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? speed,
    Expression<double>? accuracy,
    Expression<double>? heading,
    Expression<double>? altitude,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (t != null) 't': t,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
      if (heading != null) 'heading': heading,
      if (altitude != null) 'altitude': altitude,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SamplesCompanion copyWith({
    Value<String>? tripId,
    Value<int>? t,
    Value<double>? lat,
    Value<double>? lon,
    Value<double?>? speed,
    Value<double>? accuracy,
    Value<double?>? heading,
    Value<double?>? altitude,
    Value<int>? rowid,
  }) {
    return SamplesCompanion(
      tripId: tripId ?? this.tripId,
      t: t ?? this.t,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      altitude: altitude ?? this.altitude,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (t.present) {
      map['t'] = Variable<int>(t.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (heading.present) {
      map['heading'] = Variable<double>(heading.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<double>(altitude.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SamplesCompanion(')
          ..write('tripId: $tripId, ')
          ..write('t: $t, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('speed: $speed, ')
          ..write('accuracy: $accuracy, ')
          ..write('heading: $heading, ')
          ..write('altitude: $altitude, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MotionPeaksTable extends MotionPeaks
    with TableInfo<$MotionPeaksTable, MotionPeak> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MotionPeaksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tMeta = const VerificationMeta('t');
  @override
  late final GeneratedColumn<int> t = GeneratedColumn<int>(
    't',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peakMeta = const VerificationMeta('peak');
  @override
  late final GeneratedColumn<double> peak = GeneratedColumn<double>(
    'peak',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tripId, t, peak];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'motion_peaks';
  @override
  VerificationContext validateIntegrity(
    Insertable<MotionPeak> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('t')) {
      context.handle(_tMeta, t.isAcceptableOrUnknown(data['t']!, _tMeta));
    } else if (isInserting) {
      context.missing(_tMeta);
    }
    if (data.containsKey('peak')) {
      context.handle(
        _peakMeta,
        peak.isAcceptableOrUnknown(data['peak']!, _peakMeta),
      );
    } else if (isInserting) {
      context.missing(_peakMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, t};
  @override
  MotionPeak map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MotionPeak(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      t: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}t'],
      )!,
      peak: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}peak'],
      )!,
    );
  }

  @override
  $MotionPeaksTable createAlias(String alias) {
    return $MotionPeaksTable(attachedDatabase, alias);
  }
}

class MotionPeak extends DataClass implements Insertable<MotionPeak> {
  final String tripId;
  final int t;
  final double peak;
  const MotionPeak({required this.tripId, required this.t, required this.peak});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['t'] = Variable<int>(t);
    map['peak'] = Variable<double>(peak);
    return map;
  }

  MotionPeaksCompanion toCompanion(bool nullToAbsent) {
    return MotionPeaksCompanion(
      tripId: Value(tripId),
      t: Value(t),
      peak: Value(peak),
    );
  }

  factory MotionPeak.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MotionPeak(
      tripId: serializer.fromJson<String>(json['tripId']),
      t: serializer.fromJson<int>(json['t']),
      peak: serializer.fromJson<double>(json['peak']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      't': serializer.toJson<int>(t),
      'peak': serializer.toJson<double>(peak),
    };
  }

  MotionPeak copyWith({String? tripId, int? t, double? peak}) => MotionPeak(
    tripId: tripId ?? this.tripId,
    t: t ?? this.t,
    peak: peak ?? this.peak,
  );
  MotionPeak copyWithCompanion(MotionPeaksCompanion data) {
    return MotionPeak(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      t: data.t.present ? data.t.value : this.t,
      peak: data.peak.present ? data.peak.value : this.peak,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MotionPeak(')
          ..write('tripId: $tripId, ')
          ..write('t: $t, ')
          ..write('peak: $peak')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tripId, t, peak);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MotionPeak &&
          other.tripId == this.tripId &&
          other.t == this.t &&
          other.peak == this.peak);
}

class MotionPeaksCompanion extends UpdateCompanion<MotionPeak> {
  final Value<String> tripId;
  final Value<int> t;
  final Value<double> peak;
  final Value<int> rowid;
  const MotionPeaksCompanion({
    this.tripId = const Value.absent(),
    this.t = const Value.absent(),
    this.peak = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MotionPeaksCompanion.insert({
    required String tripId,
    required int t,
    required double peak,
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       t = Value(t),
       peak = Value(peak);
  static Insertable<MotionPeak> custom({
    Expression<String>? tripId,
    Expression<int>? t,
    Expression<double>? peak,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (t != null) 't': t,
      if (peak != null) 'peak': peak,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MotionPeaksCompanion copyWith({
    Value<String>? tripId,
    Value<int>? t,
    Value<double>? peak,
    Value<int>? rowid,
  }) {
    return MotionPeaksCompanion(
      tripId: tripId ?? this.tripId,
      t: t ?? this.t,
      peak: peak ?? this.peak,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (t.present) {
      map['t'] = Variable<int>(t.value);
    }
    if (peak.present) {
      map['peak'] = Variable<double>(peak.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MotionPeaksCompanion(')
          ..write('tripId: $tripId, ')
          ..write('t: $t, ')
          ..write('peak: $peak, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhoneEventsTable extends PhoneEvents
    with TableInfo<$PhoneEventsTable, PhoneEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhoneEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tMeta = const VerificationMeta('t');
  @override
  late final GeneratedColumn<int> t = GeneratedColumn<int>(
    't',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tripId, t, kind];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'phone_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<PhoneEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('t')) {
      context.handle(_tMeta, t.isAcceptableOrUnknown(data['t']!, _tMeta));
    } else if (isInserting) {
      context.missing(_tMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, t, kind};
  @override
  PhoneEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PhoneEventRow(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      t: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}t'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
    );
  }

  @override
  $PhoneEventsTable createAlias(String alias) {
    return $PhoneEventsTable(attachedDatabase, alias);
  }
}

class PhoneEventRow extends DataClass implements Insertable<PhoneEventRow> {
  final String tripId;
  final int t;
  final String kind;
  const PhoneEventRow({
    required this.tripId,
    required this.t,
    required this.kind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['t'] = Variable<int>(t);
    map['kind'] = Variable<String>(kind);
    return map;
  }

  PhoneEventsCompanion toCompanion(bool nullToAbsent) {
    return PhoneEventsCompanion(
      tripId: Value(tripId),
      t: Value(t),
      kind: Value(kind),
    );
  }

  factory PhoneEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PhoneEventRow(
      tripId: serializer.fromJson<String>(json['tripId']),
      t: serializer.fromJson<int>(json['t']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      't': serializer.toJson<int>(t),
      'kind': serializer.toJson<String>(kind),
    };
  }

  PhoneEventRow copyWith({String? tripId, int? t, String? kind}) =>
      PhoneEventRow(
        tripId: tripId ?? this.tripId,
        t: t ?? this.t,
        kind: kind ?? this.kind,
      );
  PhoneEventRow copyWithCompanion(PhoneEventsCompanion data) {
    return PhoneEventRow(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      t: data.t.present ? data.t.value : this.t,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhoneEventRow(')
          ..write('tripId: $tripId, ')
          ..write('t: $t, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tripId, t, kind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhoneEventRow &&
          other.tripId == this.tripId &&
          other.t == this.t &&
          other.kind == this.kind);
}

class PhoneEventsCompanion extends UpdateCompanion<PhoneEventRow> {
  final Value<String> tripId;
  final Value<int> t;
  final Value<String> kind;
  final Value<int> rowid;
  const PhoneEventsCompanion({
    this.tripId = const Value.absent(),
    this.t = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhoneEventsCompanion.insert({
    required String tripId,
    required int t,
    required String kind,
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       t = Value(t),
       kind = Value(kind);
  static Insertable<PhoneEventRow> custom({
    Expression<String>? tripId,
    Expression<int>? t,
    Expression<String>? kind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (t != null) 't': t,
      if (kind != null) 'kind': kind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhoneEventsCompanion copyWith({
    Value<String>? tripId,
    Value<int>? t,
    Value<String>? kind,
    Value<int>? rowid,
  }) {
    return PhoneEventsCompanion(
      tripId: tripId ?? this.tripId,
      t: t ?? this.t,
      kind: kind ?? this.kind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (t.present) {
      map['t'] = Variable<int>(t.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhoneEventsCompanion(')
          ..write('tripId: $tripId, ')
          ..write('t: $t, ')
          ..write('kind: $kind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SegmentsTable extends Segments with TableInfo<$SegmentsTable, Segment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SegmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromIdxMeta = const VerificationMeta(
    'fromIdx',
  );
  @override
  late final GeneratedColumn<int> fromIdx = GeneratedColumn<int>(
    'from_idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toIdxMeta = const VerificationMeta('toIdx');
  @override
  late final GeneratedColumn<int> toIdx = GeneratedColumn<int>(
    'to_idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedLimitMpsMeta = const VerificationMeta(
    'speedLimitMps',
  );
  @override
  late final GeneratedColumn<double> speedLimitMps = GeneratedColumn<double>(
    'speed_limit_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roadClassMeta = const VerificationMeta(
    'roadClass',
  );
  @override
  late final GeneratedColumn<String> roadClass = GeneratedColumn<String>(
    'road_class',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wayIdMeta = const VerificationMeta('wayId');
  @override
  late final GeneratedColumn<String> wayId = GeneratedColumn<String>(
    'way_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tripId,
    fromIdx,
    toIdx,
    speedLimitMps,
    confidence,
    roadClass,
    name,
    wayId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'segments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Segment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('from_idx')) {
      context.handle(
        _fromIdxMeta,
        fromIdx.isAcceptableOrUnknown(data['from_idx']!, _fromIdxMeta),
      );
    } else if (isInserting) {
      context.missing(_fromIdxMeta);
    }
    if (data.containsKey('to_idx')) {
      context.handle(
        _toIdxMeta,
        toIdx.isAcceptableOrUnknown(data['to_idx']!, _toIdxMeta),
      );
    } else if (isInserting) {
      context.missing(_toIdxMeta);
    }
    if (data.containsKey('speed_limit_mps')) {
      context.handle(
        _speedLimitMpsMeta,
        speedLimitMps.isAcceptableOrUnknown(
          data['speed_limit_mps']!,
          _speedLimitMpsMeta,
        ),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    if (data.containsKey('road_class')) {
      context.handle(
        _roadClassMeta,
        roadClass.isAcceptableOrUnknown(data['road_class']!, _roadClassMeta),
      );
    } else if (isInserting) {
      context.missing(_roadClassMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('way_id')) {
      context.handle(
        _wayIdMeta,
        wayId.isAcceptableOrUnknown(data['way_id']!, _wayIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, fromIdx};
  @override
  Segment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Segment(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      fromIdx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}from_idx'],
      )!,
      toIdx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_idx'],
      )!,
      speedLimitMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_limit_mps'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      roadClass: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}road_class'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      wayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}way_id'],
      ),
    );
  }

  @override
  $SegmentsTable createAlias(String alias) {
    return $SegmentsTable(attachedDatabase, alias);
  }
}

class Segment extends DataClass implements Insertable<Segment> {
  final String tripId;
  final int fromIdx;
  final int toIdx;
  final double? speedLimitMps;
  final double confidence;
  final String roadClass;
  final String? name;
  final String? wayId;
  const Segment({
    required this.tripId,
    required this.fromIdx,
    required this.toIdx,
    this.speedLimitMps,
    required this.confidence,
    required this.roadClass,
    this.name,
    this.wayId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['from_idx'] = Variable<int>(fromIdx);
    map['to_idx'] = Variable<int>(toIdx);
    if (!nullToAbsent || speedLimitMps != null) {
      map['speed_limit_mps'] = Variable<double>(speedLimitMps);
    }
    map['confidence'] = Variable<double>(confidence);
    map['road_class'] = Variable<String>(roadClass);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || wayId != null) {
      map['way_id'] = Variable<String>(wayId);
    }
    return map;
  }

  SegmentsCompanion toCompanion(bool nullToAbsent) {
    return SegmentsCompanion(
      tripId: Value(tripId),
      fromIdx: Value(fromIdx),
      toIdx: Value(toIdx),
      speedLimitMps: speedLimitMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedLimitMps),
      confidence: Value(confidence),
      roadClass: Value(roadClass),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      wayId: wayId == null && nullToAbsent
          ? const Value.absent()
          : Value(wayId),
    );
  }

  factory Segment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Segment(
      tripId: serializer.fromJson<String>(json['tripId']),
      fromIdx: serializer.fromJson<int>(json['fromIdx']),
      toIdx: serializer.fromJson<int>(json['toIdx']),
      speedLimitMps: serializer.fromJson<double?>(json['speedLimitMps']),
      confidence: serializer.fromJson<double>(json['confidence']),
      roadClass: serializer.fromJson<String>(json['roadClass']),
      name: serializer.fromJson<String?>(json['name']),
      wayId: serializer.fromJson<String?>(json['wayId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'fromIdx': serializer.toJson<int>(fromIdx),
      'toIdx': serializer.toJson<int>(toIdx),
      'speedLimitMps': serializer.toJson<double?>(speedLimitMps),
      'confidence': serializer.toJson<double>(confidence),
      'roadClass': serializer.toJson<String>(roadClass),
      'name': serializer.toJson<String?>(name),
      'wayId': serializer.toJson<String?>(wayId),
    };
  }

  Segment copyWith({
    String? tripId,
    int? fromIdx,
    int? toIdx,
    Value<double?> speedLimitMps = const Value.absent(),
    double? confidence,
    String? roadClass,
    Value<String?> name = const Value.absent(),
    Value<String?> wayId = const Value.absent(),
  }) => Segment(
    tripId: tripId ?? this.tripId,
    fromIdx: fromIdx ?? this.fromIdx,
    toIdx: toIdx ?? this.toIdx,
    speedLimitMps: speedLimitMps.present
        ? speedLimitMps.value
        : this.speedLimitMps,
    confidence: confidence ?? this.confidence,
    roadClass: roadClass ?? this.roadClass,
    name: name.present ? name.value : this.name,
    wayId: wayId.present ? wayId.value : this.wayId,
  );
  Segment copyWithCompanion(SegmentsCompanion data) {
    return Segment(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      fromIdx: data.fromIdx.present ? data.fromIdx.value : this.fromIdx,
      toIdx: data.toIdx.present ? data.toIdx.value : this.toIdx,
      speedLimitMps: data.speedLimitMps.present
          ? data.speedLimitMps.value
          : this.speedLimitMps,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      roadClass: data.roadClass.present ? data.roadClass.value : this.roadClass,
      name: data.name.present ? data.name.value : this.name,
      wayId: data.wayId.present ? data.wayId.value : this.wayId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Segment(')
          ..write('tripId: $tripId, ')
          ..write('fromIdx: $fromIdx, ')
          ..write('toIdx: $toIdx, ')
          ..write('speedLimitMps: $speedLimitMps, ')
          ..write('confidence: $confidence, ')
          ..write('roadClass: $roadClass, ')
          ..write('name: $name, ')
          ..write('wayId: $wayId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tripId,
    fromIdx,
    toIdx,
    speedLimitMps,
    confidence,
    roadClass,
    name,
    wayId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Segment &&
          other.tripId == this.tripId &&
          other.fromIdx == this.fromIdx &&
          other.toIdx == this.toIdx &&
          other.speedLimitMps == this.speedLimitMps &&
          other.confidence == this.confidence &&
          other.roadClass == this.roadClass &&
          other.name == this.name &&
          other.wayId == this.wayId);
}

class SegmentsCompanion extends UpdateCompanion<Segment> {
  final Value<String> tripId;
  final Value<int> fromIdx;
  final Value<int> toIdx;
  final Value<double?> speedLimitMps;
  final Value<double> confidence;
  final Value<String> roadClass;
  final Value<String?> name;
  final Value<String?> wayId;
  final Value<int> rowid;
  const SegmentsCompanion({
    this.tripId = const Value.absent(),
    this.fromIdx = const Value.absent(),
    this.toIdx = const Value.absent(),
    this.speedLimitMps = const Value.absent(),
    this.confidence = const Value.absent(),
    this.roadClass = const Value.absent(),
    this.name = const Value.absent(),
    this.wayId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SegmentsCompanion.insert({
    required String tripId,
    required int fromIdx,
    required int toIdx,
    this.speedLimitMps = const Value.absent(),
    required double confidence,
    required String roadClass,
    this.name = const Value.absent(),
    this.wayId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       fromIdx = Value(fromIdx),
       toIdx = Value(toIdx),
       confidence = Value(confidence),
       roadClass = Value(roadClass);
  static Insertable<Segment> custom({
    Expression<String>? tripId,
    Expression<int>? fromIdx,
    Expression<int>? toIdx,
    Expression<double>? speedLimitMps,
    Expression<double>? confidence,
    Expression<String>? roadClass,
    Expression<String>? name,
    Expression<String>? wayId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (fromIdx != null) 'from_idx': fromIdx,
      if (toIdx != null) 'to_idx': toIdx,
      if (speedLimitMps != null) 'speed_limit_mps': speedLimitMps,
      if (confidence != null) 'confidence': confidence,
      if (roadClass != null) 'road_class': roadClass,
      if (name != null) 'name': name,
      if (wayId != null) 'way_id': wayId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SegmentsCompanion copyWith({
    Value<String>? tripId,
    Value<int>? fromIdx,
    Value<int>? toIdx,
    Value<double?>? speedLimitMps,
    Value<double>? confidence,
    Value<String>? roadClass,
    Value<String?>? name,
    Value<String?>? wayId,
    Value<int>? rowid,
  }) {
    return SegmentsCompanion(
      tripId: tripId ?? this.tripId,
      fromIdx: fromIdx ?? this.fromIdx,
      toIdx: toIdx ?? this.toIdx,
      speedLimitMps: speedLimitMps ?? this.speedLimitMps,
      confidence: confidence ?? this.confidence,
      roadClass: roadClass ?? this.roadClass,
      name: name ?? this.name,
      wayId: wayId ?? this.wayId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (fromIdx.present) {
      map['from_idx'] = Variable<int>(fromIdx.value);
    }
    if (toIdx.present) {
      map['to_idx'] = Variable<int>(toIdx.value);
    }
    if (speedLimitMps.present) {
      map['speed_limit_mps'] = Variable<double>(speedLimitMps.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (roadClass.present) {
      map['road_class'] = Variable<String>(roadClass.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (wayId.present) {
      map['way_id'] = Variable<String>(wayId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SegmentsCompanion(')
          ..write('tripId: $tripId, ')
          ..write('fromIdx: $fromIdx, ')
          ..write('toIdx: $toIdx, ')
          ..write('speedLimitMps: $speedLimitMps, ')
          ..write('confidence: $confidence, ')
          ..write('roadClass: $roadClass, ')
          ..write('name: $name, ')
          ..write('wayId: $wayId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TripScoresTable extends TripScores
    with TableInfo<$TripScoresTable, TripScoreRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TripScoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreJsonMeta = const VerificationMeta(
    'scoreJson',
  );
  @override
  late final GeneratedColumn<String> scoreJson = GeneratedColumn<String>(
    'score_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _xpMeta = const VerificationMeta('xp');
  @override
  late final GeneratedColumn<int> xp = GeneratedColumn<int>(
    'xp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recklessMeta = const VerificationMeta(
    'reckless',
  );
  @override
  late final GeneratedColumn<bool> reckless = GeneratedColumn<bool>(
    'reckless',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reckless" IN (0, 1))',
    ),
  );
  static const VerificationMeta _scoredMeta = const VerificationMeta('scored');
  @override
  late final GeneratedColumn<bool> scored = GeneratedColumn<bool>(
    'scored',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("scored" IN (0, 1))',
    ),
  );
  static const VerificationMeta _roastTextMeta = const VerificationMeta(
    'roastText',
  );
  @override
  late final GeneratedColumn<String> roastText = GeneratedColumn<String>(
    'roast_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scoredAtMeta = const VerificationMeta(
    'scoredAt',
  );
  @override
  late final GeneratedColumn<int> scoredAt = GeneratedColumn<int>(
    'scored_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tripId,
    scoreJson,
    score,
    xp,
    reckless,
    scored,
    roastText,
    scoredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trip_scores';
  @override
  VerificationContext validateIntegrity(
    Insertable<TripScoreRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('score_json')) {
      context.handle(
        _scoreJsonMeta,
        scoreJson.isAcceptableOrUnknown(data['score_json']!, _scoreJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreJsonMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    }
    if (data.containsKey('xp')) {
      context.handle(_xpMeta, xp.isAcceptableOrUnknown(data['xp']!, _xpMeta));
    } else if (isInserting) {
      context.missing(_xpMeta);
    }
    if (data.containsKey('reckless')) {
      context.handle(
        _recklessMeta,
        reckless.isAcceptableOrUnknown(data['reckless']!, _recklessMeta),
      );
    } else if (isInserting) {
      context.missing(_recklessMeta);
    }
    if (data.containsKey('scored')) {
      context.handle(
        _scoredMeta,
        scored.isAcceptableOrUnknown(data['scored']!, _scoredMeta),
      );
    } else if (isInserting) {
      context.missing(_scoredMeta);
    }
    if (data.containsKey('roast_text')) {
      context.handle(
        _roastTextMeta,
        roastText.isAcceptableOrUnknown(data['roast_text']!, _roastTextMeta),
      );
    }
    if (data.containsKey('scored_at')) {
      context.handle(
        _scoredAtMeta,
        scoredAt.isAcceptableOrUnknown(data['scored_at']!, _scoredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_scoredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId};
  @override
  TripScoreRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TripScoreRow(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      scoreJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}score_json'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      ),
      xp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}xp'],
      )!,
      reckless: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reckless'],
      )!,
      scored: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}scored'],
      )!,
      roastText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roast_text'],
      ),
      scoredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scored_at'],
      )!,
    );
  }

  @override
  $TripScoresTable createAlias(String alias) {
    return $TripScoresTable(attachedDatabase, alias);
  }
}

class TripScoreRow extends DataClass implements Insertable<TripScoreRow> {
  final String tripId;
  final String scoreJson;
  final int? score;
  final int xp;
  final bool reckless;
  final bool scored;
  final String? roastText;
  final int scoredAt;
  const TripScoreRow({
    required this.tripId,
    required this.scoreJson,
    this.score,
    required this.xp,
    required this.reckless,
    required this.scored,
    this.roastText,
    required this.scoredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['score_json'] = Variable<String>(scoreJson);
    if (!nullToAbsent || score != null) {
      map['score'] = Variable<int>(score);
    }
    map['xp'] = Variable<int>(xp);
    map['reckless'] = Variable<bool>(reckless);
    map['scored'] = Variable<bool>(scored);
    if (!nullToAbsent || roastText != null) {
      map['roast_text'] = Variable<String>(roastText);
    }
    map['scored_at'] = Variable<int>(scoredAt);
    return map;
  }

  TripScoresCompanion toCompanion(bool nullToAbsent) {
    return TripScoresCompanion(
      tripId: Value(tripId),
      scoreJson: Value(scoreJson),
      score: score == null && nullToAbsent
          ? const Value.absent()
          : Value(score),
      xp: Value(xp),
      reckless: Value(reckless),
      scored: Value(scored),
      roastText: roastText == null && nullToAbsent
          ? const Value.absent()
          : Value(roastText),
      scoredAt: Value(scoredAt),
    );
  }

  factory TripScoreRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TripScoreRow(
      tripId: serializer.fromJson<String>(json['tripId']),
      scoreJson: serializer.fromJson<String>(json['scoreJson']),
      score: serializer.fromJson<int?>(json['score']),
      xp: serializer.fromJson<int>(json['xp']),
      reckless: serializer.fromJson<bool>(json['reckless']),
      scored: serializer.fromJson<bool>(json['scored']),
      roastText: serializer.fromJson<String?>(json['roastText']),
      scoredAt: serializer.fromJson<int>(json['scoredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'scoreJson': serializer.toJson<String>(scoreJson),
      'score': serializer.toJson<int?>(score),
      'xp': serializer.toJson<int>(xp),
      'reckless': serializer.toJson<bool>(reckless),
      'scored': serializer.toJson<bool>(scored),
      'roastText': serializer.toJson<String?>(roastText),
      'scoredAt': serializer.toJson<int>(scoredAt),
    };
  }

  TripScoreRow copyWith({
    String? tripId,
    String? scoreJson,
    Value<int?> score = const Value.absent(),
    int? xp,
    bool? reckless,
    bool? scored,
    Value<String?> roastText = const Value.absent(),
    int? scoredAt,
  }) => TripScoreRow(
    tripId: tripId ?? this.tripId,
    scoreJson: scoreJson ?? this.scoreJson,
    score: score.present ? score.value : this.score,
    xp: xp ?? this.xp,
    reckless: reckless ?? this.reckless,
    scored: scored ?? this.scored,
    roastText: roastText.present ? roastText.value : this.roastText,
    scoredAt: scoredAt ?? this.scoredAt,
  );
  TripScoreRow copyWithCompanion(TripScoresCompanion data) {
    return TripScoreRow(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      scoreJson: data.scoreJson.present ? data.scoreJson.value : this.scoreJson,
      score: data.score.present ? data.score.value : this.score,
      xp: data.xp.present ? data.xp.value : this.xp,
      reckless: data.reckless.present ? data.reckless.value : this.reckless,
      scored: data.scored.present ? data.scored.value : this.scored,
      roastText: data.roastText.present ? data.roastText.value : this.roastText,
      scoredAt: data.scoredAt.present ? data.scoredAt.value : this.scoredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TripScoreRow(')
          ..write('tripId: $tripId, ')
          ..write('scoreJson: $scoreJson, ')
          ..write('score: $score, ')
          ..write('xp: $xp, ')
          ..write('reckless: $reckless, ')
          ..write('scored: $scored, ')
          ..write('roastText: $roastText, ')
          ..write('scoredAt: $scoredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tripId,
    scoreJson,
    score,
    xp,
    reckless,
    scored,
    roastText,
    scoredAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TripScoreRow &&
          other.tripId == this.tripId &&
          other.scoreJson == this.scoreJson &&
          other.score == this.score &&
          other.xp == this.xp &&
          other.reckless == this.reckless &&
          other.scored == this.scored &&
          other.roastText == this.roastText &&
          other.scoredAt == this.scoredAt);
}

class TripScoresCompanion extends UpdateCompanion<TripScoreRow> {
  final Value<String> tripId;
  final Value<String> scoreJson;
  final Value<int?> score;
  final Value<int> xp;
  final Value<bool> reckless;
  final Value<bool> scored;
  final Value<String?> roastText;
  final Value<int> scoredAt;
  final Value<int> rowid;
  const TripScoresCompanion({
    this.tripId = const Value.absent(),
    this.scoreJson = const Value.absent(),
    this.score = const Value.absent(),
    this.xp = const Value.absent(),
    this.reckless = const Value.absent(),
    this.scored = const Value.absent(),
    this.roastText = const Value.absent(),
    this.scoredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TripScoresCompanion.insert({
    required String tripId,
    required String scoreJson,
    this.score = const Value.absent(),
    required int xp,
    required bool reckless,
    required bool scored,
    this.roastText = const Value.absent(),
    required int scoredAt,
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       scoreJson = Value(scoreJson),
       xp = Value(xp),
       reckless = Value(reckless),
       scored = Value(scored),
       scoredAt = Value(scoredAt);
  static Insertable<TripScoreRow> custom({
    Expression<String>? tripId,
    Expression<String>? scoreJson,
    Expression<int>? score,
    Expression<int>? xp,
    Expression<bool>? reckless,
    Expression<bool>? scored,
    Expression<String>? roastText,
    Expression<int>? scoredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (scoreJson != null) 'score_json': scoreJson,
      if (score != null) 'score': score,
      if (xp != null) 'xp': xp,
      if (reckless != null) 'reckless': reckless,
      if (scored != null) 'scored': scored,
      if (roastText != null) 'roast_text': roastText,
      if (scoredAt != null) 'scored_at': scoredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TripScoresCompanion copyWith({
    Value<String>? tripId,
    Value<String>? scoreJson,
    Value<int?>? score,
    Value<int>? xp,
    Value<bool>? reckless,
    Value<bool>? scored,
    Value<String?>? roastText,
    Value<int>? scoredAt,
    Value<int>? rowid,
  }) {
    return TripScoresCompanion(
      tripId: tripId ?? this.tripId,
      scoreJson: scoreJson ?? this.scoreJson,
      score: score ?? this.score,
      xp: xp ?? this.xp,
      reckless: reckless ?? this.reckless,
      scored: scored ?? this.scored,
      roastText: roastText ?? this.roastText,
      scoredAt: scoredAt ?? this.scoredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (scoreJson.present) {
      map['score_json'] = Variable<String>(scoreJson.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (xp.present) {
      map['xp'] = Variable<int>(xp.value);
    }
    if (reckless.present) {
      map['reckless'] = Variable<bool>(reckless.value);
    }
    if (scored.present) {
      map['scored'] = Variable<bool>(scored.value);
    }
    if (roastText.present) {
      map['roast_text'] = Variable<String>(roastText.value);
    }
    if (scoredAt.present) {
      map['scored_at'] = Variable<int>(scoredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TripScoresCompanion(')
          ..write('tripId: $tripId, ')
          ..write('scoreJson: $scoreJson, ')
          ..write('score: $score, ')
          ..write('xp: $xp, ')
          ..write('reckless: $reckless, ')
          ..write('scored: $scored, ')
          ..write('roastText: $roastText, ')
          ..write('scoredAt: $scoredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PacksTable extends Packs with TableInfo<$PacksTable, Pack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PacksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  @override
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _osmTimestampMeta = const VerificationMeta(
    'osmTimestamp',
  );
  @override
  late final GeneratedColumn<String> osmTimestamp = GeneratedColumn<String>(
    'osm_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wayCountMeta = const VerificationMeta(
    'wayCount',
  );
  @override
  late final GeneratedColumn<int> wayCount = GeneratedColumn<int>(
    'way_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxMinLatMeta = const VerificationMeta(
    'bboxMinLat',
  );
  @override
  late final GeneratedColumn<double> bboxMinLat = GeneratedColumn<double>(
    'bbox_min_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxMinLonMeta = const VerificationMeta(
    'bboxMinLon',
  );
  @override
  late final GeneratedColumn<double> bboxMinLon = GeneratedColumn<double>(
    'bbox_min_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxMaxLatMeta = const VerificationMeta(
    'bboxMaxLat',
  );
  @override
  late final GeneratedColumn<double> bboxMaxLat = GeneratedColumn<double>(
    'bbox_max_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxMaxLonMeta = const VerificationMeta(
    'bboxMaxLon',
  );
  @override
  late final GeneratedColumn<double> bboxMaxLon = GeneratedColumn<double>(
    'bbox_max_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<int> installedAt = GeneratedColumn<int>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    region,
    name,
    osmTimestamp,
    path,
    sha256,
    bytes,
    wayCount,
    bboxMinLat,
    bboxMinLon,
    bboxMaxLat,
    bboxMaxLon,
    installedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'packs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Pack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    } else if (isInserting) {
      context.missing(_regionMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('osm_timestamp')) {
      context.handle(
        _osmTimestampMeta,
        osmTimestamp.isAcceptableOrUnknown(
          data['osm_timestamp']!,
          _osmTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_osmTimestampMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('way_count')) {
      context.handle(
        _wayCountMeta,
        wayCount.isAcceptableOrUnknown(data['way_count']!, _wayCountMeta),
      );
    } else if (isInserting) {
      context.missing(_wayCountMeta);
    }
    if (data.containsKey('bbox_min_lat')) {
      context.handle(
        _bboxMinLatMeta,
        bboxMinLat.isAcceptableOrUnknown(
          data['bbox_min_lat']!,
          _bboxMinLatMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bboxMinLatMeta);
    }
    if (data.containsKey('bbox_min_lon')) {
      context.handle(
        _bboxMinLonMeta,
        bboxMinLon.isAcceptableOrUnknown(
          data['bbox_min_lon']!,
          _bboxMinLonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bboxMinLonMeta);
    }
    if (data.containsKey('bbox_max_lat')) {
      context.handle(
        _bboxMaxLatMeta,
        bboxMaxLat.isAcceptableOrUnknown(
          data['bbox_max_lat']!,
          _bboxMaxLatMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bboxMaxLatMeta);
    }
    if (data.containsKey('bbox_max_lon')) {
      context.handle(
        _bboxMaxLonMeta,
        bboxMaxLon.isAcceptableOrUnknown(
          data['bbox_max_lon']!,
          _bboxMaxLonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bboxMaxLonMeta);
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {region};
  @override
  Pack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Pack(
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      osmTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}osm_timestamp'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      )!,
      wayCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}way_count'],
      )!,
      bboxMinLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_min_lat'],
      )!,
      bboxMinLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_min_lon'],
      )!,
      bboxMaxLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_max_lat'],
      )!,
      bboxMaxLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_max_lon'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}installed_at'],
      )!,
    );
  }

  @override
  $PacksTable createAlias(String alias) {
    return $PacksTable(attachedDatabase, alias);
  }
}

class Pack extends DataClass implements Insertable<Pack> {
  final String region;
  final String name;
  final String osmTimestamp;
  final String path;
  final String sha256;
  final int bytes;
  final int wayCount;
  final double bboxMinLat;
  final double bboxMinLon;
  final double bboxMaxLat;
  final double bboxMaxLon;
  final int installedAt;
  const Pack({
    required this.region,
    required this.name,
    required this.osmTimestamp,
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.wayCount,
    required this.bboxMinLat,
    required this.bboxMinLon,
    required this.bboxMaxLat,
    required this.bboxMaxLon,
    required this.installedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['region'] = Variable<String>(region);
    map['name'] = Variable<String>(name);
    map['osm_timestamp'] = Variable<String>(osmTimestamp);
    map['path'] = Variable<String>(path);
    map['sha256'] = Variable<String>(sha256);
    map['bytes'] = Variable<int>(bytes);
    map['way_count'] = Variable<int>(wayCount);
    map['bbox_min_lat'] = Variable<double>(bboxMinLat);
    map['bbox_min_lon'] = Variable<double>(bboxMinLon);
    map['bbox_max_lat'] = Variable<double>(bboxMaxLat);
    map['bbox_max_lon'] = Variable<double>(bboxMaxLon);
    map['installed_at'] = Variable<int>(installedAt);
    return map;
  }

  PacksCompanion toCompanion(bool nullToAbsent) {
    return PacksCompanion(
      region: Value(region),
      name: Value(name),
      osmTimestamp: Value(osmTimestamp),
      path: Value(path),
      sha256: Value(sha256),
      bytes: Value(bytes),
      wayCount: Value(wayCount),
      bboxMinLat: Value(bboxMinLat),
      bboxMinLon: Value(bboxMinLon),
      bboxMaxLat: Value(bboxMaxLat),
      bboxMaxLon: Value(bboxMaxLon),
      installedAt: Value(installedAt),
    );
  }

  factory Pack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Pack(
      region: serializer.fromJson<String>(json['region']),
      name: serializer.fromJson<String>(json['name']),
      osmTimestamp: serializer.fromJson<String>(json['osmTimestamp']),
      path: serializer.fromJson<String>(json['path']),
      sha256: serializer.fromJson<String>(json['sha256']),
      bytes: serializer.fromJson<int>(json['bytes']),
      wayCount: serializer.fromJson<int>(json['wayCount']),
      bboxMinLat: serializer.fromJson<double>(json['bboxMinLat']),
      bboxMinLon: serializer.fromJson<double>(json['bboxMinLon']),
      bboxMaxLat: serializer.fromJson<double>(json['bboxMaxLat']),
      bboxMaxLon: serializer.fromJson<double>(json['bboxMaxLon']),
      installedAt: serializer.fromJson<int>(json['installedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'region': serializer.toJson<String>(region),
      'name': serializer.toJson<String>(name),
      'osmTimestamp': serializer.toJson<String>(osmTimestamp),
      'path': serializer.toJson<String>(path),
      'sha256': serializer.toJson<String>(sha256),
      'bytes': serializer.toJson<int>(bytes),
      'wayCount': serializer.toJson<int>(wayCount),
      'bboxMinLat': serializer.toJson<double>(bboxMinLat),
      'bboxMinLon': serializer.toJson<double>(bboxMinLon),
      'bboxMaxLat': serializer.toJson<double>(bboxMaxLat),
      'bboxMaxLon': serializer.toJson<double>(bboxMaxLon),
      'installedAt': serializer.toJson<int>(installedAt),
    };
  }

  Pack copyWith({
    String? region,
    String? name,
    String? osmTimestamp,
    String? path,
    String? sha256,
    int? bytes,
    int? wayCount,
    double? bboxMinLat,
    double? bboxMinLon,
    double? bboxMaxLat,
    double? bboxMaxLon,
    int? installedAt,
  }) => Pack(
    region: region ?? this.region,
    name: name ?? this.name,
    osmTimestamp: osmTimestamp ?? this.osmTimestamp,
    path: path ?? this.path,
    sha256: sha256 ?? this.sha256,
    bytes: bytes ?? this.bytes,
    wayCount: wayCount ?? this.wayCount,
    bboxMinLat: bboxMinLat ?? this.bboxMinLat,
    bboxMinLon: bboxMinLon ?? this.bboxMinLon,
    bboxMaxLat: bboxMaxLat ?? this.bboxMaxLat,
    bboxMaxLon: bboxMaxLon ?? this.bboxMaxLon,
    installedAt: installedAt ?? this.installedAt,
  );
  Pack copyWithCompanion(PacksCompanion data) {
    return Pack(
      region: data.region.present ? data.region.value : this.region,
      name: data.name.present ? data.name.value : this.name,
      osmTimestamp: data.osmTimestamp.present
          ? data.osmTimestamp.value
          : this.osmTimestamp,
      path: data.path.present ? data.path.value : this.path,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      wayCount: data.wayCount.present ? data.wayCount.value : this.wayCount,
      bboxMinLat: data.bboxMinLat.present
          ? data.bboxMinLat.value
          : this.bboxMinLat,
      bboxMinLon: data.bboxMinLon.present
          ? data.bboxMinLon.value
          : this.bboxMinLon,
      bboxMaxLat: data.bboxMaxLat.present
          ? data.bboxMaxLat.value
          : this.bboxMaxLat,
      bboxMaxLon: data.bboxMaxLon.present
          ? data.bboxMaxLon.value
          : this.bboxMaxLon,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Pack(')
          ..write('region: $region, ')
          ..write('name: $name, ')
          ..write('osmTimestamp: $osmTimestamp, ')
          ..write('path: $path, ')
          ..write('sha256: $sha256, ')
          ..write('bytes: $bytes, ')
          ..write('wayCount: $wayCount, ')
          ..write('bboxMinLat: $bboxMinLat, ')
          ..write('bboxMinLon: $bboxMinLon, ')
          ..write('bboxMaxLat: $bboxMaxLat, ')
          ..write('bboxMaxLon: $bboxMaxLon, ')
          ..write('installedAt: $installedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    region,
    name,
    osmTimestamp,
    path,
    sha256,
    bytes,
    wayCount,
    bboxMinLat,
    bboxMinLon,
    bboxMaxLat,
    bboxMaxLon,
    installedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Pack &&
          other.region == this.region &&
          other.name == this.name &&
          other.osmTimestamp == this.osmTimestamp &&
          other.path == this.path &&
          other.sha256 == this.sha256 &&
          other.bytes == this.bytes &&
          other.wayCount == this.wayCount &&
          other.bboxMinLat == this.bboxMinLat &&
          other.bboxMinLon == this.bboxMinLon &&
          other.bboxMaxLat == this.bboxMaxLat &&
          other.bboxMaxLon == this.bboxMaxLon &&
          other.installedAt == this.installedAt);
}

class PacksCompanion extends UpdateCompanion<Pack> {
  final Value<String> region;
  final Value<String> name;
  final Value<String> osmTimestamp;
  final Value<String> path;
  final Value<String> sha256;
  final Value<int> bytes;
  final Value<int> wayCount;
  final Value<double> bboxMinLat;
  final Value<double> bboxMinLon;
  final Value<double> bboxMaxLat;
  final Value<double> bboxMaxLon;
  final Value<int> installedAt;
  final Value<int> rowid;
  const PacksCompanion({
    this.region = const Value.absent(),
    this.name = const Value.absent(),
    this.osmTimestamp = const Value.absent(),
    this.path = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.bytes = const Value.absent(),
    this.wayCount = const Value.absent(),
    this.bboxMinLat = const Value.absent(),
    this.bboxMinLon = const Value.absent(),
    this.bboxMaxLat = const Value.absent(),
    this.bboxMaxLon = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PacksCompanion.insert({
    required String region,
    required String name,
    required String osmTimestamp,
    required String path,
    required String sha256,
    required int bytes,
    required int wayCount,
    required double bboxMinLat,
    required double bboxMinLon,
    required double bboxMaxLat,
    required double bboxMaxLon,
    required int installedAt,
    this.rowid = const Value.absent(),
  }) : region = Value(region),
       name = Value(name),
       osmTimestamp = Value(osmTimestamp),
       path = Value(path),
       sha256 = Value(sha256),
       bytes = Value(bytes),
       wayCount = Value(wayCount),
       bboxMinLat = Value(bboxMinLat),
       bboxMinLon = Value(bboxMinLon),
       bboxMaxLat = Value(bboxMaxLat),
       bboxMaxLon = Value(bboxMaxLon),
       installedAt = Value(installedAt);
  static Insertable<Pack> custom({
    Expression<String>? region,
    Expression<String>? name,
    Expression<String>? osmTimestamp,
    Expression<String>? path,
    Expression<String>? sha256,
    Expression<int>? bytes,
    Expression<int>? wayCount,
    Expression<double>? bboxMinLat,
    Expression<double>? bboxMinLon,
    Expression<double>? bboxMaxLat,
    Expression<double>? bboxMaxLon,
    Expression<int>? installedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (region != null) 'region': region,
      if (name != null) 'name': name,
      if (osmTimestamp != null) 'osm_timestamp': osmTimestamp,
      if (path != null) 'path': path,
      if (sha256 != null) 'sha256': sha256,
      if (bytes != null) 'bytes': bytes,
      if (wayCount != null) 'way_count': wayCount,
      if (bboxMinLat != null) 'bbox_min_lat': bboxMinLat,
      if (bboxMinLon != null) 'bbox_min_lon': bboxMinLon,
      if (bboxMaxLat != null) 'bbox_max_lat': bboxMaxLat,
      if (bboxMaxLon != null) 'bbox_max_lon': bboxMaxLon,
      if (installedAt != null) 'installed_at': installedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PacksCompanion copyWith({
    Value<String>? region,
    Value<String>? name,
    Value<String>? osmTimestamp,
    Value<String>? path,
    Value<String>? sha256,
    Value<int>? bytes,
    Value<int>? wayCount,
    Value<double>? bboxMinLat,
    Value<double>? bboxMinLon,
    Value<double>? bboxMaxLat,
    Value<double>? bboxMaxLon,
    Value<int>? installedAt,
    Value<int>? rowid,
  }) {
    return PacksCompanion(
      region: region ?? this.region,
      name: name ?? this.name,
      osmTimestamp: osmTimestamp ?? this.osmTimestamp,
      path: path ?? this.path,
      sha256: sha256 ?? this.sha256,
      bytes: bytes ?? this.bytes,
      wayCount: wayCount ?? this.wayCount,
      bboxMinLat: bboxMinLat ?? this.bboxMinLat,
      bboxMinLon: bboxMinLon ?? this.bboxMinLon,
      bboxMaxLat: bboxMaxLat ?? this.bboxMaxLat,
      bboxMaxLon: bboxMaxLon ?? this.bboxMaxLon,
      installedAt: installedAt ?? this.installedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (osmTimestamp.present) {
      map['osm_timestamp'] = Variable<String>(osmTimestamp.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (wayCount.present) {
      map['way_count'] = Variable<int>(wayCount.value);
    }
    if (bboxMinLat.present) {
      map['bbox_min_lat'] = Variable<double>(bboxMinLat.value);
    }
    if (bboxMinLon.present) {
      map['bbox_min_lon'] = Variable<double>(bboxMinLon.value);
    }
    if (bboxMaxLat.present) {
      map['bbox_max_lat'] = Variable<double>(bboxMaxLat.value);
    }
    if (bboxMaxLon.present) {
      map['bbox_max_lon'] = Variable<double>(bboxMaxLon.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<int>(installedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PacksCompanion(')
          ..write('region: $region, ')
          ..write('name: $name, ')
          ..write('osmTimestamp: $osmTimestamp, ')
          ..write('path: $path, ')
          ..write('sha256: $sha256, ')
          ..write('bytes: $bytes, ')
          ..write('wayCount: $wayCount, ')
          ..write('bboxMinLat: $bboxMinLat, ')
          ..write('bboxMinLon: $bboxMinLon, ')
          ..write('bboxMaxLat: $bboxMaxLat, ')
          ..write('bboxMaxLon: $bboxMaxLon, ')
          ..write('installedAt: $installedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LimitFlagsTable extends LimitFlags
    with TableInfo<$LimitFlagsTable, LimitFlag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LimitFlagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _wayIdMeta = const VerificationMeta('wayId');
  @override
  late final GeneratedColumn<String> wayId = GeneratedColumn<String>(
    'way_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  @override
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _suggestedMpsMeta = const VerificationMeta(
    'suggestedMps',
  );
  @override
  late final GeneratedColumn<double> suggestedMps = GeneratedColumn<double>(
    'suggested_mps',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    wayId,
    region,
    tripId,
    suggestedMps,
    createdAt,
    synced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'limit_flags';
  @override
  VerificationContext validateIntegrity(
    Insertable<LimitFlag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('way_id')) {
      context.handle(
        _wayIdMeta,
        wayId.isAcceptableOrUnknown(data['way_id']!, _wayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wayIdMeta);
    }
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    }
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    }
    if (data.containsKey('suggested_mps')) {
      context.handle(
        _suggestedMpsMeta,
        suggestedMps.isAcceptableOrUnknown(
          data['suggested_mps']!,
          _suggestedMpsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_suggestedMpsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LimitFlag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LimitFlag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      wayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}way_id'],
      )!,
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      ),
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      ),
      suggestedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}suggested_mps'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
    );
  }

  @override
  $LimitFlagsTable createAlias(String alias) {
    return $LimitFlagsTable(attachedDatabase, alias);
  }
}

class LimitFlag extends DataClass implements Insertable<LimitFlag> {
  final int id;
  final String wayId;
  final String? region;
  final String? tripId;
  final double suggestedMps;
  final int createdAt;
  final bool synced;
  const LimitFlag({
    required this.id,
    required this.wayId,
    this.region,
    this.tripId,
    required this.suggestedMps,
    required this.createdAt,
    required this.synced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['way_id'] = Variable<String>(wayId);
    if (!nullToAbsent || region != null) {
      map['region'] = Variable<String>(region);
    }
    if (!nullToAbsent || tripId != null) {
      map['trip_id'] = Variable<String>(tripId);
    }
    map['suggested_mps'] = Variable<double>(suggestedMps);
    map['created_at'] = Variable<int>(createdAt);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  LimitFlagsCompanion toCompanion(bool nullToAbsent) {
    return LimitFlagsCompanion(
      id: Value(id),
      wayId: Value(wayId),
      region: region == null && nullToAbsent
          ? const Value.absent()
          : Value(region),
      tripId: tripId == null && nullToAbsent
          ? const Value.absent()
          : Value(tripId),
      suggestedMps: Value(suggestedMps),
      createdAt: Value(createdAt),
      synced: Value(synced),
    );
  }

  factory LimitFlag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LimitFlag(
      id: serializer.fromJson<int>(json['id']),
      wayId: serializer.fromJson<String>(json['wayId']),
      region: serializer.fromJson<String?>(json['region']),
      tripId: serializer.fromJson<String?>(json['tripId']),
      suggestedMps: serializer.fromJson<double>(json['suggestedMps']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'wayId': serializer.toJson<String>(wayId),
      'region': serializer.toJson<String?>(region),
      'tripId': serializer.toJson<String?>(tripId),
      'suggestedMps': serializer.toJson<double>(suggestedMps),
      'createdAt': serializer.toJson<int>(createdAt),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  LimitFlag copyWith({
    int? id,
    String? wayId,
    Value<String?> region = const Value.absent(),
    Value<String?> tripId = const Value.absent(),
    double? suggestedMps,
    int? createdAt,
    bool? synced,
  }) => LimitFlag(
    id: id ?? this.id,
    wayId: wayId ?? this.wayId,
    region: region.present ? region.value : this.region,
    tripId: tripId.present ? tripId.value : this.tripId,
    suggestedMps: suggestedMps ?? this.suggestedMps,
    createdAt: createdAt ?? this.createdAt,
    synced: synced ?? this.synced,
  );
  LimitFlag copyWithCompanion(LimitFlagsCompanion data) {
    return LimitFlag(
      id: data.id.present ? data.id.value : this.id,
      wayId: data.wayId.present ? data.wayId.value : this.wayId,
      region: data.region.present ? data.region.value : this.region,
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      suggestedMps: data.suggestedMps.present
          ? data.suggestedMps.value
          : this.suggestedMps,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LimitFlag(')
          ..write('id: $id, ')
          ..write('wayId: $wayId, ')
          ..write('region: $region, ')
          ..write('tripId: $tripId, ')
          ..write('suggestedMps: $suggestedMps, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, wayId, region, tripId, suggestedMps, createdAt, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LimitFlag &&
          other.id == this.id &&
          other.wayId == this.wayId &&
          other.region == this.region &&
          other.tripId == this.tripId &&
          other.suggestedMps == this.suggestedMps &&
          other.createdAt == this.createdAt &&
          other.synced == this.synced);
}

class LimitFlagsCompanion extends UpdateCompanion<LimitFlag> {
  final Value<int> id;
  final Value<String> wayId;
  final Value<String?> region;
  final Value<String?> tripId;
  final Value<double> suggestedMps;
  final Value<int> createdAt;
  final Value<bool> synced;
  const LimitFlagsCompanion({
    this.id = const Value.absent(),
    this.wayId = const Value.absent(),
    this.region = const Value.absent(),
    this.tripId = const Value.absent(),
    this.suggestedMps = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.synced = const Value.absent(),
  });
  LimitFlagsCompanion.insert({
    this.id = const Value.absent(),
    required String wayId,
    this.region = const Value.absent(),
    this.tripId = const Value.absent(),
    required double suggestedMps,
    required int createdAt,
    this.synced = const Value.absent(),
  }) : wayId = Value(wayId),
       suggestedMps = Value(suggestedMps),
       createdAt = Value(createdAt);
  static Insertable<LimitFlag> custom({
    Expression<int>? id,
    Expression<String>? wayId,
    Expression<String>? region,
    Expression<String>? tripId,
    Expression<double>? suggestedMps,
    Expression<int>? createdAt,
    Expression<bool>? synced,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (wayId != null) 'way_id': wayId,
      if (region != null) 'region': region,
      if (tripId != null) 'trip_id': tripId,
      if (suggestedMps != null) 'suggested_mps': suggestedMps,
      if (createdAt != null) 'created_at': createdAt,
      if (synced != null) 'synced': synced,
    });
  }

  LimitFlagsCompanion copyWith({
    Value<int>? id,
    Value<String>? wayId,
    Value<String?>? region,
    Value<String?>? tripId,
    Value<double>? suggestedMps,
    Value<int>? createdAt,
    Value<bool>? synced,
  }) {
    return LimitFlagsCompanion(
      id: id ?? this.id,
      wayId: wayId ?? this.wayId,
      region: region ?? this.region,
      tripId: tripId ?? this.tripId,
      suggestedMps: suggestedMps ?? this.suggestedMps,
      createdAt: createdAt ?? this.createdAt,
      synced: synced ?? this.synced,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (wayId.present) {
      map['way_id'] = Variable<String>(wayId.value);
    }
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (suggestedMps.present) {
      map['suggested_mps'] = Variable<double>(suggestedMps.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LimitFlagsCompanion(')
          ..write('id: $id, ')
          ..write('wayId: $wayId, ')
          ..write('region: $region, ')
          ..write('tripId: $tripId, ')
          ..write('suggestedMps: $suggestedMps, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FixBatchesTable extends FixBatches
    with TableInfo<$FixBatchesTable, FixBatche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchTMeta = const VerificationMeta('batchT');
  @override
  late final GeneratedColumn<int> batchT = GeneratedColumn<int>(
    'batch_t',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tripId, batchT];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fix_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixBatche> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('batch_t')) {
      context.handle(
        _batchTMeta,
        batchT.isAcceptableOrUnknown(data['batch_t']!, _batchTMeta),
      );
    } else if (isInserting) {
      context.missing(_batchTMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, batchT};
  @override
  FixBatche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixBatche(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      batchT: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}batch_t'],
      )!,
    );
  }

  @override
  $FixBatchesTable createAlias(String alias) {
    return $FixBatchesTable(attachedDatabase, alias);
  }
}

class FixBatche extends DataClass implements Insertable<FixBatche> {
  final String tripId;
  final int batchT;
  const FixBatche({required this.tripId, required this.batchT});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['batch_t'] = Variable<int>(batchT);
    return map;
  }

  FixBatchesCompanion toCompanion(bool nullToAbsent) {
    return FixBatchesCompanion(tripId: Value(tripId), batchT: Value(batchT));
  }

  factory FixBatche.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixBatche(
      tripId: serializer.fromJson<String>(json['tripId']),
      batchT: serializer.fromJson<int>(json['batchT']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'batchT': serializer.toJson<int>(batchT),
    };
  }

  FixBatche copyWith({String? tripId, int? batchT}) =>
      FixBatche(tripId: tripId ?? this.tripId, batchT: batchT ?? this.batchT);
  FixBatche copyWithCompanion(FixBatchesCompanion data) {
    return FixBatche(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      batchT: data.batchT.present ? data.batchT.value : this.batchT,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixBatche(')
          ..write('tripId: $tripId, ')
          ..write('batchT: $batchT')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tripId, batchT);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixBatche &&
          other.tripId == this.tripId &&
          other.batchT == this.batchT);
}

class FixBatchesCompanion extends UpdateCompanion<FixBatche> {
  final Value<String> tripId;
  final Value<int> batchT;
  final Value<int> rowid;
  const FixBatchesCompanion({
    this.tripId = const Value.absent(),
    this.batchT = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixBatchesCompanion.insert({
    required String tripId,
    required int batchT,
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       batchT = Value(batchT);
  static Insertable<FixBatche> custom({
    Expression<String>? tripId,
    Expression<int>? batchT,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (batchT != null) 'batch_t': batchT,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixBatchesCompanion copyWith({
    Value<String>? tripId,
    Value<int>? batchT,
    Value<int>? rowid,
  }) {
    return FixBatchesCompanion(
      tripId: tripId ?? this.tripId,
      batchT: batchT ?? this.batchT,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (batchT.present) {
      map['batch_t'] = Variable<int>(batchT.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixBatchesCompanion(')
          ..write('tripId: $tripId, ')
          ..write('batchT: $batchT, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    payload,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final String id;
  final String kind;
  final String payload;
  final int createdAt;
  final int attempts;
  final int nextAttemptAt;
  final String? lastError;
  const OutboxData({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<int>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      kind: Value(kind),
      payload: Value(payload),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<int>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<int>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<int>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxData copyWith({
    String? id,
    String? kind,
    String? payload,
    int? createdAt,
    int? attempts,
    int? nextAttemptAt,
    Value<String?> lastError = const Value.absent(),
  }) => OutboxData(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    payload,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> payload;
  final Value<int> createdAt;
  final Value<int> attempts;
  final Value<int> nextAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String id,
    required String kind,
    required String payload,
    required int createdAt,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<OutboxData> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? payload,
    Expression<int>? createdAt,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? payload,
    Value<int>? createdAt,
    Value<int>? attempts,
    Value<int>? nextAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return OutboxCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteCacheTable extends RemoteCache
    with TableInfo<$RemoteCacheTable, RemoteCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, json, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  RemoteCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteCacheData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RemoteCacheTable createAlias(String alias) {
    return $RemoteCacheTable(attachedDatabase, alias);
  }
}

class RemoteCacheData extends DataClass implements Insertable<RemoteCacheData> {
  final String key;
  final String json;
  final int updatedAt;
  const RemoteCacheData({
    required this.key,
    required this.json,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['json'] = Variable<String>(json);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  RemoteCacheCompanion toCompanion(bool nullToAbsent) {
    return RemoteCacheCompanion(
      key: Value(key),
      json: Value(json),
      updatedAt: Value(updatedAt),
    );
  }

  factory RemoteCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteCacheData(
      key: serializer.fromJson<String>(json['key']),
      json: serializer.fromJson<String>(json['json']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'json': serializer.toJson<String>(json),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  RemoteCacheData copyWith({String? key, String? json, int? updatedAt}) =>
      RemoteCacheData(
        key: key ?? this.key,
        json: json ?? this.json,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  RemoteCacheData copyWithCompanion(RemoteCacheCompanion data) {
    return RemoteCacheData(
      key: data.key.present ? data.key.value : this.key,
      json: data.json.present ? data.json.value : this.json,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCacheData(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, json, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteCacheData &&
          other.key == this.key &&
          other.json == this.json &&
          other.updatedAt == this.updatedAt);
}

class RemoteCacheCompanion extends UpdateCompanion<RemoteCacheData> {
  final Value<String> key;
  final Value<String> json;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const RemoteCacheCompanion({
    this.key = const Value.absent(),
    this.json = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteCacheCompanion.insert({
    required String key,
    required String json,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       json = Value(json),
       updatedAt = Value(updatedAt);
  static Insertable<RemoteCacheData> custom({
    Expression<String>? key,
    Expression<String>? json,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (json != null) 'json': json,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteCacheCompanion copyWith({
    Value<String>? key,
    Value<String>? json,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return RemoteCacheCompanion(
      key: key ?? this.key,
      json: json ?? this.json,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCacheCompanion(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadedTripsTable extends UploadedTrips
    with TableInfo<$UploadedTripsTable, UploadedTrip> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadedTripsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadedAtMeta = const VerificationMeta(
    'uploadedAt',
  );
  @override
  late final GeneratedColumn<int> uploadedAt = GeneratedColumn<int>(
    'uploaded_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryHashMeta = const VerificationMeta(
    'summaryHash',
  );
  @override
  late final GeneratedColumn<String> summaryHash = GeneratedColumn<String>(
    'summary_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tripId, uploadedAt, summaryHash];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'uploaded_trips';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadedTrip> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
        _uploadedAtMeta,
        uploadedAt.isAcceptableOrUnknown(data['uploaded_at']!, _uploadedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadedAtMeta);
    }
    if (data.containsKey('summary_hash')) {
      context.handle(
        _summaryHashMeta,
        summaryHash.isAcceptableOrUnknown(
          data['summary_hash']!,
          _summaryHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryHashMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId};
  @override
  UploadedTrip map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadedTrip(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      uploadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uploaded_at'],
      )!,
      summaryHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_hash'],
      )!,
    );
  }

  @override
  $UploadedTripsTable createAlias(String alias) {
    return $UploadedTripsTable(attachedDatabase, alias);
  }
}

class UploadedTrip extends DataClass implements Insertable<UploadedTrip> {
  final String tripId;
  final int uploadedAt;
  final String summaryHash;
  const UploadedTrip({
    required this.tripId,
    required this.uploadedAt,
    required this.summaryHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['uploaded_at'] = Variable<int>(uploadedAt);
    map['summary_hash'] = Variable<String>(summaryHash);
    return map;
  }

  UploadedTripsCompanion toCompanion(bool nullToAbsent) {
    return UploadedTripsCompanion(
      tripId: Value(tripId),
      uploadedAt: Value(uploadedAt),
      summaryHash: Value(summaryHash),
    );
  }

  factory UploadedTrip.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadedTrip(
      tripId: serializer.fromJson<String>(json['tripId']),
      uploadedAt: serializer.fromJson<int>(json['uploadedAt']),
      summaryHash: serializer.fromJson<String>(json['summaryHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'uploadedAt': serializer.toJson<int>(uploadedAt),
      'summaryHash': serializer.toJson<String>(summaryHash),
    };
  }

  UploadedTrip copyWith({
    String? tripId,
    int? uploadedAt,
    String? summaryHash,
  }) => UploadedTrip(
    tripId: tripId ?? this.tripId,
    uploadedAt: uploadedAt ?? this.uploadedAt,
    summaryHash: summaryHash ?? this.summaryHash,
  );
  UploadedTrip copyWithCompanion(UploadedTripsCompanion data) {
    return UploadedTrip(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      uploadedAt: data.uploadedAt.present
          ? data.uploadedAt.value
          : this.uploadedAt,
      summaryHash: data.summaryHash.present
          ? data.summaryHash.value
          : this.summaryHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadedTrip(')
          ..write('tripId: $tripId, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('summaryHash: $summaryHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tripId, uploadedAt, summaryHash);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadedTrip &&
          other.tripId == this.tripId &&
          other.uploadedAt == this.uploadedAt &&
          other.summaryHash == this.summaryHash);
}

class UploadedTripsCompanion extends UpdateCompanion<UploadedTrip> {
  final Value<String> tripId;
  final Value<int> uploadedAt;
  final Value<String> summaryHash;
  final Value<int> rowid;
  const UploadedTripsCompanion({
    this.tripId = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.summaryHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadedTripsCompanion.insert({
    required String tripId,
    required int uploadedAt,
    required String summaryHash,
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       uploadedAt = Value(uploadedAt),
       summaryHash = Value(summaryHash);
  static Insertable<UploadedTrip> custom({
    Expression<String>? tripId,
    Expression<int>? uploadedAt,
    Expression<String>? summaryHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (summaryHash != null) 'summary_hash': summaryHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadedTripsCompanion copyWith({
    Value<String>? tripId,
    Value<int>? uploadedAt,
    Value<String>? summaryHash,
    Value<int>? rowid,
  }) {
    return UploadedTripsCompanion(
      tripId: tripId ?? this.tripId,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      summaryHash: summaryHash ?? this.summaryHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<int>(uploadedAt.value);
    }
    if (summaryHash.present) {
      map['summary_hash'] = Variable<String>(summaryHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadedTripsCompanion(')
          ..write('tripId: $tripId, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('summaryHash: $summaryHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BadgeAwardsTable extends BadgeAwards
    with TableInfo<$BadgeAwardsTable, BadgeAward> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BadgeAwardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _badgeIdMeta = const VerificationMeta(
    'badgeId',
  );
  @override
  late final GeneratedColumn<String> badgeId = GeneratedColumn<String>(
    'badge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _awardedAtMeta = const VerificationMeta(
    'awardedAt',
  );
  @override
  late final GeneratedColumn<int> awardedAt = GeneratedColumn<int>(
    'awarded_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [badgeId, awardedAt, synced];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'badge_awards';
  @override
  VerificationContext validateIntegrity(
    Insertable<BadgeAward> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('badge_id')) {
      context.handle(
        _badgeIdMeta,
        badgeId.isAcceptableOrUnknown(data['badge_id']!, _badgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_badgeIdMeta);
    }
    if (data.containsKey('awarded_at')) {
      context.handle(
        _awardedAtMeta,
        awardedAt.isAcceptableOrUnknown(data['awarded_at']!, _awardedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_awardedAtMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {badgeId};
  @override
  BadgeAward map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BadgeAward(
      badgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}badge_id'],
      )!,
      awardedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}awarded_at'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
    );
  }

  @override
  $BadgeAwardsTable createAlias(String alias) {
    return $BadgeAwardsTable(attachedDatabase, alias);
  }
}

class BadgeAward extends DataClass implements Insertable<BadgeAward> {
  final String badgeId;
  final int awardedAt;
  final bool synced;
  const BadgeAward({
    required this.badgeId,
    required this.awardedAt,
    required this.synced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['badge_id'] = Variable<String>(badgeId);
    map['awarded_at'] = Variable<int>(awardedAt);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  BadgeAwardsCompanion toCompanion(bool nullToAbsent) {
    return BadgeAwardsCompanion(
      badgeId: Value(badgeId),
      awardedAt: Value(awardedAt),
      synced: Value(synced),
    );
  }

  factory BadgeAward.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BadgeAward(
      badgeId: serializer.fromJson<String>(json['badgeId']),
      awardedAt: serializer.fromJson<int>(json['awardedAt']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'badgeId': serializer.toJson<String>(badgeId),
      'awardedAt': serializer.toJson<int>(awardedAt),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  BadgeAward copyWith({String? badgeId, int? awardedAt, bool? synced}) =>
      BadgeAward(
        badgeId: badgeId ?? this.badgeId,
        awardedAt: awardedAt ?? this.awardedAt,
        synced: synced ?? this.synced,
      );
  BadgeAward copyWithCompanion(BadgeAwardsCompanion data) {
    return BadgeAward(
      badgeId: data.badgeId.present ? data.badgeId.value : this.badgeId,
      awardedAt: data.awardedAt.present ? data.awardedAt.value : this.awardedAt,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BadgeAward(')
          ..write('badgeId: $badgeId, ')
          ..write('awardedAt: $awardedAt, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(badgeId, awardedAt, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BadgeAward &&
          other.badgeId == this.badgeId &&
          other.awardedAt == this.awardedAt &&
          other.synced == this.synced);
}

class BadgeAwardsCompanion extends UpdateCompanion<BadgeAward> {
  final Value<String> badgeId;
  final Value<int> awardedAt;
  final Value<bool> synced;
  final Value<int> rowid;
  const BadgeAwardsCompanion({
    this.badgeId = const Value.absent(),
    this.awardedAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BadgeAwardsCompanion.insert({
    required String badgeId,
    required int awardedAt,
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : badgeId = Value(badgeId),
       awardedAt = Value(awardedAt);
  static Insertable<BadgeAward> custom({
    Expression<String>? badgeId,
    Expression<int>? awardedAt,
    Expression<bool>? synced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (badgeId != null) 'badge_id': badgeId,
      if (awardedAt != null) 'awarded_at': awardedAt,
      if (synced != null) 'synced': synced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BadgeAwardsCompanion copyWith({
    Value<String>? badgeId,
    Value<int>? awardedAt,
    Value<bool>? synced,
    Value<int>? rowid,
  }) {
    return BadgeAwardsCompanion(
      badgeId: badgeId ?? this.badgeId,
      awardedAt: awardedAt ?? this.awardedAt,
      synced: synced ?? this.synced,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (badgeId.present) {
      map['badge_id'] = Variable<String>(badgeId.value);
    }
    if (awardedAt.present) {
      map['awarded_at'] = Variable<int>(awardedAt.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BadgeAwardsCompanion(')
          ..write('badgeId: $badgeId, ')
          ..write('awardedAt: $awardedAt, ')
          ..write('synced: $synced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TripsTable trips = $TripsTable(this);
  late final $SamplesTable samples = $SamplesTable(this);
  late final $MotionPeaksTable motionPeaks = $MotionPeaksTable(this);
  late final $PhoneEventsTable phoneEvents = $PhoneEventsTable(this);
  late final $SegmentsTable segments = $SegmentsTable(this);
  late final $TripScoresTable tripScores = $TripScoresTable(this);
  late final $PacksTable packs = $PacksTable(this);
  late final $LimitFlagsTable limitFlags = $LimitFlagsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $FixBatchesTable fixBatches = $FixBatchesTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $RemoteCacheTable remoteCache = $RemoteCacheTable(this);
  late final $UploadedTripsTable uploadedTrips = $UploadedTripsTable(this);
  late final $BadgeAwardsTable badgeAwards = $BadgeAwardsTable(this);
  late final Index tripsStartedAt = Index(
    'trips_started_at',
    'CREATE INDEX trips_started_at ON trips (started_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    trips,
    samples,
    motionPeaks,
    phoneEvents,
    segments,
    tripScores,
    packs,
    limitFlags,
    settings,
    fixBatches,
    outbox,
    remoteCache,
    uploadedTrips,
    badgeAwards,
    tripsStartedAt,
  ];
}

typedef $$TripsTableCreateCompanionBuilder =
    TripsCompanion Function({
      required String id,
      required int startedAt,
      Value<int?> endedAt,
      required String phase,
      Value<String?> endReason,
      Value<String?> triggerKind,
      Value<double> distanceM,
      Value<double> movingS,
      Value<bool?> isPassenger,
      Value<bool> passengerHint,
      Value<bool> passengerAnswered,
      Value<String?> vehicleLabel,
      Value<String?> packRegion,
      Value<String?> packVersion,
      Value<double?> limitCoverage,
      Value<double?> nightFraction,
      Value<String?> weather,
      required int createdAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });
typedef $$TripsTableUpdateCompanionBuilder =
    TripsCompanion Function({
      Value<String> id,
      Value<int> startedAt,
      Value<int?> endedAt,
      Value<String> phase,
      Value<String?> endReason,
      Value<String?> triggerKind,
      Value<double> distanceM,
      Value<double> movingS,
      Value<bool?> isPassenger,
      Value<bool> passengerHint,
      Value<bool> passengerAnswered,
      Value<String?> vehicleLabel,
      Value<String?> packRegion,
      Value<String?> packVersion,
      Value<double?> limitCoverage,
      Value<double?> nightFraction,
      Value<String?> weather,
      Value<int> createdAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });

class $$TripsTableFilterComposer extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerKind => $composableBuilder(
    column: $table.triggerKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get movingS => $composableBuilder(
    column: $table.movingS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPassenger => $composableBuilder(
    column: $table.isPassenger,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get passengerHint => $composableBuilder(
    column: $table.passengerHint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get passengerAnswered => $composableBuilder(
    column: $table.passengerAnswered,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packRegion => $composableBuilder(
    column: $table.packRegion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get limitCoverage => $composableBuilder(
    column: $table.limitCoverage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get nightFraction => $composableBuilder(
    column: $table.nightFraction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weather => $composableBuilder(
    column: $table.weather,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TripsTableOrderingComposer
    extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerKind => $composableBuilder(
    column: $table.triggerKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get movingS => $composableBuilder(
    column: $table.movingS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPassenger => $composableBuilder(
    column: $table.isPassenger,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get passengerHint => $composableBuilder(
    column: $table.passengerHint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get passengerAnswered => $composableBuilder(
    column: $table.passengerAnswered,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packRegion => $composableBuilder(
    column: $table.packRegion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get limitCoverage => $composableBuilder(
    column: $table.limitCoverage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get nightFraction => $composableBuilder(
    column: $table.nightFraction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weather => $composableBuilder(
    column: $table.weather,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TripsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get endReason =>
      $composableBuilder(column: $table.endReason, builder: (column) => column);

  GeneratedColumn<String> get triggerKind => $composableBuilder(
    column: $table.triggerKind,
    builder: (column) => column,
  );

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);

  GeneratedColumn<double> get movingS =>
      $composableBuilder(column: $table.movingS, builder: (column) => column);

  GeneratedColumn<bool> get isPassenger => $composableBuilder(
    column: $table.isPassenger,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get passengerHint => $composableBuilder(
    column: $table.passengerHint,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get passengerAnswered => $composableBuilder(
    column: $table.passengerAnswered,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packRegion => $composableBuilder(
    column: $table.packRegion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => column,
  );

  GeneratedColumn<double> get limitCoverage => $composableBuilder(
    column: $table.limitCoverage,
    builder: (column) => column,
  );

  GeneratedColumn<double> get nightFraction => $composableBuilder(
    column: $table.nightFraction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weather =>
      $composableBuilder(column: $table.weather, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$TripsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TripsTable,
          Trip,
          $$TripsTableFilterComposer,
          $$TripsTableOrderingComposer,
          $$TripsTableAnnotationComposer,
          $$TripsTableCreateCompanionBuilder,
          $$TripsTableUpdateCompanionBuilder,
          (Trip, BaseReferences<_$AppDatabase, $TripsTable, Trip>),
          Trip,
          PrefetchHooks Function()
        > {
  $$TripsTableTableManager(_$AppDatabase db, $TripsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TripsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TripsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TripsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int?> endedAt = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<String?> endReason = const Value.absent(),
                Value<String?> triggerKind = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<double> movingS = const Value.absent(),
                Value<bool?> isPassenger = const Value.absent(),
                Value<bool> passengerHint = const Value.absent(),
                Value<bool> passengerAnswered = const Value.absent(),
                Value<String?> vehicleLabel = const Value.absent(),
                Value<String?> packRegion = const Value.absent(),
                Value<String?> packVersion = const Value.absent(),
                Value<double?> limitCoverage = const Value.absent(),
                Value<double?> nightFraction = const Value.absent(),
                Value<String?> weather = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TripsCompanion(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                phase: phase,
                endReason: endReason,
                triggerKind: triggerKind,
                distanceM: distanceM,
                movingS: movingS,
                isPassenger: isPassenger,
                passengerHint: passengerHint,
                passengerAnswered: passengerAnswered,
                vehicleLabel: vehicleLabel,
                packRegion: packRegion,
                packVersion: packVersion,
                limitCoverage: limitCoverage,
                nightFraction: nightFraction,
                weather: weather,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int startedAt,
                Value<int?> endedAt = const Value.absent(),
                required String phase,
                Value<String?> endReason = const Value.absent(),
                Value<String?> triggerKind = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<double> movingS = const Value.absent(),
                Value<bool?> isPassenger = const Value.absent(),
                Value<bool> passengerHint = const Value.absent(),
                Value<bool> passengerAnswered = const Value.absent(),
                Value<String?> vehicleLabel = const Value.absent(),
                Value<String?> packRegion = const Value.absent(),
                Value<String?> packVersion = const Value.absent(),
                Value<double?> limitCoverage = const Value.absent(),
                Value<double?> nightFraction = const Value.absent(),
                Value<String?> weather = const Value.absent(),
                required int createdAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TripsCompanion.insert(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                phase: phase,
                endReason: endReason,
                triggerKind: triggerKind,
                distanceM: distanceM,
                movingS: movingS,
                isPassenger: isPassenger,
                passengerHint: passengerHint,
                passengerAnswered: passengerAnswered,
                vehicleLabel: vehicleLabel,
                packRegion: packRegion,
                packVersion: packVersion,
                limitCoverage: limitCoverage,
                nightFraction: nightFraction,
                weather: weather,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TripsTable, Trip>(table),
                  BaseReferences<_$AppDatabase, $TripsTable, Trip>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TripsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TripsTable,
      Trip,
      $$TripsTableFilterComposer,
      $$TripsTableOrderingComposer,
      $$TripsTableAnnotationComposer,
      $$TripsTableCreateCompanionBuilder,
      $$TripsTableUpdateCompanionBuilder,
      (Trip, BaseReferences<_$AppDatabase, $TripsTable, Trip>),
      Trip,
      PrefetchHooks Function()
    >;
typedef $$SamplesTableCreateCompanionBuilder =
    SamplesCompanion Function({
      required String tripId,
      required int t,
      required double lat,
      required double lon,
      Value<double?> speed,
      required double accuracy,
      Value<double?> heading,
      Value<double?> altitude,
      Value<int> rowid,
    });
typedef $$SamplesTableUpdateCompanionBuilder =
    SamplesCompanion Function({
      Value<String> tripId,
      Value<int> t,
      Value<double> lat,
      Value<double> lon,
      Value<double?> speed,
      Value<double> accuracy,
      Value<double?> heading,
      Value<double?> altitude,
      Value<int> rowid,
    });

class $$SamplesTableFilterComposer
    extends Composer<_$AppDatabase, $SamplesTable> {
  $$SamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heading => $composableBuilder(
    column: $table.heading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SamplesTableOrderingComposer
    extends Composer<_$AppDatabase, $SamplesTable> {
  $$SamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heading => $composableBuilder(
    column: $table.heading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SamplesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SamplesTable> {
  $$SamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get t =>
      $composableBuilder(column: $table.t, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<double> get accuracy =>
      $composableBuilder(column: $table.accuracy, builder: (column) => column);

  GeneratedColumn<double> get heading =>
      $composableBuilder(column: $table.heading, builder: (column) => column);

  GeneratedColumn<double> get altitude =>
      $composableBuilder(column: $table.altitude, builder: (column) => column);
}

class $$SamplesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SamplesTable,
          Sample,
          $$SamplesTableFilterComposer,
          $$SamplesTableOrderingComposer,
          $$SamplesTableAnnotationComposer,
          $$SamplesTableCreateCompanionBuilder,
          $$SamplesTableUpdateCompanionBuilder,
          (Sample, BaseReferences<_$AppDatabase, $SamplesTable, Sample>),
          Sample,
          PrefetchHooks Function()
        > {
  $$SamplesTableTableManager(_$AppDatabase db, $SamplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> t = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<double> accuracy = const Value.absent(),
                Value<double?> heading = const Value.absent(),
                Value<double?> altitude = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SamplesCompanion(
                tripId: tripId,
                t: t,
                lat: lat,
                lon: lon,
                speed: speed,
                accuracy: accuracy,
                heading: heading,
                altitude: altitude,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int t,
                required double lat,
                required double lon,
                Value<double?> speed = const Value.absent(),
                required double accuracy,
                Value<double?> heading = const Value.absent(),
                Value<double?> altitude = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SamplesCompanion.insert(
                tripId: tripId,
                t: t,
                lat: lat,
                lon: lon,
                speed: speed,
                accuracy: accuracy,
                heading: heading,
                altitude: altitude,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SamplesTable, Sample>(table),
                  BaseReferences<_$AppDatabase, $SamplesTable, Sample>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SamplesTable,
      Sample,
      $$SamplesTableFilterComposer,
      $$SamplesTableOrderingComposer,
      $$SamplesTableAnnotationComposer,
      $$SamplesTableCreateCompanionBuilder,
      $$SamplesTableUpdateCompanionBuilder,
      (Sample, BaseReferences<_$AppDatabase, $SamplesTable, Sample>),
      Sample,
      PrefetchHooks Function()
    >;
typedef $$MotionPeaksTableCreateCompanionBuilder =
    MotionPeaksCompanion Function({
      required String tripId,
      required int t,
      required double peak,
      Value<int> rowid,
    });
typedef $$MotionPeaksTableUpdateCompanionBuilder =
    MotionPeaksCompanion Function({
      Value<String> tripId,
      Value<int> t,
      Value<double> peak,
      Value<int> rowid,
    });

class $$MotionPeaksTableFilterComposer
    extends Composer<_$AppDatabase, $MotionPeaksTable> {
  $$MotionPeaksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get peak => $composableBuilder(
    column: $table.peak,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MotionPeaksTableOrderingComposer
    extends Composer<_$AppDatabase, $MotionPeaksTable> {
  $$MotionPeaksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get peak => $composableBuilder(
    column: $table.peak,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MotionPeaksTableAnnotationComposer
    extends Composer<_$AppDatabase, $MotionPeaksTable> {
  $$MotionPeaksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get t =>
      $composableBuilder(column: $table.t, builder: (column) => column);

  GeneratedColumn<double> get peak =>
      $composableBuilder(column: $table.peak, builder: (column) => column);
}

class $$MotionPeaksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MotionPeaksTable,
          MotionPeak,
          $$MotionPeaksTableFilterComposer,
          $$MotionPeaksTableOrderingComposer,
          $$MotionPeaksTableAnnotationComposer,
          $$MotionPeaksTableCreateCompanionBuilder,
          $$MotionPeaksTableUpdateCompanionBuilder,
          (
            MotionPeak,
            BaseReferences<_$AppDatabase, $MotionPeaksTable, MotionPeak>,
          ),
          MotionPeak,
          PrefetchHooks Function()
        > {
  $$MotionPeaksTableTableManager(_$AppDatabase db, $MotionPeaksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MotionPeaksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MotionPeaksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MotionPeaksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> t = const Value.absent(),
                Value<double> peak = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MotionPeaksCompanion(
                tripId: tripId,
                t: t,
                peak: peak,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int t,
                required double peak,
                Value<int> rowid = const Value.absent(),
              }) => MotionPeaksCompanion.insert(
                tripId: tripId,
                t: t,
                peak: peak,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MotionPeaksTable, MotionPeak>(table),
                  BaseReferences<_$AppDatabase, $MotionPeaksTable, MotionPeak>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MotionPeaksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MotionPeaksTable,
      MotionPeak,
      $$MotionPeaksTableFilterComposer,
      $$MotionPeaksTableOrderingComposer,
      $$MotionPeaksTableAnnotationComposer,
      $$MotionPeaksTableCreateCompanionBuilder,
      $$MotionPeaksTableUpdateCompanionBuilder,
      (
        MotionPeak,
        BaseReferences<_$AppDatabase, $MotionPeaksTable, MotionPeak>,
      ),
      MotionPeak,
      PrefetchHooks Function()
    >;
typedef $$PhoneEventsTableCreateCompanionBuilder =
    PhoneEventsCompanion Function({
      required String tripId,
      required int t,
      required String kind,
      Value<int> rowid,
    });
typedef $$PhoneEventsTableUpdateCompanionBuilder =
    PhoneEventsCompanion Function({
      Value<String> tripId,
      Value<int> t,
      Value<String> kind,
      Value<int> rowid,
    });

class $$PhoneEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PhoneEventsTable> {
  $$PhoneEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PhoneEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PhoneEventsTable> {
  $$PhoneEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PhoneEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PhoneEventsTable> {
  $$PhoneEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get t =>
      $composableBuilder(column: $table.t, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);
}

class $$PhoneEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PhoneEventsTable,
          PhoneEventRow,
          $$PhoneEventsTableFilterComposer,
          $$PhoneEventsTableOrderingComposer,
          $$PhoneEventsTableAnnotationComposer,
          $$PhoneEventsTableCreateCompanionBuilder,
          $$PhoneEventsTableUpdateCompanionBuilder,
          (
            PhoneEventRow,
            BaseReferences<_$AppDatabase, $PhoneEventsTable, PhoneEventRow>,
          ),
          PhoneEventRow,
          PrefetchHooks Function()
        > {
  $$PhoneEventsTableTableManager(_$AppDatabase db, $PhoneEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhoneEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhoneEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhoneEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> t = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhoneEventsCompanion(
                tripId: tripId,
                t: t,
                kind: kind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int t,
                required String kind,
                Value<int> rowid = const Value.absent(),
              }) => PhoneEventsCompanion.insert(
                tripId: tripId,
                t: t,
                kind: kind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PhoneEventsTable, PhoneEventRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PhoneEventsTable,
                    PhoneEventRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PhoneEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PhoneEventsTable,
      PhoneEventRow,
      $$PhoneEventsTableFilterComposer,
      $$PhoneEventsTableOrderingComposer,
      $$PhoneEventsTableAnnotationComposer,
      $$PhoneEventsTableCreateCompanionBuilder,
      $$PhoneEventsTableUpdateCompanionBuilder,
      (
        PhoneEventRow,
        BaseReferences<_$AppDatabase, $PhoneEventsTable, PhoneEventRow>,
      ),
      PhoneEventRow,
      PrefetchHooks Function()
    >;
typedef $$SegmentsTableCreateCompanionBuilder =
    SegmentsCompanion Function({
      required String tripId,
      required int fromIdx,
      required int toIdx,
      Value<double?> speedLimitMps,
      required double confidence,
      required String roadClass,
      Value<String?> name,
      Value<String?> wayId,
      Value<int> rowid,
    });
typedef $$SegmentsTableUpdateCompanionBuilder =
    SegmentsCompanion Function({
      Value<String> tripId,
      Value<int> fromIdx,
      Value<int> toIdx,
      Value<double?> speedLimitMps,
      Value<double> confidence,
      Value<String> roadClass,
      Value<String?> name,
      Value<String?> wayId,
      Value<int> rowid,
    });

class $$SegmentsTableFilterComposer
    extends Composer<_$AppDatabase, $SegmentsTable> {
  $$SegmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fromIdx => $composableBuilder(
    column: $table.fromIdx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get toIdx => $composableBuilder(
    column: $table.toIdx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedLimitMps => $composableBuilder(
    column: $table.speedLimitMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roadClass => $composableBuilder(
    column: $table.roadClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wayId => $composableBuilder(
    column: $table.wayId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SegmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $SegmentsTable> {
  $$SegmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fromIdx => $composableBuilder(
    column: $table.fromIdx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get toIdx => $composableBuilder(
    column: $table.toIdx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedLimitMps => $composableBuilder(
    column: $table.speedLimitMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roadClass => $composableBuilder(
    column: $table.roadClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wayId => $composableBuilder(
    column: $table.wayId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SegmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SegmentsTable> {
  $$SegmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get fromIdx =>
      $composableBuilder(column: $table.fromIdx, builder: (column) => column);

  GeneratedColumn<int> get toIdx =>
      $composableBuilder(column: $table.toIdx, builder: (column) => column);

  GeneratedColumn<double> get speedLimitMps => $composableBuilder(
    column: $table.speedLimitMps,
    builder: (column) => column,
  );

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get roadClass =>
      $composableBuilder(column: $table.roadClass, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get wayId =>
      $composableBuilder(column: $table.wayId, builder: (column) => column);
}

class $$SegmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SegmentsTable,
          Segment,
          $$SegmentsTableFilterComposer,
          $$SegmentsTableOrderingComposer,
          $$SegmentsTableAnnotationComposer,
          $$SegmentsTableCreateCompanionBuilder,
          $$SegmentsTableUpdateCompanionBuilder,
          (Segment, BaseReferences<_$AppDatabase, $SegmentsTable, Segment>),
          Segment,
          PrefetchHooks Function()
        > {
  $$SegmentsTableTableManager(_$AppDatabase db, $SegmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SegmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SegmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SegmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> fromIdx = const Value.absent(),
                Value<int> toIdx = const Value.absent(),
                Value<double?> speedLimitMps = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<String> roadClass = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> wayId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SegmentsCompanion(
                tripId: tripId,
                fromIdx: fromIdx,
                toIdx: toIdx,
                speedLimitMps: speedLimitMps,
                confidence: confidence,
                roadClass: roadClass,
                name: name,
                wayId: wayId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int fromIdx,
                required int toIdx,
                Value<double?> speedLimitMps = const Value.absent(),
                required double confidence,
                required String roadClass,
                Value<String?> name = const Value.absent(),
                Value<String?> wayId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SegmentsCompanion.insert(
                tripId: tripId,
                fromIdx: fromIdx,
                toIdx: toIdx,
                speedLimitMps: speedLimitMps,
                confidence: confidence,
                roadClass: roadClass,
                name: name,
                wayId: wayId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SegmentsTable, Segment>(table),
                  BaseReferences<_$AppDatabase, $SegmentsTable, Segment>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SegmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SegmentsTable,
      Segment,
      $$SegmentsTableFilterComposer,
      $$SegmentsTableOrderingComposer,
      $$SegmentsTableAnnotationComposer,
      $$SegmentsTableCreateCompanionBuilder,
      $$SegmentsTableUpdateCompanionBuilder,
      (Segment, BaseReferences<_$AppDatabase, $SegmentsTable, Segment>),
      Segment,
      PrefetchHooks Function()
    >;
typedef $$TripScoresTableCreateCompanionBuilder =
    TripScoresCompanion Function({
      required String tripId,
      required String scoreJson,
      Value<int?> score,
      required int xp,
      required bool reckless,
      required bool scored,
      Value<String?> roastText,
      required int scoredAt,
      Value<int> rowid,
    });
typedef $$TripScoresTableUpdateCompanionBuilder =
    TripScoresCompanion Function({
      Value<String> tripId,
      Value<String> scoreJson,
      Value<int?> score,
      Value<int> xp,
      Value<bool> reckless,
      Value<bool> scored,
      Value<String?> roastText,
      Value<int> scoredAt,
      Value<int> rowid,
    });

class $$TripScoresTableFilterComposer
    extends Composer<_$AppDatabase, $TripScoresTable> {
  $$TripScoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scoreJson => $composableBuilder(
    column: $table.scoreJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get xp => $composableBuilder(
    column: $table.xp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reckless => $composableBuilder(
    column: $table.reckless,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get scored => $composableBuilder(
    column: $table.scored,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roastText => $composableBuilder(
    column: $table.roastText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scoredAt => $composableBuilder(
    column: $table.scoredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TripScoresTableOrderingComposer
    extends Composer<_$AppDatabase, $TripScoresTable> {
  $$TripScoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scoreJson => $composableBuilder(
    column: $table.scoreJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get xp => $composableBuilder(
    column: $table.xp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reckless => $composableBuilder(
    column: $table.reckless,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get scored => $composableBuilder(
    column: $table.scored,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roastText => $composableBuilder(
    column: $table.roastText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scoredAt => $composableBuilder(
    column: $table.scoredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TripScoresTableAnnotationComposer
    extends Composer<_$AppDatabase, $TripScoresTable> {
  $$TripScoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<String> get scoreJson =>
      $composableBuilder(column: $table.scoreJson, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get xp =>
      $composableBuilder(column: $table.xp, builder: (column) => column);

  GeneratedColumn<bool> get reckless =>
      $composableBuilder(column: $table.reckless, builder: (column) => column);

  GeneratedColumn<bool> get scored =>
      $composableBuilder(column: $table.scored, builder: (column) => column);

  GeneratedColumn<String> get roastText =>
      $composableBuilder(column: $table.roastText, builder: (column) => column);

  GeneratedColumn<int> get scoredAt =>
      $composableBuilder(column: $table.scoredAt, builder: (column) => column);
}

class $$TripScoresTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TripScoresTable,
          TripScoreRow,
          $$TripScoresTableFilterComposer,
          $$TripScoresTableOrderingComposer,
          $$TripScoresTableAnnotationComposer,
          $$TripScoresTableCreateCompanionBuilder,
          $$TripScoresTableUpdateCompanionBuilder,
          (
            TripScoreRow,
            BaseReferences<_$AppDatabase, $TripScoresTable, TripScoreRow>,
          ),
          TripScoreRow,
          PrefetchHooks Function()
        > {
  $$TripScoresTableTableManager(_$AppDatabase db, $TripScoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TripScoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TripScoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TripScoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<String> scoreJson = const Value.absent(),
                Value<int?> score = const Value.absent(),
                Value<int> xp = const Value.absent(),
                Value<bool> reckless = const Value.absent(),
                Value<bool> scored = const Value.absent(),
                Value<String?> roastText = const Value.absent(),
                Value<int> scoredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TripScoresCompanion(
                tripId: tripId,
                scoreJson: scoreJson,
                score: score,
                xp: xp,
                reckless: reckless,
                scored: scored,
                roastText: roastText,
                scoredAt: scoredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required String scoreJson,
                Value<int?> score = const Value.absent(),
                required int xp,
                required bool reckless,
                required bool scored,
                Value<String?> roastText = const Value.absent(),
                required int scoredAt,
                Value<int> rowid = const Value.absent(),
              }) => TripScoresCompanion.insert(
                tripId: tripId,
                scoreJson: scoreJson,
                score: score,
                xp: xp,
                reckless: reckless,
                scored: scored,
                roastText: roastText,
                scoredAt: scoredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TripScoresTable, TripScoreRow>(table),
                  BaseReferences<_$AppDatabase, $TripScoresTable, TripScoreRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TripScoresTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TripScoresTable,
      TripScoreRow,
      $$TripScoresTableFilterComposer,
      $$TripScoresTableOrderingComposer,
      $$TripScoresTableAnnotationComposer,
      $$TripScoresTableCreateCompanionBuilder,
      $$TripScoresTableUpdateCompanionBuilder,
      (
        TripScoreRow,
        BaseReferences<_$AppDatabase, $TripScoresTable, TripScoreRow>,
      ),
      TripScoreRow,
      PrefetchHooks Function()
    >;
typedef $$PacksTableCreateCompanionBuilder =
    PacksCompanion Function({
      required String region,
      required String name,
      required String osmTimestamp,
      required String path,
      required String sha256,
      required int bytes,
      required int wayCount,
      required double bboxMinLat,
      required double bboxMinLon,
      required double bboxMaxLat,
      required double bboxMaxLon,
      required int installedAt,
      Value<int> rowid,
    });
typedef $$PacksTableUpdateCompanionBuilder =
    PacksCompanion Function({
      Value<String> region,
      Value<String> name,
      Value<String> osmTimestamp,
      Value<String> path,
      Value<String> sha256,
      Value<int> bytes,
      Value<int> wayCount,
      Value<double> bboxMinLat,
      Value<double> bboxMinLon,
      Value<double> bboxMaxLat,
      Value<double> bboxMaxLon,
      Value<int> installedAt,
      Value<int> rowid,
    });

class $$PacksTableFilterComposer extends Composer<_$AppDatabase, $PacksTable> {
  $$PacksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get osmTimestamp => $composableBuilder(
    column: $table.osmTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wayCount => $composableBuilder(
    column: $table.wayCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxMinLat => $composableBuilder(
    column: $table.bboxMinLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxMinLon => $composableBuilder(
    column: $table.bboxMinLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxMaxLat => $composableBuilder(
    column: $table.bboxMaxLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxMaxLon => $composableBuilder(
    column: $table.bboxMaxLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PacksTableOrderingComposer
    extends Composer<_$AppDatabase, $PacksTable> {
  $$PacksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get osmTimestamp => $composableBuilder(
    column: $table.osmTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wayCount => $composableBuilder(
    column: $table.wayCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxMinLat => $composableBuilder(
    column: $table.bboxMinLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxMinLon => $composableBuilder(
    column: $table.bboxMinLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxMaxLat => $composableBuilder(
    column: $table.bboxMaxLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxMaxLon => $composableBuilder(
    column: $table.bboxMaxLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PacksTableAnnotationComposer
    extends Composer<_$AppDatabase, $PacksTable> {
  $$PacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get osmTimestamp => $composableBuilder(
    column: $table.osmTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<int> get wayCount =>
      $composableBuilder(column: $table.wayCount, builder: (column) => column);

  GeneratedColumn<double> get bboxMinLat => $composableBuilder(
    column: $table.bboxMinLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bboxMinLon => $composableBuilder(
    column: $table.bboxMinLon,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bboxMaxLat => $composableBuilder(
    column: $table.bboxMaxLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bboxMaxLon => $composableBuilder(
    column: $table.bboxMaxLon,
    builder: (column) => column,
  );

  GeneratedColumn<int> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );
}

class $$PacksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PacksTable,
          Pack,
          $$PacksTableFilterComposer,
          $$PacksTableOrderingComposer,
          $$PacksTableAnnotationComposer,
          $$PacksTableCreateCompanionBuilder,
          $$PacksTableUpdateCompanionBuilder,
          (Pack, BaseReferences<_$AppDatabase, $PacksTable, Pack>),
          Pack,
          PrefetchHooks Function()
        > {
  $$PacksTableTableManager(_$AppDatabase db, $PacksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PacksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PacksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> region = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> osmTimestamp = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int> bytes = const Value.absent(),
                Value<int> wayCount = const Value.absent(),
                Value<double> bboxMinLat = const Value.absent(),
                Value<double> bboxMinLon = const Value.absent(),
                Value<double> bboxMaxLat = const Value.absent(),
                Value<double> bboxMaxLon = const Value.absent(),
                Value<int> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PacksCompanion(
                region: region,
                name: name,
                osmTimestamp: osmTimestamp,
                path: path,
                sha256: sha256,
                bytes: bytes,
                wayCount: wayCount,
                bboxMinLat: bboxMinLat,
                bboxMinLon: bboxMinLon,
                bboxMaxLat: bboxMaxLat,
                bboxMaxLon: bboxMaxLon,
                installedAt: installedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String region,
                required String name,
                required String osmTimestamp,
                required String path,
                required String sha256,
                required int bytes,
                required int wayCount,
                required double bboxMinLat,
                required double bboxMinLon,
                required double bboxMaxLat,
                required double bboxMaxLon,
                required int installedAt,
                Value<int> rowid = const Value.absent(),
              }) => PacksCompanion.insert(
                region: region,
                name: name,
                osmTimestamp: osmTimestamp,
                path: path,
                sha256: sha256,
                bytes: bytes,
                wayCount: wayCount,
                bboxMinLat: bboxMinLat,
                bboxMinLon: bboxMinLon,
                bboxMaxLat: bboxMaxLat,
                bboxMaxLon: bboxMaxLon,
                installedAt: installedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PacksTable, Pack>(table),
                  BaseReferences<_$AppDatabase, $PacksTable, Pack>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PacksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PacksTable,
      Pack,
      $$PacksTableFilterComposer,
      $$PacksTableOrderingComposer,
      $$PacksTableAnnotationComposer,
      $$PacksTableCreateCompanionBuilder,
      $$PacksTableUpdateCompanionBuilder,
      (Pack, BaseReferences<_$AppDatabase, $PacksTable, Pack>),
      Pack,
      PrefetchHooks Function()
    >;
typedef $$LimitFlagsTableCreateCompanionBuilder =
    LimitFlagsCompanion Function({
      Value<int> id,
      required String wayId,
      Value<String?> region,
      Value<String?> tripId,
      required double suggestedMps,
      required int createdAt,
      Value<bool> synced,
    });
typedef $$LimitFlagsTableUpdateCompanionBuilder =
    LimitFlagsCompanion Function({
      Value<int> id,
      Value<String> wayId,
      Value<String?> region,
      Value<String?> tripId,
      Value<double> suggestedMps,
      Value<int> createdAt,
      Value<bool> synced,
    });

class $$LimitFlagsTableFilterComposer
    extends Composer<_$AppDatabase, $LimitFlagsTable> {
  $$LimitFlagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wayId => $composableBuilder(
    column: $table.wayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get suggestedMps => $composableBuilder(
    column: $table.suggestedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LimitFlagsTableOrderingComposer
    extends Composer<_$AppDatabase, $LimitFlagsTable> {
  $$LimitFlagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wayId => $composableBuilder(
    column: $table.wayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get suggestedMps => $composableBuilder(
    column: $table.suggestedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LimitFlagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LimitFlagsTable> {
  $$LimitFlagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get wayId =>
      $composableBuilder(column: $table.wayId, builder: (column) => column);

  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<double> get suggestedMps => $composableBuilder(
    column: $table.suggestedMps,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$LimitFlagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LimitFlagsTable,
          LimitFlag,
          $$LimitFlagsTableFilterComposer,
          $$LimitFlagsTableOrderingComposer,
          $$LimitFlagsTableAnnotationComposer,
          $$LimitFlagsTableCreateCompanionBuilder,
          $$LimitFlagsTableUpdateCompanionBuilder,
          (
            LimitFlag,
            BaseReferences<_$AppDatabase, $LimitFlagsTable, LimitFlag>,
          ),
          LimitFlag,
          PrefetchHooks Function()
        > {
  $$LimitFlagsTableTableManager(_$AppDatabase db, $LimitFlagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LimitFlagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LimitFlagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LimitFlagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> wayId = const Value.absent(),
                Value<String?> region = const Value.absent(),
                Value<String?> tripId = const Value.absent(),
                Value<double> suggestedMps = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<bool> synced = const Value.absent(),
              }) => LimitFlagsCompanion(
                id: id,
                wayId: wayId,
                region: region,
                tripId: tripId,
                suggestedMps: suggestedMps,
                createdAt: createdAt,
                synced: synced,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String wayId,
                Value<String?> region = const Value.absent(),
                Value<String?> tripId = const Value.absent(),
                required double suggestedMps,
                required int createdAt,
                Value<bool> synced = const Value.absent(),
              }) => LimitFlagsCompanion.insert(
                id: id,
                wayId: wayId,
                region: region,
                tripId: tripId,
                suggestedMps: suggestedMps,
                createdAt: createdAt,
                synced: synced,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LimitFlagsTable, LimitFlag>(table),
                  BaseReferences<_$AppDatabase, $LimitFlagsTable, LimitFlag>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LimitFlagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LimitFlagsTable,
      LimitFlag,
      $$LimitFlagsTableFilterComposer,
      $$LimitFlagsTableOrderingComposer,
      $$LimitFlagsTableAnnotationComposer,
      $$LimitFlagsTableCreateCompanionBuilder,
      $$LimitFlagsTableUpdateCompanionBuilder,
      (LimitFlag, BaseReferences<_$AppDatabase, $LimitFlagsTable, LimitFlag>),
      LimitFlag,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$FixBatchesTableCreateCompanionBuilder =
    FixBatchesCompanion Function({
      required String tripId,
      required int batchT,
      Value<int> rowid,
    });
typedef $$FixBatchesTableUpdateCompanionBuilder =
    FixBatchesCompanion Function({
      Value<String> tripId,
      Value<int> batchT,
      Value<int> rowid,
    });

class $$FixBatchesTableFilterComposer
    extends Composer<_$AppDatabase, $FixBatchesTable> {
  $$FixBatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get batchT => $composableBuilder(
    column: $table.batchT,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixBatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $FixBatchesTable> {
  $$FixBatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get batchT => $composableBuilder(
    column: $table.batchT,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixBatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FixBatchesTable> {
  $$FixBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get batchT =>
      $composableBuilder(column: $table.batchT, builder: (column) => column);
}

class $$FixBatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FixBatchesTable,
          FixBatche,
          $$FixBatchesTableFilterComposer,
          $$FixBatchesTableOrderingComposer,
          $$FixBatchesTableAnnotationComposer,
          $$FixBatchesTableCreateCompanionBuilder,
          $$FixBatchesTableUpdateCompanionBuilder,
          (
            FixBatche,
            BaseReferences<_$AppDatabase, $FixBatchesTable, FixBatche>,
          ),
          FixBatche,
          PrefetchHooks Function()
        > {
  $$FixBatchesTableTableManager(_$AppDatabase db, $FixBatchesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixBatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> batchT = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixBatchesCompanion(
                tripId: tripId,
                batchT: batchT,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int batchT,
                Value<int> rowid = const Value.absent(),
              }) => FixBatchesCompanion.insert(
                tripId: tripId,
                batchT: batchT,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FixBatchesTable, FixBatche>(table),
                  BaseReferences<_$AppDatabase, $FixBatchesTable, FixBatche>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixBatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FixBatchesTable,
      FixBatche,
      $$FixBatchesTableFilterComposer,
      $$FixBatchesTableOrderingComposer,
      $$FixBatchesTableAnnotationComposer,
      $$FixBatchesTableCreateCompanionBuilder,
      $$FixBatchesTableUpdateCompanionBuilder,
      (FixBatche, BaseReferences<_$AppDatabase, $FixBatchesTable, FixBatche>),
      FixBatche,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder =
    OutboxCompanion Function({
      required String id,
      required String kind,
      required String payload,
      required int createdAt,
      Value<int> attempts,
      Value<int> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$OutboxTableUpdateCompanionBuilder =
    OutboxCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<String> payload,
      Value<int> createdAt,
      Value<int> attempts,
      Value<int> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion(
                id: id,
                kind: kind,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String payload,
                required int createdAt,
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion.insert(
                id: id,
                kind: kind,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxData>(table),
                  BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;
typedef $$RemoteCacheTableCreateCompanionBuilder =
    RemoteCacheCompanion Function({
      required String key,
      required String json,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$RemoteCacheTableUpdateCompanionBuilder =
    RemoteCacheCompanion Function({
      Value<String> key,
      Value<String> json,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$RemoteCacheTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteCacheTable> {
  $$RemoteCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteCacheTable> {
  $$RemoteCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteCacheTable> {
  $$RemoteCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RemoteCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemoteCacheTable,
          RemoteCacheData,
          $$RemoteCacheTableFilterComposer,
          $$RemoteCacheTableOrderingComposer,
          $$RemoteCacheTableAnnotationComposer,
          $$RemoteCacheTableCreateCompanionBuilder,
          $$RemoteCacheTableUpdateCompanionBuilder,
          (
            RemoteCacheData,
            BaseReferences<_$AppDatabase, $RemoteCacheTable, RemoteCacheData>,
          ),
          RemoteCacheData,
          PrefetchHooks Function()
        > {
  $$RemoteCacheTableTableManager(_$AppDatabase db, $RemoteCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteCacheCompanion(
                key: key,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String json,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RemoteCacheCompanion.insert(
                key: key,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RemoteCacheTable, RemoteCacheData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RemoteCacheTable,
                    RemoteCacheData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemoteCacheTable,
      RemoteCacheData,
      $$RemoteCacheTableFilterComposer,
      $$RemoteCacheTableOrderingComposer,
      $$RemoteCacheTableAnnotationComposer,
      $$RemoteCacheTableCreateCompanionBuilder,
      $$RemoteCacheTableUpdateCompanionBuilder,
      (
        RemoteCacheData,
        BaseReferences<_$AppDatabase, $RemoteCacheTable, RemoteCacheData>,
      ),
      RemoteCacheData,
      PrefetchHooks Function()
    >;
typedef $$UploadedTripsTableCreateCompanionBuilder =
    UploadedTripsCompanion Function({
      required String tripId,
      required int uploadedAt,
      required String summaryHash,
      Value<int> rowid,
    });
typedef $$UploadedTripsTableUpdateCompanionBuilder =
    UploadedTripsCompanion Function({
      Value<String> tripId,
      Value<int> uploadedAt,
      Value<String> summaryHash,
      Value<int> rowid,
    });

class $$UploadedTripsTableFilterComposer
    extends Composer<_$AppDatabase, $UploadedTripsTable> {
  $$UploadedTripsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryHash => $composableBuilder(
    column: $table.summaryHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadedTripsTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadedTripsTable> {
  $$UploadedTripsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryHash => $composableBuilder(
    column: $table.summaryHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadedTripsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadedTripsTable> {
  $$UploadedTripsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summaryHash => $composableBuilder(
    column: $table.summaryHash,
    builder: (column) => column,
  );
}

class $$UploadedTripsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadedTripsTable,
          UploadedTrip,
          $$UploadedTripsTableFilterComposer,
          $$UploadedTripsTableOrderingComposer,
          $$UploadedTripsTableAnnotationComposer,
          $$UploadedTripsTableCreateCompanionBuilder,
          $$UploadedTripsTableUpdateCompanionBuilder,
          (
            UploadedTrip,
            BaseReferences<_$AppDatabase, $UploadedTripsTable, UploadedTrip>,
          ),
          UploadedTrip,
          PrefetchHooks Function()
        > {
  $$UploadedTripsTableTableManager(_$AppDatabase db, $UploadedTripsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadedTripsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadedTripsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadedTripsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> uploadedAt = const Value.absent(),
                Value<String> summaryHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadedTripsCompanion(
                tripId: tripId,
                uploadedAt: uploadedAt,
                summaryHash: summaryHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int uploadedAt,
                required String summaryHash,
                Value<int> rowid = const Value.absent(),
              }) => UploadedTripsCompanion.insert(
                tripId: tripId,
                uploadedAt: uploadedAt,
                summaryHash: summaryHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadedTripsTable, UploadedTrip>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $UploadedTripsTable,
                    UploadedTrip
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadedTripsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadedTripsTable,
      UploadedTrip,
      $$UploadedTripsTableFilterComposer,
      $$UploadedTripsTableOrderingComposer,
      $$UploadedTripsTableAnnotationComposer,
      $$UploadedTripsTableCreateCompanionBuilder,
      $$UploadedTripsTableUpdateCompanionBuilder,
      (
        UploadedTrip,
        BaseReferences<_$AppDatabase, $UploadedTripsTable, UploadedTrip>,
      ),
      UploadedTrip,
      PrefetchHooks Function()
    >;
typedef $$BadgeAwardsTableCreateCompanionBuilder =
    BadgeAwardsCompanion Function({
      required String badgeId,
      required int awardedAt,
      Value<bool> synced,
      Value<int> rowid,
    });
typedef $$BadgeAwardsTableUpdateCompanionBuilder =
    BadgeAwardsCompanion Function({
      Value<String> badgeId,
      Value<int> awardedAt,
      Value<bool> synced,
      Value<int> rowid,
    });

class $$BadgeAwardsTableFilterComposer
    extends Composer<_$AppDatabase, $BadgeAwardsTable> {
  $$BadgeAwardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get badgeId => $composableBuilder(
    column: $table.badgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get awardedAt => $composableBuilder(
    column: $table.awardedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BadgeAwardsTableOrderingComposer
    extends Composer<_$AppDatabase, $BadgeAwardsTable> {
  $$BadgeAwardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get badgeId => $composableBuilder(
    column: $table.badgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get awardedAt => $composableBuilder(
    column: $table.awardedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BadgeAwardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BadgeAwardsTable> {
  $$BadgeAwardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get badgeId =>
      $composableBuilder(column: $table.badgeId, builder: (column) => column);

  GeneratedColumn<int> get awardedAt =>
      $composableBuilder(column: $table.awardedAt, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$BadgeAwardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BadgeAwardsTable,
          BadgeAward,
          $$BadgeAwardsTableFilterComposer,
          $$BadgeAwardsTableOrderingComposer,
          $$BadgeAwardsTableAnnotationComposer,
          $$BadgeAwardsTableCreateCompanionBuilder,
          $$BadgeAwardsTableUpdateCompanionBuilder,
          (
            BadgeAward,
            BaseReferences<_$AppDatabase, $BadgeAwardsTable, BadgeAward>,
          ),
          BadgeAward,
          PrefetchHooks Function()
        > {
  $$BadgeAwardsTableTableManager(_$AppDatabase db, $BadgeAwardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BadgeAwardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BadgeAwardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BadgeAwardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> badgeId = const Value.absent(),
                Value<int> awardedAt = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BadgeAwardsCompanion(
                badgeId: badgeId,
                awardedAt: awardedAt,
                synced: synced,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String badgeId,
                required int awardedAt,
                Value<bool> synced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BadgeAwardsCompanion.insert(
                badgeId: badgeId,
                awardedAt: awardedAt,
                synced: synced,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BadgeAwardsTable, BadgeAward>(table),
                  BaseReferences<_$AppDatabase, $BadgeAwardsTable, BadgeAward>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BadgeAwardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BadgeAwardsTable,
      BadgeAward,
      $$BadgeAwardsTableFilterComposer,
      $$BadgeAwardsTableOrderingComposer,
      $$BadgeAwardsTableAnnotationComposer,
      $$BadgeAwardsTableCreateCompanionBuilder,
      $$BadgeAwardsTableUpdateCompanionBuilder,
      (
        BadgeAward,
        BaseReferences<_$AppDatabase, $BadgeAwardsTable, BadgeAward>,
      ),
      BadgeAward,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TripsTableTableManager get trips =>
      $$TripsTableTableManager(_db, _db.trips);
  $$SamplesTableTableManager get samples =>
      $$SamplesTableTableManager(_db, _db.samples);
  $$MotionPeaksTableTableManager get motionPeaks =>
      $$MotionPeaksTableTableManager(_db, _db.motionPeaks);
  $$PhoneEventsTableTableManager get phoneEvents =>
      $$PhoneEventsTableTableManager(_db, _db.phoneEvents);
  $$SegmentsTableTableManager get segments =>
      $$SegmentsTableTableManager(_db, _db.segments);
  $$TripScoresTableTableManager get tripScores =>
      $$TripScoresTableTableManager(_db, _db.tripScores);
  $$PacksTableTableManager get packs =>
      $$PacksTableTableManager(_db, _db.packs);
  $$LimitFlagsTableTableManager get limitFlags =>
      $$LimitFlagsTableTableManager(_db, _db.limitFlags);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$FixBatchesTableTableManager get fixBatches =>
      $$FixBatchesTableTableManager(_db, _db.fixBatches);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$RemoteCacheTableTableManager get remoteCache =>
      $$RemoteCacheTableTableManager(_db, _db.remoteCache);
  $$UploadedTripsTableTableManager get uploadedTrips =>
      $$UploadedTripsTableTableManager(_db, _db.uploadedTrips);
  $$BadgeAwardsTableTableManager get badgeAwards =>
      $$BadgeAwardsTableTableManager(_db, _db.badgeAwards);
}

/// CarPlay groundwork (docs/04 §2).
///
/// Apple grants the Driving Task entitlement per app and nothing here reaches
/// a car until it does. What we can build now, and test, is the *plan*: the
/// four tabs, their rows and their buttons, as plain data mapped from the same
/// frame the Live Activity shows. When the entitlement lands, a Swift
/// `CPTemplateApplicationSceneDelegate` reads a [CarPlayPlan] off a method
/// channel and renders it with `CPInformationTemplate`, `CPListTemplate`,
/// `CPGridTemplate` and `CPPointOfInterestTemplate`; the Dart side does not
/// change.
///
/// Car rules baked in here: a row is one short line, no scores, no roasts,
/// alerts only for convoy events (docs/04 §2 "Rules we follow").
library;

import 'package:flutter/foundation.dart';

import 'live_activity.dart' show LiveActivityContent;

/// Longest string CarPlay shows without truncating on the smallest head unit.
const int carPlayMaxChars = 40;

enum CarPlayTemplateKind { information, list, grid, pointOfInterest }

/// Button or list-row action the Swift side maps to a handler.
enum CarPlayAction {
  markPassenger,
  regroupHere,
  proposeStop,
  pushToTalk,
  openStop,
}

@immutable
class CarPlayItem {
  const CarPlayItem(this.title, {this.detail, this.action, this.stopId});

  final String title;
  final String? detail;
  final CarPlayAction? action;

  /// For [CarPlayAction.openStop].
  final String? stopId;

  Map<String, Object?> toMap() => {
    'title': title,
    'detail': ?detail,
    'action': ?action?.name,
    'stopId': ?stopId,
  };
}

@immutable
class CarPlayTemplate {
  const CarPlayTemplate({
    required this.kind,
    required this.title,
    this.items = const [],
    this.actions = const [],
  });

  final CarPlayTemplateKind kind;
  final String title;
  final List<CarPlayItem> items;
  final List<CarPlayItem> actions;

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'title': title,
    'items': [for (final i in items) i.toMap()],
    'actions': [for (final a in actions) a.toMap()],
  };
}

/// A convoy member as the Convoy tab lists them.
@immutable
class CarPlayMember {
  const CarPlayMember({
    required this.name,
    this.gapMinutes,
    this.etaMinutes,
    this.lost = false,
  });

  final String name;
  final int? gapMinutes;
  final int? etaMinutes;
  final bool lost;
}

/// A proposed or agreed stop as a pin on Apple's map.
@immutable
class CarPlayStop {
  const CarPlayStop({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.votes = 0,
    this.agreed = false,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final int votes;
  final bool agreed;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lon': lon,
    'votes': votes,
    'agreed': agreed,
  };
}

/// Everything the CarPlay scene would render, as data.
@immutable
class CarPlayPlan {
  const CarPlayPlan({
    required this.drive,
    required this.convoy,
    required this.talk,
    required this.stops,
    this.stopPins = const [],
  });

  /// Builds the four tabs from the Live Activity frame plus convoy detail the
  /// frame does not carry. A null frame is the parked state.
  factory CarPlayPlan.from(
    LiveActivityContent? frame, {
    List<CarPlayMember> members = const [],
    List<CarPlayStop> stops = const [],
    String? lastTalker,
    int? lastTalkAgoSeconds,
  }) {
    final driveRows = <CarPlayItem>[];
    if (frame == null) {
      driveRows.add(const CarPlayItem('Parked'));
    } else {
      driveRows.add(
        CarPlayItem(
          frame.cleanSoFar ? 'Clean so far' : 'Recording',
          detail: '${frame.tripMinutes} min',
        ),
      );
      final limit = frame.limitPosted;
      final road = frame.roadName;
      if (limit != null) {
        final speed = frame.speedPosted;
        final over = frame.overBy;
        driveRows.add(
          CarPlayItem(
            'Limit $limit ${frame.limitUnit}',
            detail: speed == null
                ? road
                : over != null
                ? '$speed, $over over'
                : '$speed ${frame.limitUnit}',
          ),
        );
      } else if (road != null) {
        driveRows.add(CarPlayItem(road));
      }
    }
    final drive = CarPlayTemplate(
      kind: CarPlayTemplateKind.information,
      title: 'Drive',
      items: _clip(driveRows),
      actions: frame == null
          ? const []
          : const [
              CarPlayItem(
                'Mark passenger',
                action: CarPlayAction.markPassenger,
              ),
            ],
    );

    final inConvoy = frame?.convoyName != null;
    final memberRows = [
      for (final m in members)
        CarPlayItem(
          m.lost ? '${m.name} · lost' : m.name,
          detail: _memberDetail(m),
        ),
    ];
    final convoy = CarPlayTemplate(
      kind: CarPlayTemplateKind.list,
      title: 'Convoy',
      items: _clip(
        !inConvoy
            ? const [CarPlayItem('No active convoy')]
            : memberRows.isEmpty
            ? const [CarPlayItem('Waiting for positions')]
            : memberRows,
      ),
      actions: inConvoy
          ? const [
              CarPlayItem('Regroup here', action: CarPlayAction.regroupHere),
              CarPlayItem('Propose stop', action: CarPlayAction.proposeStop),
            ]
          : const [],
    );

    final talking = frame?.talking;
    final talkDetail = talking != null
        ? '$talking talking'
        : lastTalker != null && lastTalkAgoSeconds != null
        ? 'Last: $lastTalker, ${_ago(lastTalkAgoSeconds)}'
        : null;
    final talk = CarPlayTemplate(
      kind: CarPlayTemplateKind.grid,
      title: 'Talk',
      items: _clip([
        if (inConvoy)
          CarPlayItem(
            'Hold to talk',
            detail: talkDetail,
            action: CarPlayAction.pushToTalk,
          )
        else
          const CarPlayItem('Join a convoy to talk'),
      ]),
    );

    final stopsTemplate = CarPlayTemplate(
      kind: CarPlayTemplateKind.pointOfInterest,
      title: 'Stops',
      items: _clip([
        for (final s in stops)
          CarPlayItem(
            s.name,
            detail: s.agreed
                ? 'Agreed'
                : s.votes == 1
                ? '1 vote'
                : '${s.votes} votes',
            action: CarPlayAction.openStop,
            stopId: s.id,
          ),
        if (stops.isEmpty)
          CarPlayItem(inConvoy ? 'No stops yet' : 'No active convoy'),
      ]),
    );

    return CarPlayPlan(
      drive: drive,
      convoy: convoy,
      talk: talk,
      stops: stopsTemplate,
      stopPins: stops,
    );
  }

  final CarPlayTemplate drive;
  final CarPlayTemplate convoy;
  final CarPlayTemplate talk;
  final CarPlayTemplate stops;
  final List<CarPlayStop> stopPins;

  List<CarPlayTemplate> get tabs => [drive, convoy, talk, stops];

  Map<String, Object?> toMap() => {
    'tabs': [for (final t in tabs) t.toMap()],
    'pins': [for (final p in stopPins) p.toMap()],
  };

  static String? _memberDetail(CarPlayMember m) {
    final parts = <String>[];
    final gap = m.gapMinutes;
    if (gap != null) parts.add(gap <= 0 ? 'leading' : '$gap min behind');
    if (m.etaMinutes != null) parts.add('ETA ${m.etaMinutes} min');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _ago(int seconds) {
    if (seconds < 60) return '$seconds s ago';
    final m = seconds ~/ 60;
    return m == 1 ? '1 min ago' : '$m min ago';
  }

  /// Shortens every string to [carPlayMaxChars]; a car row never wraps.
  static List<CarPlayItem> _clip(List<CarPlayItem> items) => [
    for (final i in items)
      CarPlayItem(
        clipForCar(i.title),
        detail: i.detail == null ? null : clipForCar(i.detail!),
        action: i.action,
        stopId: i.stopId,
      ),
  ];
}

/// Truncates with an ellipsis at [carPlayMaxChars].
String clipForCar(String s) =>
    s.length <= carPlayMaxChars ? s : '${s.substring(0, carPlayMaxChars - 1)}…';

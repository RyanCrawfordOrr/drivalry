import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../tracking/tracking_models.dart';
import '../db/database.dart';
import '../sync/outbox.dart';
import 'crash_sms.dart';

/// What was sent, kept locally until the driver confirms they are OK.
class CrashAlertRecord {
  const CrashAlertRecord({
    required this.alertId,
    required this.tripId,
    required this.t,
    required this.lat,
    required this.lon,
    required this.createdAt,
    required this.contactsTexted,
    required this.cloudSent,
  });

  factory CrashAlertRecord.fromJson(Map<String, dynamic> j) => CrashAlertRecord(
    alertId: j['alertId'] as String,
    tripId: j['tripId'] as String,
    t: (j['t'] as num).toInt(),
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    createdAt: (j['createdAt'] as num).toInt(),
    contactsTexted: (j['contactsTexted'] as num?)?.toInt() ?? 0,
    cloudSent: j['cloudSent'] as bool? ?? false,
  );

  /// Client-generated id of the `crash_alerts` row (also the outbox id).
  final String alertId;
  final String tripId;

  /// Epoch ms of the impact.
  final int t;
  final double lat;
  final double lon;
  final int createdAt;
  final int contactsTexted;

  /// True when the row reached Supabase directly; false when it is still in
  /// the outbox.
  final bool cloudSent;

  Map<String, dynamic> toJson() => {
    'alertId': alertId,
    'tripId': tripId,
    't': t,
    'lat': lat,
    'lon': lon,
    'createdAt': createdAt,
    'contactsTexted': contactsTexted,
    'cloudSent': cloudSent,
  };

  static CrashAlertRecord? tryParse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return CrashAlertRecord.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Sends the alert when a countdown runs out (docs/01 §4.5): a `crash_alerts`
/// row (the push Edge Function fans it out to circle members and linked
/// contacts) and one prefilled SMS to every emergency contact. Never a phone
/// call. The cloud write goes straight to Supabase because it must leave now;
/// only when that fails does it fall back to the outbox.
class CrashEscalator {
  CrashEscalator(
    this._db, {
    required SupabaseClient? Function() clientOf,
    required String? Function() userIdOf,
    required OutboxWorker outboxWorker,
    required String Function() nameOf,
    Future<bool> Function(Uri uri)? launch,
    bool Function()? isIos,
    int Function()? now,
  }) : _client = clientOf,
       _userId = userIdOf,
       _outbox = outboxWorker,
       _displayName = nameOf,
       _launch = launch ?? _defaultLaunch,
       _isIos = isIos ?? (() => !kIsWeb && Platform.isIOS),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const kindAlert = 'crash_alert';
  static const kindResolve = 'crash_resolve';

  final AppDatabase _db;
  final SupabaseClient? Function() _client;
  final String? Function() _userId;
  final OutboxWorker _outbox;
  final String Function() _displayName;
  final Future<bool> Function(Uri uri) _launch;
  final bool Function() _isIos;
  final int Function() _now;

  static Future<bool> _defaultLaunch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Outbox fallbacks for the two cloud writes.
  void registerHandlers() {
    _outbox.register(kindAlert, (p) async {
      final c = _client();
      final uid = _userId();
      if (c == null || uid == null) throw const OutboxRetryLater('signed out');
      await c
          .from('crash_alerts')
          .upsert(
            {
              'id': p['id'],
              'user_id': uid,
              'lat': p['lat'],
              'lon': p['lon'],
              'notify_user_ids': p['notify_user_ids'] ?? const <String>[],
            },
            onConflict: 'id',
            ignoreDuplicates: true,
          );
    });
    _outbox.register(kindResolve, (p) async {
      final c = _client();
      if (c == null || _userId() == null) {
        throw const OutboxRetryLater('signed out');
      }
      await c
          .from('crash_alerts')
          .update({'resolved_at': p['resolved_at']})
          .eq('id', p['id']);
    });
  }

  /// Sends everything and returns what was sent. Never throws: a failed SMS
  /// launch or a failed cloud write is logged and the record says so.
  Future<CrashAlertRecord> escalate(CrashCandidateEvent e) async {
    final alertId = const Uuid().v4();
    final contacts = await _db.allEmergencyContacts();
    final linked = [
      for (final c in contacts)
        if (c.userId != null && c.userId!.isNotEmpty) c.userId!,
    ];

    var cloudSent = false;
    final c = _client();
    final uid = _userId();
    if (c != null && uid != null) {
      try {
        await c.from('crash_alerts').insert({
          'id': alertId,
          'user_id': uid,
          'lat': e.lat,
          'lon': e.lon,
          'notify_user_ids': linked,
        });
        cloudSent = true;
      } catch (err) {
        debugPrint('crash alert insert failed, queueing: $err');
      }
    }
    if (!cloudSent) {
      await _outbox.enqueue(kindAlert, {
        'id': alertId,
        'lat': e.lat,
        'lon': e.lon,
        'notify_user_ids': linked,
      }, id: alertId);
    }

    var texted = 0;
    final numbers = [for (final k in contacts) k.phone];
    if (numbers.isNotEmpty) {
      final uri = crashSmsUri(
        numbers: numbers,
        body: crashMessage(name: _displayName(), lat: e.lat, lon: e.lon),
        ios: _isIos(),
      );
      try {
        if (await _launch(uri)) texted = numbers.length;
      } catch (err) {
        debugPrint('crash SMS composer failed: $err');
      }
    }

    return CrashAlertRecord(
      alertId: alertId,
      tripId: e.tripId!,
      t: e.t,
      lat: e.lat,
      lon: e.lon,
      createdAt: _now(),
      contactsTexted: texted,
      cloudSent: cloudSent,
    );
  }

  /// Marks the cloud row resolved (friends' apps stop showing it).
  Future<void> resolve(CrashAlertRecord r) async {
    final resolvedAt = DateTime.fromMillisecondsSinceEpoch(
      _now(),
      isUtc: true,
    ).toIso8601String();
    final c = _client();
    if (c != null && _userId() != null) {
      try {
        await c
            .from('crash_alerts')
            .update({'resolved_at': resolvedAt})
            .eq('id', r.alertId);
        return;
      } catch (err) {
        debugPrint('crash alert resolve failed, queueing: $err');
      }
    }
    await _outbox.enqueue(kindResolve, {
      'id': r.alertId,
      'resolved_at': resolvedAt,
    }, id: 'crash_resolve:${r.alertId}');
  }
}
